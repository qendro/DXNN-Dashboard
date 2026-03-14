defmodule DxnnAnalyzerWeb.AWS.SpotPricingBridge do
  @moduledoc """
  Bridge for fetching AWS spot instance pricing data.
  Focuses on compute-optimized instances suitable for DXNN workloads.
  """

  # Instance types suitable for DXNN (compute-optimized and general purpose)
  @dxnn_instance_types [
    "c7i.xlarge", "c7i.2xlarge", "c7i.4xlarge",
    "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge",
    "m5.large", "m5.xlarge", "m5.2xlarge",
    "t3.medium", "t3.large", "t3.xlarge",
    "t2.medium", "t2.large"
  ]

  # Regions to check for lowest pricing
  @regions [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-west-1", "eu-central-1", "ap-southeast-1"
  ]

  # Instance specs (vCPUs and Memory)
  @instance_specs %{
    "c7i.xlarge" => %{vcpus: 4, memory: 8, family: "C7i (Compute)"},
    "c7i.2xlarge" => %{vcpus: 8, memory: 16, family: "C7i (Compute)"},
    "c7i.4xlarge" => %{vcpus: 16, memory: 32, family: "C7i (Compute)"},
    "c5.large" => %{vcpus: 2, memory: 4, family: "C5 (Compute)"},
    "c5.xlarge" => %{vcpus: 4, memory: 8, family: "C5 (Compute)"},
    "c5.2xlarge" => %{vcpus: 8, memory: 16, family: "C5 (Compute)"},
    "c5.4xlarge" => %{vcpus: 16, memory: 32, family: "C5 (Compute)"},
    "m5.large" => %{vcpus: 2, memory: 8, family: "M5 (General)"},
    "m5.xlarge" => %{vcpus: 4, memory: 16, family: "M5 (General)"},
    "m5.2xlarge" => %{vcpus: 8, memory: 32, family: "M5 (General)"},
    "t3.medium" => %{vcpus: 2, memory: 4, family: "T3 (Burstable)"},
    "t3.large" => %{vcpus: 2, memory: 8, family: "T3 (Burstable)"},
    "t3.xlarge" => %{vcpus: 4, memory: 16, family: "T3 (Burstable)"},
    "t2.medium" => %{vcpus: 2, memory: 4, family: "T2 (Burstable)"},
    "t2.large" => %{vcpus: 2, memory: 8, family: "T2 (Burstable)"}
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
