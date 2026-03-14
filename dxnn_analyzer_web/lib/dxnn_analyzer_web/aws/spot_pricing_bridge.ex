defmodule DxnnAnalyzerWeb.AWS.SpotPricingBridge do
  @moduledoc """
  Bridge for fetching AWS spot instance pricing data.
  Focuses on compute-optimized instances suitable for DXNN workloads.
  """

  # Instance types suitable for DXNN (compute-optimized and general purpose)
  @dxnn_instance_types [
    # T3 - Dev/test only
    "t3.xlarge",
    # C7i - Latest compute-optimized (Intel 4th gen)
    "c7i.xlarge", "c7i.2xlarge", "c7i.4xlarge", "c7i.8xlarge", "c7i.12xlarge", "c7i.16xlarge", "c7i.24xlarge",
    # C6i - Compute-optimized (Intel 3rd gen)
    "c6i.xlarge", "c6i.2xlarge", "c6i.4xlarge", "c6i.8xlarge", "c6i.12xlarge", "c6i.16xlarge", "c6i.24xlarge",
    # C5 - Compute-optimized
    "c5.xlarge", "c5.2xlarge", "c5.4xlarge", "c5.9xlarge", "c5.12xlarge",
    # M5 - General purpose (balanced)
    "m5.xlarge", "m5.2xlarge", "m5.4xlarge", "m5.8xlarge"
  ]

  # Regions to check for lowest pricing
  @regions [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-west-1", "eu-central-1", "ap-southeast-1"
  ]

  # Instance specs (vCPUs and Memory)
  @instance_specs %{
    # T3 - Dev/test
    "t3.xlarge" => %{vcpus: 4, memory: 16, family: "T3 (Burstable)"},
    # C7i - Latest compute-optimized
    "c7i.xlarge" => %{vcpus: 4, memory: 8, family: "C7i (Compute)"},
    "c7i.2xlarge" => %{vcpus: 8, memory: 16, family: "C7i (Compute)"},
    "c7i.4xlarge" => %{vcpus: 16, memory: 32, family: "C7i (Compute)"},
    "c7i.8xlarge" => %{vcpus: 32, memory: 64, family: "C7i (Compute)"},
    "c7i.12xlarge" => %{vcpus: 48, memory: 96, family: "C7i (Compute)"},
    "c7i.16xlarge" => %{vcpus: 64, memory: 128, family: "C7i (Compute)"},
    "c7i.24xlarge" => %{vcpus: 96, memory: 192, family: "C7i (Compute)"},
    # C6i - Compute-optimized
    "c6i.xlarge" => %{vcpus: 4, memory: 8, family: "C6i (Compute)"},
    "c6i.2xlarge" => %{vcpus: 8, memory: 16, family: "C6i (Compute)"},
    "c6i.4xlarge" => %{vcpus: 16, memory: 32, family: "C6i (Compute)"},
    "c6i.8xlarge" => %{vcpus: 32, memory: 64, family: "C6i (Compute)"},
    "c6i.12xlarge" => %{vcpus: 48, memory: 96, family: "C6i (Compute)"},
    "c6i.16xlarge" => %{vcpus: 64, memory: 128, family: "C6i (Compute)"},
    "c6i.24xlarge" => %{vcpus: 96, memory: 192, family: "C6i (Compute)"},
    # C5 - Compute-optimized
    "c5.xlarge" => %{vcpus: 4, memory: 8, family: "C5 (Compute)"},
    "c5.2xlarge" => %{vcpus: 8, memory: 16, family: "C5 (Compute)"},
    "c5.4xlarge" => %{vcpus: 16, memory: 32, family: "C5 (Compute)"},
    "c5.9xlarge" => %{vcpus: 36, memory: 72, family: "C5 (Compute)"},
    "c5.12xlarge" => %{vcpus: 48, memory: 96, family: "C5 (Compute)"},
    # M5 - General purpose
    "m5.xlarge" => %{vcpus: 4, memory: 16, family: "M5 (General)"},
    "m5.2xlarge" => %{vcpus: 8, memory: 32, family: "M5 (General)"},
    "m5.4xlarge" => %{vcpus: 16, memory: 64, family: "M5 (General)"},
    "m5.8xlarge" => %{vcpus: 32, memory: 128, family: "M5 (General)"}
  }

  def get_spot_pricing do
    require Logger
    Logger.info("Starting spot pricing fetch for #{length(@dxnn_instance_types)} instance types")
    
    # Fetch all prices in parallel using tasks for speed
    tasks = Enum.map(@dxnn_instance_types, fn instance_type ->
      Task.async(fn ->
        specs = Map.get(@instance_specs, instance_type, %{vcpus: "?", memory: "?", family: "Unknown"})
        
        # Get us-east-1 price
        us_east_1_price = get_spot_price(instance_type, "us-east-1")
        
        # Get lowest price across select regions (fewer regions for speed)
        {lowest_price, lowest_region} = get_lowest_price_fast(instance_type)
        
        %{
          instance_type: instance_type,
          family: specs.family,
          vcpus: specs.vcpus,
          memory: specs.memory,
          us_east_1_price: us_east_1_price,
          lowest_price: lowest_price,
          lowest_region: lowest_region
        }
      end)
    end)
    
    # Wait for all tasks with longer timeout
    pricing_data = Task.await_many(tasks, 60_000)
    
    Logger.info("Successfully fetched pricing for #{length(pricing_data)} instances")
    {:ok, pricing_data}
  rescue
    e -> 
      Logger.error("Failed to fetch pricing: #{Exception.message(e)}")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      {:error, "Failed to fetch pricing: #{Exception.message(e)}"}
  end

  defp get_spot_price(instance_type, region) do
    require Logger
    
    case System.cmd("aws", [
      "ec2", "describe-spot-price-history",
      "--instance-types", instance_type,
      "--region", region,
      "--max-items", "1",
      "--output", "json"
    ], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"SpotPriceHistory" => [first | _]}} ->
            price = first["SpotPrice"]
            if price && price != "" do
              format_price(price)
            else
              Logger.debug("No price data for #{instance_type} in #{region}")
              nil
            end
          {:ok, %{"SpotPriceHistory" => []}} ->
            Logger.debug("Empty price history for #{instance_type} in #{region}")
            nil
          {:error, reason} ->
            Logger.warning("JSON parse error for #{instance_type} in #{region}: #{inspect(reason)}")
            nil
        end
      {error, code} ->
        Logger.warning("AWS CLI error for #{instance_type} in #{region} (exit #{code}): #{String.slice(error, 0, 100)}")
        nil
    end
  end

  defp get_lowest_price_fast(instance_type) do
    # Only check 3 popular regions for speed
    fast_regions = ["us-east-1", "us-west-2", "eu-west-1"]
    
    # Fetch prices in parallel for speed
    tasks = Enum.map(fast_regions, fn region ->
      Task.async(fn ->
        price = get_spot_price(instance_type, region)
        {price, region}
      end)
    end)
    
    prices = Task.await_many(tasks, 30_000)
    |> Enum.filter(fn {price, _region} -> price != nil end)
    
    case prices do
      [] -> {nil, nil}
      prices ->
        {lowest_price, lowest_region} = Enum.min_by(prices, fn {price, _region} -> 
          String.to_float(price)
        end)
        {lowest_price, lowest_region}
    end
  catch
    :exit, {:timeout, _} ->
      require Logger
      Logger.warning("Timeout finding lowest price for #{instance_type}")
      {nil, nil}
  end

  defp format_price(price_string) do
    case Float.parse(price_string) do
      {price, _} -> Float.round(price, 4) |> Float.to_string()
      :error -> price_string
    end
  end
end
