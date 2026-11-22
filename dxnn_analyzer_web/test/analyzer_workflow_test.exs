defmodule DxnnAnalyzerWeb.AnalyzerWorkflowTest do
  use ExUnit.Case, async: false
  alias DxnnAnalyzerWeb.{AnalyzerBridge, ContextRegistry}
  require Record
  Record.defrecordp(:agent, Record.extract(:agent, from: "../dxnn_analyzer/include/records.hrl"))

  Record.defrecordp(
    :neuron,
    Record.extract(:neuron, from: "../dxnn_analyzer/include/records.hrl")
  )

  Record.defrecordp(
    :cortex,
    Record.extract(:cortex, from: "../dxnn_analyzer/include/records.hrl")
  )

  test "an experiment can be created, persisted, loaded, saved, and unloaded" do
    workspace =
      Path.join(System.tmp_dir!(), "dxnn-workflow-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)
    previous_dir = Application.get_env(:mnesia, :dir)
    Application.put_env(:mnesia, :dir, String.to_charlist(Path.join(workspace, "mnesia")))

    on_exit(fn ->
      Application.stop(:mnesia)

      if previous_dir,
        do: Application.put_env(:mnesia, :dir, previous_dir),
        else: Application.delete_env(:mnesia, :dir)

      File.rm_rf!(workspace)
    end)

    # Settings use a relative data folder. Keep the real analyzer's writes inside this fixture.
    File.cd!(workspace, fn ->
      start_supervised!(ContextRegistry)
      start_supervised!(AnalyzerBridge)
      run_path = Path.join(workspace, "run")

      assert :ok = AnalyzerBridge.create_experiment_in_settings("smoke", run_path)
      assert [%{name: "smoke"}] = AnalyzerBridge.get_experiments_from_settings()
      assert {:ok, _} = AnalyzerBridge.load_context(run_path, "smoke")
      assert [%{name: "smoke", agent_count: 0, specie_count: 0}] = AnalyzerBridge.list_contexts()
      assert [] = AnalyzerBridge.list_agents(context: "smoke")
      assert {:ok, []} = AnalyzerBridge.get_populations("smoke")
      assert {:ok, []} = AnalyzerBridge.get_species("smoke")
      assert {:error, _} = AnalyzerBridge.inspect_agent({1.0, :agent}, "smoke")
      assert {:error, _} = AnalyzerBridge.get_topology({1.0, :agent}, "smoke")

      # Exercise comparison through the real Erlang engine, including tuple IDs in its output.
      {:ok, context, _} = DxnnAnalyzerWeb.AnalyzerBridge.ContextManager.validate_context("smoke")
      ids = [{1.0, :agent}, {2.0, :agent}]

      for {id, index} <- Enum.with_index(ids) do
        cortex_id = {index, :cortex}

        :ets.insert(
          :dxnn_mnesia_loader.table_name(context, :agent),
          agent(id: id, cx_id: cortex_id, fitness: 1.0, generation: 1)
        )

        :ets.insert(
          :dxnn_mnesia_loader.table_name(context, :cortex),
          cortex(id: cortex_id, agent_id: id)
        )
      end

      comparison = AnalyzerBridge.compare_agents(ids, "smoke")
      assert comparison.agents == ids
      assert comparison.structural_similarity == 1.0

      # Several neurons can share a layer. Similarity must remain symmetric and bounded.
      for {id, index} <- Enum.with_index(ids) do
        cortex_id = {index, :cortex}
        neuron_ids = for n <- 1..(3 - index), do: {{0, index * 10 + n}, :neuron}

        for neuron_id <- neuron_ids do
          :ets.insert(
            :dxnn_mnesia_loader.table_name(context, :neuron),
            neuron(id: neuron_id, cx_id: cortex_id)
          )
        end

        :ets.insert(
          :dxnn_mnesia_loader.table_name(context, :cortex),
          cortex(id: cortex_id, agent_id: id, neuron_ids: neuron_ids)
        )
      end

      [first, second] = ids
      assert {:ok, similarity} = :comparator.calculate_similarity(first, second, context)
      assert {:ok, ^similarity} = :comparator.calculate_similarity(second, first, context)
      assert similarity >= 0.0 and similarity <= 1.0
      assert {:ok, _} = AnalyzerBridge.save_experiment("smoke", run_path)
      assert :ok = AnalyzerBridge.unload_context("smoke")
      assert [] = AnalyzerBridge.list_contexts()
      assert :ok = AnalyzerBridge.remove_experiment_from_settings("smoke")
      assert [] = AnalyzerBridge.get_experiments_from_settings()
      assert File.dir?(Path.join(run_path, "Mnesia.nonode@nohost"))
    end)
  end
end
