defmodule DxnnAnalyzerWeb.OracleSpotPricingTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias DxnnAnalyzerWeb.OCI.SpotPricingBridge
  @endpoint DxnnAnalyzerWeb.Endpoint
  @fixture Path.join(__DIR__, "fixtures/oracle_pricing.json")

  defmodule MockBridge do
    def fetch_catalog do
      send(Process.whereis(:oracle_pricing_owner), {:fetch_catalog, self()})

      receive do
        {:result, result} -> result
      end
    end
  end

  setup do
    Process.register(self(), :oracle_pricing_owner)
    Application.put_env(:dxnn_analyzer_web, :oracle_pricing_bridge, MockBridge)
    on_exit(fn -> Application.delete_env(:dxnn_analyzer_web, :oracle_pricing_bridge) end)
    start_supervised!({Phoenix.PubSub, name: DxnnAnalyzerWeb.PubSub})
    start_supervised!(DxnnAnalyzerWeb.Endpoint)
    {:ok, catalog} = SpotPricingBridge.decode_catalog(File.read!(@fixture))
    %{catalog: catalog}
  end

  defp row(rows, shape), do: Enum.find(rows, &(&1.shape == shape))

  test "CPU and memory are both discounted; monthly and normalized prices retain precision", %{
    catalog: catalog
  } do
    assert {:ok, rows} = SpotPricingBridge.quote(catalog, 8, 32, 730)
    e5 = row(rows, "VM.Standard.E5.Flex")
    assert_in_delta e5.on_demand, 0.304, 0.0000001
    assert_in_delta e5.preemptible, 0.152, 0.0000001
    assert_in_delta e5.monthly, 110.96, 0.0000001
    assert_in_delta e5.per_vcpu, 0.0095, 0.0000001
    assert_in_delta e5.per_gb, 0.00475, 0.0000001
    assert e5.vcpus == 16
    assert Enum.all?(rows, &(&1.reason == nil))
  end

  test "A1 ignores initial free tiers; A1 and A4 use different OCPU/vCPU mappings", %{
    catalog: catalog
  } do
    {:ok, rows} = SpotPricingBridge.quote(catalog, 8, 32, 730)
    a1 = row(rows, "VM.Standard.A1.Flex")
    assert a1.cpu_rate == 0.01
    assert a1.memory_rate == 0.0015
    assert_in_delta a1.preemptible, 0.064, 0.0000001
    assert a1.vcpus == 8
    assert row(rows, "VM.Standard.A4.Flex").vcpus == 16
  end

  test "invalid inputs and shapes outside standard limits never produce a misleading quote", %{
    catalog: catalog
  } do
    for inputs <- [{0, 32, 730}, {8, 4, 730}, {8, 32, 0}, {8.0, 32, 730}, {8, 32, 745}] do
      assert {:error, _} = apply(SpotPricingBridge, :quote, [catalog | Tuple.to_list(inputs)])
    end

    {:ok, rows} = SpotPricingBridge.quote(catalog, 32, 512, 730)
    assert row(rows, "VM.Optimized3.Flex").preemptible == nil
    assert row(rows, "VM.Optimized3.Flex").reason =~ "Maximum"
    assert is_number(row(rows, "VM.Standard.E5.Flex").preemptible)
    {:ok, rows} = SpotPricingBridge.quote(catalog, 1, 128, 730)
    assert rows |> Enum.filter(&(&1.kind == :cpu)) |> Enum.all?(&is_nil(&1.preemptible))
    assert is_number(row(rows, "VM.GPU3.1").preemptible)
  end

  test "missing, wrong-currency and ambiguous SKUs stay unavailable rather than free" do
    payload = Jason.decode!(File.read!(@fixture))
    # Removing only the memory SKU must disable the whole E5 quote.
    missing =
      update_in(payload["items"], &Enum.reject(&1, fn item -> item["partNumber"] == "B97385" end))

    {:ok, catalog} = SpotPricingBridge.decode_catalog(Jason.encode!(missing))
    {:ok, rows} = SpotPricingBridge.quote(catalog, 8, 32, 730)
    assert row(rows, "VM.Standard.E5.Flex").preemptible == nil

    e5 = Enum.find(payload["items"], &(&1["partNumber"] == "B97384"))

    {:ok, duplicate} =
      SpotPricingBridge.decode_catalog(Jason.encode!(update_in(payload["items"], &[e5 | &1])))

    assert Enum.find(duplicate.rates, &(&1.shape == "VM.Standard.E5.Flex")).cpu_rate == nil

    wrong_currency =
      update_in(payload["items"], fn items ->
        Enum.map(items, fn item ->
          Map.put(item, "currencyCodeLocalizations", [
            %{
              "currencyCode" => "EUR",
              "prices" => [%{"model" => "PAY_AS_YOU_GO", "value" => 0.01}]
            }
          ])
        end)
      end)

    assert {:error, _} = SpotPricingBridge.decode_catalog(Jason.encode!(wrong_currency))
    assert {:error, _} = SpotPricingBridge.decode_catalog("not json")
    assert {:error, _} = SpotPricingBridge.decode_catalog(~s({"items":[]}))
  end

  test "metric changes cannot double count vCPU rates as OCPU rates" do
    payload = Jason.decode!(File.read!(@fixture))

    changed =
      update_in(payload["items"], fn items ->
        Enum.map(items, fn item ->
          if item["partNumber"] == "B97384",
            do: Map.put(item, "metricName", "vCPU Per Hour"),
            else: item
        end)
      end)

    {:ok, catalog} = SpotPricingBridge.decode_catalog(Jason.encode!(changed))
    assert Enum.find(catalog.rates, &(&1.shape == "VM.Standard.E5.Flex")).cpu_rate == nil
  end

  test "page loads asynchronously, recalculates locally, and sorts numeric prices", %{
    catalog: catalog
  } do
    {:ok, view, html} = live(build_conn(), "/oracle-spot-pricing")
    assert html =~ "Oracle Spot Pricing"
    assert html =~ "AWS Spot Pricing"
    assert_receive {:fetch_catalog, task}
    assert has_element?(view, "button[phx-click=refresh_pricing][disabled]")
    send(task, {:result, {:ok, catalog}})
    assert render_async(view) =~ "$0.1520"
    assert has_element?(view, "#oracle-pricing-table")

    view
    |> form("#oracle-pricing-config", %{"ocpus" => "4", "memory" => "16", "hours" => "100"})
    |> render_change()

    assert render(view) =~ "$0.0760"
    assert render(view) =~ "$7.60"
    refute_receive {:fetch_catalog, _}

    view |> element("button[phx-value-kind=cpu]") |> render_click()

    view |> element("button[phx-value-column=preemptible]") |> render_click()

    rows =
      render(view) |> Floki.parse_document!() |> Floki.find("tbody tr") |> Enum.map(&Floki.text/1)

    assert hd(rows) =~ "VM.Optimized3.Flex"
    assert List.last(rows) =~ "VM.Standard.A1.Flex"

    assert render_click(view, "sort", %{"column" => "unknown-atom-must-not-be-created"}) =~
             "Oracle Spot Pricing"
  end

  test "GPU prices use the fixed GPU count and bundled host resources", %{catalog: catalog} do
    {:ok, rows} = SpotPricingBridge.quote(catalog, 8, 32, 730)
    {:ok, other_sizes} = SpotPricingBridge.quote(catalog, 1, 4, 730)

    for name <-
          ~w(VM.Standard.A1.Flex VM.Standard.E4.Flex VM.Standard.E5.Flex VM.GPU.A10.1 VM.GPU.A10.2 VM.GPU3.1 VM.GPU2.1 BM.GPU.L40S.4) do
      assert row(rows, name), "Requested shape #{name} is missing"
    end

    a10 = row(rows, "VM.GPU.A10.2")
    assert a10.gpus == 2
    assert a10.ocpus == 30
    assert a10.vcpus == 60
    assert a10.memory == 480
    assert a10.gpu_memory == 24
    assert a10.on_demand == 4.0
    assert a10.on_demand_monthly == 2920.0
    l40 = row(rows, "BM.GPU.L40S.4")
    assert l40.gpus == 4
    assert l40.on_demand == 14.0
    assert l40.memory == 1024

    for gpu <- Enum.filter(rows, &(&1.kind == :gpu)) do
      other = row(other_sizes, gpu.shape)

      assert Map.take(gpu, [:ocpus, :memory, :on_demand, :preemptible]) ==
               Map.take(other, [:ocpus, :memory, :on_demand, :preemptible])
    end
  end

  test "discount applies to GPU2/GPU3 only; A10 and bare metal retain on-demand estimates", %{
    catalog: catalog
  } do
    {:ok, rows} = SpotPricingBridge.quote(catalog, 8, 32, 100)
    v100 = row(rows, "VM.GPU3.1")
    assert_in_delta v100.preemptible, 1.475, 0.0000001
    assert_in_delta v100.monthly, 147.5, 0.0000001
    assert v100.per_gpu == v100.preemptible
    assert row(rows, "VM.GPU2.1").preemptible == 0.6375

    for shape <- ~w(VM.GPU.A10.1 VM.GPU.A10.2 BM.GPU.L40S.4) do
      gpu = row(rows, shape)
      assert gpu.preemptible == nil
      assert gpu.monthly == nil
      assert gpu.per_gpu == nil
      assert is_number(gpu.on_demand)
      assert gpu.reason == nil
      assert gpu.eligibility_note != nil
    end
  end

  test "GPU unit and service-category mismatches do not generate a price" do
    payload = Jason.decode!(File.read!(@fixture))

    changed =
      update_in(payload["items"], fn items ->
        Enum.map(items, fn item ->
          case item["partNumber"] do
            "B95909" -> Map.put(item, "metricName", "OCPU Per Hour")
            "B109479" -> Map.put(item, "serviceCategory", "Compute Cloud@Customer")
            _ -> item
          end
        end)
      end)

    {:ok, catalog} = SpotPricingBridge.decode_catalog(Jason.encode!(changed))
    {:ok, rows} = SpotPricingBridge.quote(catalog, 8, 32, 730)

    for name <- ~w(VM.GPU.A10.1 VM.GPU.A10.2 BM.GPU.L40S.4) do
      assert row(rows, name).on_demand == nil
    end

    assert is_number(row(rows, "VM.GPU3.1").on_demand)
    assert is_number(row(rows, "VM.Standard.E5.Flex").preemptible)
  end

  test "GPU filter shows fixed specifications and unsupported spot labels", %{catalog: catalog} do
    {:ok, view, _} = live(build_conn(), "/oracle-spot-pricing")
    assert_receive {:fetch_catalog, task}
    send(task, {:result, {:ok, catalog}})
    render_async(view)
    view |> element("button[phx-value-kind=gpu]") |> render_click()
    html = render(view)
    rows = html |> Floki.parse_document!() |> Floki.find("tbody tr")
    assert length(rows) == 5
    assert html =~ "Fixed GPU shape"
    assert html =~ "Not available"

    a10 =
      rows
      |> Enum.find(&(Floki.attribute(&1, "id") == ["oracle-price-VM.GPU.A10.2"]))
      |> Floki.text()

    assert a10 =~ "$4.0000"
    assert a10 =~ "$2920.00"
    assert a10 =~ "A10 is not listed"

    view
    |> form("#oracle-pricing-config", %{"ocpus" => "1", "memory" => "4", "hours" => "100"})
    |> render_change()

    assert render(view) =~ "$400.00"
    assert render(view) =~ "$4.0000"
    view |> element("button[phx-value-column=preemptible]") |> render_click()
    sorted = render(view) |> Floki.parse_document!() |> Floki.find("tbody tr")
    assert Floki.text(hd(sorted)) =~ "VM.GPU3.1"
    view |> element("button[phx-value-kind=cpu]") |> render_click()
    assert render(view) |> Floki.parse_document!() |> Floki.find("tbody tr") |> length() == 7
  end

  test "failed refresh keeps previous prices and exposes an error with a retry", %{
    catalog: catalog
  } do
    {:ok, view, _} = live(build_conn(), "/oracle-spot-pricing")
    assert_receive {:fetch_catalog, first}
    send(first, {:result, {:ok, catalog}})
    render_async(view)
    view |> element("button[phx-click=refresh_pricing]") |> render_click()
    assert_receive {:fetch_catalog, second}
    send(second, {:result, {:error, "Oracle catalog unavailable"}})
    html = render_async(view)
    assert html =~ "Oracle catalog unavailable"
    assert html =~ "$0.1520"
    refute has_element?(view, "button[phx-click=refresh_pricing][disabled]")
  end

  test "invalid input is shown immediately while the catalog is still loading", %{
    catalog: catalog
  } do
    {:ok, view, _} = live(build_conn(), "/oracle-spot-pricing")
    assert_receive {:fetch_catalog, task}

    view
    |> form("#oracle-pricing-config", %{"ocpus" => "8", "memory" => "4", "hours" => "730"})
    |> render_change()

    assert render(view) =~ "at least 1 GB"
    send(task, {:result, {:ok, catalog}})
    assert render_async(view) =~ "at least 1 GB"
    refute has_element?(view, "#oracle-pricing-table")
  end
end
