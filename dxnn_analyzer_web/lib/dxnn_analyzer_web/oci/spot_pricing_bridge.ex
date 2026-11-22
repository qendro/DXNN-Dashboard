defmodule DxnnAnalyzerWeb.OCI.SpotPricingBridge do
  @moduledoc """
  Oracle public USD PAYG CPU/GPU rates and supported preemptible estimates.

  Prices come from Oracle's documented public catalog, without cloud credentials.
  Eligible preemptible shapes cost 50% of PAYG list rates. Account discounts,
  free-tier allowances, storage, licenses, and regional capacity are not inferred.
  """

  @catalog_url "https://apexapps.oracle.com/pls/apex/cetools/api/v1/products/?currencyCode=USD"
  @preemptible_factor 0.5
  # CPU Flex shapes explicitly listed in Oracle's preemptible docs.
  # SKU IDs prevent confusing public OCI with similarly named Cloud@Customer SKUs.
  @shapes [
    %{
      shape: "VM.Standard.E4.Flex",
      processor: "AMD E4",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      cpu_sku: "B93113",
      memory_sku: "B93114",
      max_ocpus: 64,
      max_memory: 1024
    },
    %{
      shape: "VM.Standard.E5.Flex",
      processor: "AMD E5",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      cpu_sku: "B97384",
      memory_sku: "B97385",
      max_ocpus: 126,
      max_memory: 1049
    },
    %{
      shape: "VM.Standard.E6.Flex",
      processor: "AMD E6",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      cpu_sku: "B111129",
      memory_sku: "B111130",
      max_ocpus: 126,
      max_memory: 1454
    },
    %{
      shape: "VM.Standard3.Flex",
      processor: "Intel X9",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      cpu_sku: "B94176",
      memory_sku: "B94177",
      max_ocpus: 32,
      max_memory: 512
    },
    %{
      shape: "VM.Optimized3.Flex",
      processor: "Intel X9 optimized",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      cpu_sku: "B93311",
      memory_sku: "B93312",
      max_ocpus: 18,
      max_memory: 256
    },
    %{
      shape: "VM.Standard.A1.Flex",
      processor: "Ampere Altra A1",
      architecture: "aarch64",
      vcpus_per_ocpu: 1,
      cpu_sku: "B93297",
      memory_sku: "B93298",
      max_ocpus: 76,
      max_memory: 472
    },
    %{
      shape: "VM.Standard.A4.Flex",
      processor: "AmpereOne M A4",
      architecture: "aarch64",
      vcpus_per_ocpu: 2,
      cpu_sku: "B112145",
      memory_sku: "B112146",
      max_ocpus: 45,
      max_memory: 700
    },
    %{
      shape: "VM.GPU.A10.1",
      processor: "NVIDIA A10 · Intel X9",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      gpu_sku: "B95909",
      gpus: 1,
      gpu_memory: 24,
      fixed_ocpus: 15,
      fixed_memory: 240,
      preemptible_supported: false,
      eligibility_note: "A10 is not listed in Oracle's preemptible support list"
    },
    %{
      shape: "VM.GPU.A10.2",
      processor: "NVIDIA A10 · Intel X9",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      gpu_sku: "B95909",
      gpus: 2,
      gpu_memory: 24,
      fixed_ocpus: 30,
      fixed_memory: 480,
      preemptible_supported: false,
      eligibility_note: "A10 is not listed in Oracle's preemptible support list"
    },
    %{
      shape: "VM.GPU3.1",
      processor: "NVIDIA V100 · Intel X7",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      gpu_sku: "B89734",
      gpus: 1,
      gpu_memory: 16,
      fixed_ocpus: 6,
      fixed_memory: 90,
      preemptible_supported: true,
      eligibility_note: nil
    },
    %{
      shape: "VM.GPU2.1",
      processor: "NVIDIA P100 · Intel X7",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      gpu_sku: "B88518",
      gpus: 1,
      gpu_memory: 16,
      fixed_ocpus: 12,
      fixed_memory: 72,
      preemptible_supported: true,
      eligibility_note: nil
    },
    %{
      shape: "BM.GPU.L40S.4",
      processor: "NVIDIA L40S · Intel Sapphire Rapids",
      architecture: "x86_64",
      vcpus_per_ocpu: 2,
      gpu_sku: "B109479",
      gpus: 4,
      gpu_memory: 48,
      fixed_ocpus: 112,
      fixed_memory: 1024,
      preemptible_supported: false,
      eligibility_note: "Bare-metal instances do not support preemptible capacity"
    }
  ]

  def catalog_url, do: @catalog_url

  def fetch_catalog do
    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 5,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(
           :get,
           {String.to_charlist(@catalog_url), []},
           [timeout: 15_000, connect_timeout: 5_000, ssl: ssl],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _, body}} ->
        decode_catalog(body)

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "Oracle's price catalog returned HTTP #{status}. Try refreshing again."}

      {:error, _} ->
        {:error, "Could not reach Oracle's price catalog. Check network access and try again."}
    end
  rescue
    _ ->
      {:error, "Could not load Oracle pricing. Check HTTPS connectivity and certificate trust."}
  end

  def decode_catalog(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"items" => items} = payload} when is_list(items) ->
        rows = Enum.map(@shapes, &shape_rates(&1, items))

        if Enum.any?(rows, &is_nil(&1.error)) do
          {:ok,
           %{
             rates: rows,
             catalog_updated_at: catalog_date(payload["lastUpdated"]),
             fetched_at: DateTime.utc_now()
           }}
        else
          {:error,
           "Oracle's catalog did not contain usable compute rates for the supported shapes."}
        end

      _ ->
        {:error, "Oracle returned an unexpected price catalog format."}
    end
  end

  def quote(catalog, ocpus, memory, hours)
      when is_integer(ocpus) and ocpus in 1..126 and is_integer(memory) and memory in 1..1454 and
             is_integer(hours) and hours in 1..744 do
    if memory < ocpus do
      {:error, "Choose at least 1 GB of memory per OCPU."}
    else
      rows =
        Enum.map(catalog.rates, fn rate ->
          {row_ocpus, row_memory} =
            if rate.kind == :gpu, do: {rate.fixed_ocpus, rate.fixed_memory}, else: {ocpus, memory}

          reason =
            cond do
              rate.error ->
                rate.error

              rate.kind == :gpu ->
                nil

              ocpus > rate.max_ocpus ->
                "Maximum #{rate.max_ocpus} OCPUs"

              memory > min(ocpus * 64, rate.max_memory) ->
                "Memory exceeds this shape's standard limits"

              true ->
                nil
            end

          on_demand =
            if reason == nil do
              if rate.kind == :gpu,
                do: rate.gpus * rate.gpu_rate,
                else: ocpus * rate.cpu_rate + memory * rate.memory_rate
            end

          preemptible =
            if on_demand && rate.preemptible_supported, do: on_demand * @preemptible_factor

          vcpus = row_ocpus * rate.vcpus_per_ocpu

          Map.merge(rate, %{
            ocpus: row_ocpus,
            memory: row_memory,
            vcpus: vcpus,
            reason: reason,
            on_demand: on_demand,
            on_demand_monthly: if(on_demand, do: on_demand * hours),
            preemptible: preemptible,
            monthly: if(preemptible, do: preemptible * hours),
            per_vcpu: if(preemptible, do: preemptible / vcpus),
            per_gb: if(preemptible, do: preemptible / row_memory),
            per_gpu: if(preemptible && rate.gpus > 0, do: preemptible / rate.gpus)
          })
        end)

      {:ok, rows}
    end
  end

  def quote(_, _, _, _),
    do: {:error, "Use 1–126 whole OCPUs, 1–1454 GB memory, and 1–744 hours per month."}

  defp shape_rates(%{gpu_sku: sku} = shape, items) do
    rate =
      case unit_rate(items, sku, :gpu) do
        {:ok, value} -> %{gpu_rate: value, error: nil}
        {:error, reason} -> %{gpu_rate: nil, error: reason}
      end

    shape |> Map.merge(%{kind: :gpu, cpu_rate: nil, memory_rate: nil}) |> Map.merge(rate)
  end

  defp shape_rates(shape, items) do
    shape =
      Map.merge(shape, %{
        kind: :cpu,
        gpus: 0,
        gpu_memory: 0,
        gpu_rate: nil,
        preemptible_supported: true,
        eligibility_note: nil
      })

    with {:ok, cpu} <- unit_rate(items, shape.cpu_sku, :cpu),
         {:ok, memory} <- unit_rate(items, shape.memory_sku, :memory) do
      Map.merge(shape, %{cpu_rate: cpu, memory_rate: memory, error: nil})
    else
      {:error, reason} -> Map.merge(shape, %{cpu_rate: nil, memory_rate: nil, error: reason})
    end
  end

  defp unit_rate(items, sku, kind) do
    with [item] <- Enum.filter(items, &(is_map(&1) and &1["partNumber"] == sku)),
         true <-
           item["serviceCategory"] ==
             if(kind == :gpu, do: "Compute - GPU", else: "Compute - Virtual Machine"),
         true <- valid_metric?(item["metricName"], kind),
         localizations when is_list(localizations) <- item["currencyCodeLocalizations"],
         [%{"prices" => prices}] when is_list(prices) <-
           Enum.filter(localizations, &(is_map(&1) and &1["currencyCode"] == "USD")) do
      # A1 has an initial zero-price allowance. Compare paid marginal rates,
      # rather than presenting a tenancy allowance as a free preemptible quote.
      values =
        prices
        |> Enum.filter(&(is_map(&1) and &1["model"] == "PAY_AS_YOU_GO"))
        |> Enum.map(&positive_number(&1["value"]))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      case values do
        [value] -> {:ok, value}
        _ -> {:error, "Missing or ambiguous paid USD rate (#{sku})"}
      end
    else
      _ -> {:error, "Compute catalog entry unavailable or changed (#{sku})"}
    end
  end

  defp valid_metric?(metric, :cpu),
    do: is_binary(metric) and String.downcase(metric) == "ocpu per hour"

  defp valid_metric?(metric, :memory),
    do:
      is_binary(metric) and String.downcase(metric) in ["gigabyte per hour", "gigabytes per hour"]

  defp valid_metric?(metric, :gpu),
    do: is_binary(metric) and String.downcase(metric) == "gpu per hour"

  defp positive_number(value) when is_number(value) and value > 0, do: value * 1.0

  defp positive_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp positive_number(_), do: nil

  defp catalog_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> date
      _ -> nil
    end
  end

  defp catalog_date(_), do: nil
end
