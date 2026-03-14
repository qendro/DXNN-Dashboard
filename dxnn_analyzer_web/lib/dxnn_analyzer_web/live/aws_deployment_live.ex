defmodule DxnnAnalyzerWeb.AWSDeploymentLive do
  use DxnnAnalyzerWeb, :live_view
  alias DxnnAnalyzerWeb.AWS.{AWSBridge, AWSDeploymentServer}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "aws_deployment")
      Phoenix.PubSub.subscribe(DxnnAnalyzerWeb.PubSub, "aws_operations")
      AWSDeploymentServer.refresh()
    end

    socket =
      socket
      |> assign(:active_tab, "instances")
      |> assign(:amis, [])
      |> assign(:instances, [])
      |> assign(:configs, [])
      |> assign(:regions, [])
      |> assign(:instance_types, [
        "t3.xlarge",
        "m5.xlarge", "m5.2xlarge", "m5.4xlarge", "m5.8xlarge",
        "c5.xlarge", "c5.2xlarge", "c5.4xlarge", "c5.9xlarge", "c5.12xlarge",
        "c6i.xlarge", "c6i.2xlarge", "c6i.4xlarge", "c6i.8xlarge", "c6i.12xlarge", "c6i.16xlarge", "c6i.24xlarge",
        "c7i.xlarge", "c7i.2xlarge", "c7i.4xlarge", "c7i.8xlarge", "c7i.12xlarge", "c7i.16xlarge", "c7i.24xlarge"
      ])
      |> assign(:selected_config, nil)
      |> assign(:selected_ami, nil)
      |> assign(:selected_instance, nil)
      |> assign(:selected_region, nil)
      |> assign(:launch_instance_type, nil)
      |> assign(:launch_availability_zone, nil)
      |> assign(:launch_ami_id, nil)
      |> assign(:launch_spot_max_price, nil)
      |> assign(:show_create_ami_modal, false)
      |> assign(:show_launch_instance_modal, false)
      |> assign(:show_deploy_config_modal, false)
      |> assign(:show_logs_modal, false)
      |> assign(:show_terminal_modal, false)
      |> assign(:show_copy_ami_modal, false)
      |> assign(:ami_name, "")
      |> assign(:copy_source_ami, nil)
      |> assign(:copy_source_region, nil)
      |> assign(:copy_target_region, nil)
      |> assign(:config_content, nil)
      |> assign(:operation_output, [])
      |> assign(:log_content, "")
      |> assign(:terminal_output, "")
      |> assign(:terminal_title, "")
      |> assign(:operation_running, false)
      |> assign(:operation_id, nil)
      |> assign(:pending_amis, [])
      |> assign(:expanded_instance, nil)
      |> assign(:deploy_key_file, "")
      |> assign(:deploy_host, "")
      |> assign(:deploy_branch, "main")
      |> assign(:deploy_start, false)
      |> assign(:deploy_auto_terminate, false)
      |> assign(:deploy_instance_id, nil)
      |> assign(:pending_deployment, nil)
      |> assign(:deployments, %{})  # Track deployments by instance_id
      |> assign(:available_branches, ["main", "develop", "v2.0.0", "v2.1.0", "v2.2.0"])
      |> allow_upload(:config_file, accept: :any, max_entries: 20)
      |> load_state()
      |> check_running_operations()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Check if we should auto-open launch modal with pre-filled data from spot pricing
    socket = if params["auto_open_modal"] == "true" && connected?(socket) do
      # Load regions, AMIs, and availability zones
      regions = case AWSBridge.list_regions() do
        {:ok, regions} -> regions
        _ -> []
      end
      
      amis = case AWSBridge.list_amis() do
        {:ok, amis} -> 
          us_regions = ["us-east-1", "us-east-2", "us-west-1", "us-west-2"]
          Enum.filter(amis, fn ami -> 
            Map.get(ami, :region, "us-east-1") in us_regions
          end)
        _ -> []
      end
      
      availability_zones = case AWSBridge.list_availability_zones() do
        {:ok, zones} -> zones
        _ -> []
      end
      
      # Get region from params and find matching availability zone
      region = params["region"]
      availability_zone = if region do
        # Find first available zone in the target region
        Enum.find_value(availability_zones, fn zone ->
          if zone.region == region, do: zone.name, else: nil
        end)
      else
        nil
      end
      
      socket
      |> assign(:show_launch_instance_modal, true)
      |> assign(:regions, regions)
      |> assign(:amis, amis)
      |> assign(:availability_zones, availability_zones)
      |> assign(:launch_instance_type, params["instance_type"])
      |> assign(:launch_availability_zone, availability_zone)
      |> assign(:launch_ami_id, nil)
      |> assign(:launch_spot_max_price, params["spot_max_price"])
    else
      socket
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    require Logger
    Logger.info("LiveView: Received state_updated")
    Logger.info("LiveView: State deployments: #{inspect(state.deployments)}")
    
    socket =
      socket
      |> assign(:amis, state.amis)
      |> assign(:instances, state.instances)
      |> assign(:configs, state.configs)
      |> assign(:deployments, state.deployments || %{})
    
    Logger.info("LiveView: Socket deployments after assign: #{inspect(socket.assigns.deployments)}")
    {:noreply, socket}
  end

  def handle_info({:deployment_recorded, instance_id, deployment}, socket) do
    require Logger
    Logger.info("LiveView: Received deployment_recorded message")
    Logger.info("LiveView: Current deployments: #{inspect(socket.assigns.deployments)}")

    socket =
      assign(
        socket,
        :deployments,
        Map.put(socket.assigns.deployments || %{}, instance_id, deployment)
      )
    
    # Refresh state to get updated deployments
    AWSDeploymentServer.refresh()
    {:noreply, socket}
  end

  def handle_info({:script_output, data}, socket) do
    output = socket.assigns.terminal_output <> data
    {:noreply, assign(socket, :terminal_output, output)}
  end

  def handle_info({:script_complete, status}, socket) do
    message = if status == 0, do: "✅ Operation completed successfully", else: "❌ Operation failed"
    output = socket.assigns.terminal_output <> "\n\n" <> message
    
    # If this was a successful config deployment, record it
    if status == 0 && socket.assigns.pending_deployment != nil do
      pending_deployment = socket.assigns.pending_deployment

      deployment_info = %{
        key_file: pending_deployment.key_file,
        host: pending_deployment.host,
        branch: pending_deployment.branch,
        started: pending_deployment.started
      }
      
      require Logger
      Logger.info("Recording deployment for instance: #{pending_deployment.instance_id}")
      Logger.info("Deployment info: #{inspect(deployment_info)}")
      
      AWSDeploymentServer.record_deployment(pending_deployment.instance_id, deployment_info)
    else
      require Logger
      Logger.warning(
        "Not recording deployment - status: #{status}, pending_deployment: #{inspect(socket.assigns.pending_deployment)}"
      )
    end
    
    # Remove pending AMI if this was an AMI creation
    pending_amis = if socket.assigns.operation_id do
      Enum.reject(socket.assigns.pending_amis, fn ami -> 
        ami.operation_id == socket.assigns.operation_id 
      end)
    else
      socket.assigns.pending_amis
    end
    
    socket =
      socket
      |> put_flash(:info, message)
      |> assign(:terminal_output, output)
      |> assign(:operation_running, false)
      |> assign(:pending_amis, pending_amis)
      |> assign(:pending_deployment, nil)
    AWSDeploymentServer.refresh()
    {:noreply, socket}
  end

  def handle_info({:script_timeout, reason}, socket) do
    message = "❌ Operation timed out: #{reason}"
    output = socket.assigns.terminal_output <> "\n\n" <> message

    pending_amis = if socket.assigns.operation_id do
      Enum.reject(socket.assigns.pending_amis, fn ami ->
        ami.operation_id == socket.assigns.operation_id
      end)
    else
      socket.assigns.pending_amis
    end

    socket =
      socket
      |> put_flash(:error, message)
      |> assign(:terminal_output, output)
      |> assign(:operation_running, false)
      |> assign(:pending_amis, pending_amis)
      |> assign(:pending_deployment, nil)

    AWSDeploymentServer.refresh()
    {:noreply, socket}
  end

  def handle_event("view_operation_logs", %{"operation_id" => operation_id}, socket) do
    # Find the pending AMI
    pending_ami = Enum.find(socket.assigns.pending_amis, fn ami -> 
      ami.operation_id == operation_id 
    end)
    
    if pending_ami do
      socket =
        socket
        |> assign(:show_terminal_modal, true)
        |> assign(:terminal_title, "Creating AMI: #{pending_ami.name}")
        |> assign(:terminal_output, socket.assigns.terminal_output)
        |> assign(:operation_running, true)
        |> assign(:operation_id, operation_id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("refresh", _, socket) do
    AWSDeploymentServer.refresh()
    {:noreply, put_flash(socket, :info, "Refreshing...")}
  end

  # AMI Events
  def handle_event("show_create_ami_modal", _, socket) do
    # Load regions when opening modal
    regions = case AWSBridge.list_regions() do
      {:ok, regions} -> regions
      _ -> []
    end
    socket = socket
    |> assign(:show_create_ami_modal, true)
    |> assign(:regions, regions)
    |> assign(:selected_region, get_default_region())
    {:noreply, socket}
  end

  def handle_event("hide_create_ami_modal", _, socket) do
    {:noreply, assign(socket, show_create_ami_modal: false, ami_name: "", selected_region: nil)}
  end

  def handle_event("update_ami_name", params, socket) do
    name = Map.get(params, "ami_name", Map.get(params, "value", ""))
    {:noreply, assign(socket, :ami_name, name)}
  end

  def handle_event("select_region", %{"region" => region}, socket) do
    {:noreply, assign(socket, :selected_region, region)}
  end

  def handle_event("create_ami", params, socket) do
    name =
      params
      |> Map.get("ami_name", socket.assigns.ami_name)
      |> normalize_optional_value()

    region =
      params
      |> Map.get("region", socket.assigns.selected_region)
      |> normalize_optional_value()

    operation_id = "ami_create_#{:os.system_time(:millisecond)}"
    
    case AWSBridge.create_ami(name, region) do
      {:ok, :started} ->
        # Add pending AMI to the list
        pending_ami = %{
          id: operation_id,
          name: name || "Creating...",
          region: region || get_default_region(),
          created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          state: "pending",
          operation_id: operation_id
        }
        
        socket =
          socket
          |> assign(show_create_ami_modal: false, ami_name: "", selected_region: nil)
          |> assign(:show_terminal_modal, true)
          |> assign(:terminal_title, "Creating AMI in #{region || get_default_region()} (10-15 minutes)")
          |> assign(:terminal_output, "Starting AMI creation...\n")
          |> assign(:operation_running, true)
          |> assign(:operation_id, operation_id)
          |> assign(:pending_amis, [pending_ami | socket.assigns.pending_amis])
        {:noreply, socket}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create AMI: #{reason}")}
    end
  end

  def handle_event("show_copy_ami_modal", %{"ami_id" => ami_id, "region" => region}, socket) do
    # Load regions when opening modal
    regions = case AWSBridge.list_regions() do
      {:ok, regions} -> regions
      _ -> []
    end
    socket = socket
    |> assign(:show_copy_ami_modal, true)
    |> assign(:copy_source_ami, ami_id)
    |> assign(:copy_source_region, region)
    |> assign(:copy_target_region, nil)
    |> assign(:regions, regions)
    {:noreply, socket}
  end

  def handle_event("hide_copy_ami_modal", _, socket) do
    {:noreply, assign(socket, show_copy_ami_modal: false, copy_source_ami: nil, copy_source_region: nil, copy_target_region: nil)}
  end

  def handle_event("select_target_region", %{"region" => region}, socket) do
    {:noreply, assign(socket, :copy_target_region, region)}
  end

  def handle_event("copy_ami", params, socket) do
    source_ami = socket.assigns.copy_source_ami
    source_region = socket.assigns.copy_source_region
    target_region = params |> Map.get("target_region", socket.assigns.copy_target_region) |> normalize_optional_value()

    if source_ami && source_region && target_region do
      operation_id = "ami_copy_#{:os.system_time(:millisecond)}"
      
      case AWSBridge.copy_ami(source_ami, source_region, target_region) do
        {:ok, :started} ->
          pending_ami = %{
            id: operation_id,
            name: "Copying #{source_ami}...",
            region: target_region,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            state: "pending",
            operation_id: operation_id
          }
          
          socket =
            socket
            |> assign(show_copy_ami_modal: false, copy_source_ami: nil, copy_source_region: nil, copy_target_region: nil)
            |> assign(:show_terminal_modal, true)
            |> assign(:terminal_title, "Copying AMI from #{source_region} to #{target_region} (10-15 minutes)")
            |> assign(:terminal_output, "Starting AMI copy...\n")
            |> assign(:operation_running, true)
            |> assign(:operation_id, operation_id)
            |> assign(:pending_amis, [pending_ami | socket.assigns.pending_amis])
          {:noreply, socket}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to copy AMI: #{reason}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a target region")}
    end
  end

  def handle_event("delete_ami", %{"ami_id" => ami_id}, socket) do
    case AWSBridge.delete_ami(ami_id) do
      {:ok, _} ->
        AWSDeploymentServer.refresh()
        {:noreply, put_flash(socket, :info, "AMI #{ami_id} deleted")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete AMI: #{reason}")}
    end
  end

  # Instance Events
  def handle_event("show_launch_instance_modal", _, socket) do
    # Load regions and AMIs when opening modal
    regions = case AWSBridge.list_regions() do
      {:ok, regions} -> regions
      _ -> []
    end
    
    amis = case AWSBridge.list_amis() do
      {:ok, amis} -> 
        # Filter to only US regions
        us_regions = ["us-east-1", "us-east-2", "us-west-1", "us-west-2"]
        Enum.filter(amis, fn ami -> 
          Map.get(ami, :region, "us-east-1") in us_regions
        end)
      _ -> []
    end
    
    # Get availability zones for all regions
    availability_zones = case AWSBridge.list_availability_zones() do
      {:ok, zones} -> zones
      _ -> []
    end
    
    socket = socket
    |> assign(:show_launch_instance_modal, true)
    |> assign(:regions, regions)
    |> assign(:amis, amis)
    |> assign(:availability_zones, availability_zones)
    |> assign(:launch_instance_type, nil)
    |> assign(:launch_availability_zone, nil)
    |> assign(:launch_ami_id, nil)
    |> assign(:launch_spot_max_price, nil)
    
    {:noreply, socket}
  end

  def handle_event("hide_launch_instance_modal", _, socket) do
    {:noreply, assign(socket, 
      show_launch_instance_modal: false, 
      selected_config: nil, 
      selected_ami: nil,
      launch_instance_type: nil,
      launch_availability_zone: nil,
      launch_ami_id: nil,
      launch_spot_max_price: nil
    )}
  end

  def handle_event("select_config", params, socket) do
    selected =
      params
      |> Map.get("config", Map.get(params, "value"))
      |> normalize_optional_value()

    # Load config details to populate overrides
    config_details = if selected do
      case AWSBridge.read_config(selected) do
        {:ok, %{parsed: parsed}} ->
          %{
            instance_type: get_in(parsed, ["aws", "instance_type"]),
            availability_zone: get_in(parsed, ["aws", "availability_zone"]),
            ami_id: get_in(parsed, ["aws", "ami_id"]),
            spot_max_price: get_in(parsed, ["aws", "spot_max_price"]),
            region: get_in(parsed, ["aws", "region"])
          }
        _ -> nil
      end
    else
      nil
    end

    socket = socket
    |> assign(:selected_config, selected)
    
    socket = if config_details do
      socket
      |> assign(:launch_instance_type, config_details.instance_type)
      |> assign(:launch_availability_zone, config_details.availability_zone)
      |> assign(:launch_ami_id, config_details.ami_id)
      |> assign(:launch_spot_max_price, config_details.spot_max_price)
      |> assign(:selected_region, config_details.region)
    else
      socket
    end
    
    {:noreply, socket}
  end

  def handle_event("update_launch_field", params, socket) do
    # phx-change sends the field name as the key in params
    # Extract field name from _target or find the field directly
    {field, value} = cond do
      # Check _target first (LiveView sends this with phx-change)
      Map.has_key?(params, "_target") && is_list(params["_target"]) ->
        field_name = List.first(params["_target"])
        {field_name, Map.get(params, field_name)}
      
      # Fallback to checking each field directly
      Map.has_key?(params, "instance_type") ->
        {"instance_type", params["instance_type"]}
      Map.has_key?(params, "availability_zone") ->
        {"availability_zone", params["availability_zone"]}
      Map.has_key?(params, "ami_id") ->
        {"ami_id", params["ami_id"]}
      Map.has_key?(params, "spot_max_price") ->
        {"spot_max_price", params["spot_max_price"]}
      
      true ->
        {nil, nil}
    end
    
    # Only update if we found a valid field
    socket = if field do
      assign(socket, String.to_atom("launch_#{field}"), value)
    else
      socket
    end
    
    {:noreply, socket}
  end

  def handle_event("launch_instance", params, socket) do
    selected_config =
      params
      |> Map.get("config", socket.assigns.selected_config)
      |> normalize_optional_value()

    case selected_config do
      nil ->
        {:noreply, put_flash(socket, :error, "Please select a configuration")}
      config ->
        # Build launch parameters with overrides
        overrides = %{
          instance_type: Map.get(params, "instance_type", socket.assigns.launch_instance_type) |> normalize_optional_value(),
          availability_zone: Map.get(params, "availability_zone", socket.assigns.launch_availability_zone) |> normalize_optional_value(),
          ami_id: Map.get(params, "ami_id", socket.assigns.launch_ami_id) |> normalize_optional_value(),
          spot_max_price: Map.get(params, "spot_max_price", socket.assigns.launch_spot_max_price) |> normalize_optional_value()
        }
        
        config_path = "config/#{config}"
        case AWSBridge.launch_instance(config_path, overrides) do
          {:ok, :started} ->
            socket =
              socket
              |> assign(show_launch_instance_modal: false, selected_config: nil)
              |> assign(:show_terminal_modal, true)
              |> assign(:terminal_title, "Launching Instance")
              |> assign(:terminal_output, "Starting instance launch...\n")
              |> assign(:operation_running, true)
            {:noreply, socket}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to launch instance: #{reason}")}
        end
    end
  end

  def handle_event("terminate_instance", %{"instance_id" => instance_id}, socket) do
    case AWSBridge.terminate_instance(instance_id) do
      {:ok, _} ->
        AWSDeploymentServer.refresh()
        {:noreply, put_flash(socket, :info, "Instance #{instance_id} terminating")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to terminate instance: #{reason}")}
    end
  end

  def handle_event("show_logs", %{"instance_id" => instance_id}, socket) do
    case AWSBridge.get_instance_logs(instance_id) do
      {:ok, logs} ->
        socket =
          socket
          |> assign(:show_logs_modal, true)
          |> assign(:log_content, logs)
          |> assign(:selected_instance, instance_id)
        {:noreply, socket}
      {:error, reason} ->
        error_msg = if String.contains?(reason, "UnauthorizedOperation") do
          "Console logs require ec2:GetConsoleOutput permission. Use SSH to view logs instead."
        else
          "Failed to get logs: #{reason}"
        end
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("hide_logs_modal", _, socket) do
    {:noreply, assign(socket, show_logs_modal: false, log_content: "", selected_instance: nil)}
  end

  # Config Events
  def handle_event("view_config", %{"config" => config_name}, socket) do
    case AWSBridge.read_config(config_name) do
      {:ok, %{raw: content}} ->
        {:noreply, assign(socket, :config_content, content)}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to read config")}
    end
  end

  def handle_event("close_config", _, socket) do
    {:noreply, assign(socket, :config_content, nil)}
  end

  # Deploy Config Events
  def handle_event("show_deploy_config_modal", %{"instance_id" => instance_id, "ip" => ip}, socket) do
    # Find the specific SSH key for this instance from deployment JSON
    key_file = case find_instance_key_file(instance_id) do
      nil ->
        # Fallback: find the most recent aws-deployment key file
        case File.ls("/app/AWS-Deployment/output") do
          {:ok, files} ->
            deployment_keys = files
            |> Enum.filter(&(String.starts_with?(&1, "aws-deployment-key-") and String.ends_with?(&1, ".pem")))
            |> Enum.sort()
            |> Enum.reverse()
            
            if length(deployment_keys) > 0 do
              "/app/AWS-Deployment/output/#{List.first(deployment_keys)}"
            else
              ""
            end
          _ -> ""
        end
      key -> key
    end
    
    socket =
      socket
      |> assign(:show_deploy_config_modal, true)
      |> assign(:selected_instance, instance_id)
      |> assign(:deploy_instance_id, instance_id)
      |> assign(:deploy_host, ip)
      |> assign(:deploy_key_file, key_file)
    {:noreply, socket}
  end

  def handle_event("hide_deploy_config_modal", _, socket) do
    {:noreply, assign(socket, show_deploy_config_modal: false, selected_instance: nil)}
  end

  def handle_event("update_deploy_field", %{"field" => field, "value" => value}, socket) do
    {:noreply, assign(socket, String.to_atom("deploy_#{field}"), value)}
  end

  def handle_event("update_deploy_field", %{"branch" => value}, socket) do
    {:noreply, assign(socket, :deploy_branch, value)}
  end

  def handle_event("toggle_deploy_start", _, socket) do
    {:noreply, assign(socket, :deploy_start, !socket.assigns.deploy_start)}
  end

  def handle_event("toggle_auto_terminate", _, socket) do
    {:noreply, assign(socket, :deploy_auto_terminate, !socket.assigns.deploy_auto_terminate)}
  end

  def handle_event("update_branch_select", %{"branch" => branch}, socket) do
    {:noreply, assign(socket, :deploy_branch, branch)}
  end

  def handle_event("validate_upload", _, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :config_file, ref)}
  end

  def handle_event("deploy_config", params, socket) do
    deploy_instance_id =
      params
      |> Map.get("instance_id", socket.assigns.deploy_instance_id)
      |> normalize_optional_value()

    deploy_key_file =
      params
      |> Map.get("key_file", socket.assigns.deploy_key_file)
      |> normalize_optional_value()

    deploy_host =
      params
      |> Map.get("host", socket.assigns.deploy_host)
      |> normalize_optional_value()

    deploy_branch =
      params
      |> Map.get("branch", socket.assigns.deploy_branch)
      |> normalize_optional_value()
      |> Kernel.||("main")

    deploy_start =
      case Map.get(params, "start") do
        nil -> socket.assigns.deploy_start
        "true" -> true
        "false" -> false
        value -> value in ["on", "1", 1, true]
      end

    deploy_auto_terminate =
      case Map.get(params, "auto_terminate") do
        nil -> socket.assigns.deploy_auto_terminate
        "true" -> true
        "false" -> false
        value -> value in ["on", "1", 1, true]
      end

    # Consume all uploaded files
    uploaded_files = consume_uploaded_entries(socket, :config_file, fn %{path: path}, entry ->
      # Preserve original filename
      dest = Path.join([System.tmp_dir!(), entry.client_name])
      File.cp!(path, dest)
      {:ok, dest}
    end)

    # Deploy even if no files uploaded (will just pull GitHub and compile)
    if deploy_key_file && deploy_host && deploy_instance_id do
      case AWSBridge.deploy_config(
        deploy_key_file,
        deploy_host,
        uploaded_files,  # Pass list of files (can be empty)
        deploy_branch,
        deploy_start,
        deploy_auto_terminate
      ) do
        {:ok, :started} ->
          pending_deployment = %{
            instance_id: deploy_instance_id,
            key_file: deploy_key_file,
            host: deploy_host,
            branch: deploy_branch,
            started: deploy_start,
            auto_terminate: deploy_auto_terminate
          }

          socket =
            socket
            |> assign(show_deploy_config_modal: false)
            |> assign(:show_terminal_modal, true)
            |> assign(:terminal_title, "Deploying Configuration")
            |> assign(:terminal_output, "Starting config deployment...\n")
            |> assign(:operation_running, true)
            |> assign(:deploy_branch, deploy_branch)
            |> assign(:deploy_start, deploy_start)
            |> assign(:deploy_auto_terminate, deploy_auto_terminate)
            |> assign(:deploy_instance_id, deploy_instance_id)
            |> assign(:deploy_key_file, deploy_key_file)
            |> assign(:deploy_host, deploy_host)
            |> assign(:pending_deployment, pending_deployment)
          {:noreply, socket}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to deploy config: #{reason}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please provide all required fields")}
    end
  end

  def handle_event("hide_terminal_modal", _, socket) do
    {:noreply, assign(socket, show_terminal_modal: false, terminal_output: "", operation_running: false)}
  end

  def handle_event("toggle_instance_details", %{"instance_id" => instance_id}, socket) do
    expanded = if socket.assigns.expanded_instance == instance_id, do: nil, else: instance_id
    {:noreply, assign(socket, :expanded_instance, expanded)}
  end

  def handle_event("start_training", %{"instance_id" => instance_id, "ip" => ip}, socket) do
    key_file = socket.assigns.deploy_key_file || find_key_file()
    case AWSBridge.start_training(key_file, ip) do
      {_, 0} ->
        {:noreply, put_flash(socket, :info, "Training started on #{instance_id}")}
      {error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to start training: #{error}")}
    end
  end

  def handle_event("stop_training", %{"instance_id" => instance_id, "ip" => ip}, socket) do
    key_file = socket.assigns.deploy_key_file || find_key_file()
    case AWSBridge.stop_training(key_file, ip) do
      {_, 0} ->
        {:noreply, put_flash(socket, :info, "Training stopped on #{instance_id}")}
      {error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to stop training: #{error}")}
    end
  end

  defp find_key_file do
    case File.ls("/app/AWS-Deployment/output") do
      {:ok, files} ->
        key = Enum.find(files, &String.ends_with?(&1, ".pem"))
        if key, do: "/app/AWS-Deployment/output/#{key}", else: ""
      _ -> ""
    end
  end

  defp find_instance_key_file(instance_id) do
    # Find the deployment JSON file for this instance
    case File.ls("/app/AWS-Deployment/output") do
      {:ok, files} ->
        json_files = Enum.filter(files, &String.ends_with?(&1, ".json"))
        
        # Find matching deployment file
        matching_data = Enum.find_value(json_files, fn file ->
          path = Path.join("/app/AWS-Deployment/output", file)
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, data} -> 
                  if data["instance_id"] == instance_id, do: data, else: nil
                _ -> nil
              end
            _ -> nil
          end
        end)
        
        if matching_data do
          # Get key_name and construct full path
          key_name = matching_data["key_name"]
          if key_name do
            key_path = "/app/AWS-Deployment/output/#{key_name}-key.pem"
            # Verify the key file actually exists
            if File.exists?(key_path) do
              key_path
            else
              nil
            end
          else
            nil
          end
        else
          nil
        end
      _ -> nil
    end
  end

  defp get_key_filename(instance_id) do
    # Find the deployment JSON file for this instance
    case File.ls("/app/AWS-Deployment/output") do
      {:ok, files} ->
        json_files = Enum.filter(files, &String.ends_with?(&1, ".json"))
        
        # Find matching deployment data
        matching_data = Enum.find_value(json_files, fn file ->
          path = Path.join("/app/AWS-Deployment/output", file)
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, data} -> 
                  if data["instance_id"] == instance_id do
                    data
                  else
                    nil
                  end
                _ -> nil
              end
            _ -> nil
          end
        end)
        
        if matching_data do
          # Extract just the filename from ssh_key_file path
          ssh_key_file = matching_data["ssh_key_file"]
          if ssh_key_file do
            # ssh_key_file is like "./output/aws-deployment-key-20260303-133357-key.pem"
            Path.basename(ssh_key_file)
          else
            # Try key_name as fallback
            key_name = matching_data["key_name"]
            if key_name do
              "#{key_name}-key.pem"
            else
              "aws-deployment-key-*.pem"
            end
          end
        else
          # No matching deployment found, use most recent key
          deployment_keys = files
          |> Enum.filter(&(String.starts_with?(&1, "aws-deployment-key-") and String.ends_with?(&1, ".pem")))
          |> Enum.sort()
          |> Enum.reverse()
          
          if length(deployment_keys) > 0 do
            List.first(deployment_keys)
          else
            "aws-deployment-key-*.pem"
          end
        end
      _ -> "aws-deployment-key-*.pem"
    end
  end

  defp normalize_optional_value(nil), do: nil
  defp normalize_optional_value(""), do: nil
  defp normalize_optional_value(value), do: value

  defp get_default_region do
    System.get_env("AWS_DEFAULT_REGION", "us-east-1")
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end
  defp format_datetime(_), do: "Unknown"

  defp format_launch_time(launch_time_string) when is_binary(launch_time_string) do
    case DateTime.from_iso8601(launch_time_string) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%m/%d %H:%M")
      _ ->
        launch_time_string
    end
  end
  defp format_launch_time(_), do: "—"

  defp load_state(socket) do
    state = AWSDeploymentServer.get_state()
    socket
    |> assign(:amis, state.amis)
    |> assign(:instances, state.instances)
    |> assign(:configs, state.configs)
    |> assign(:deployments, state.deployments || %{})
  end

  defp check_running_operations(socket) do
    # Check if there are any running operations and reconnect to them
    state = AWSDeploymentServer.get_state()
    running_ops = state.operations
    |> Enum.filter(fn {_id, op} -> op.status == :running end)
    
    case running_ops do
      [{op_id, operation} | _] ->
        # Reconnect to the first running operation
        socket
        |> assign(:show_terminal_modal, true)
        |> assign(:terminal_title, "Reconnected: #{operation.type}")
        |> assign(:terminal_output, Enum.join(operation.output, ""))
        |> assign(:operation_running, true)
        |> assign(:operation_id, op_id)
        |> put_flash(:info, "⚠️ Reconnected to running operation: #{operation.type}")
      [] ->
        socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-8 flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">AWS Deployment Manager</h1>
            <p class="mt-2 text-gray-600">Manage AMIs, instances, and deployments</p>
          </div>
          <div class="flex gap-2">
            <.link
              navigate={~p"/spot-pricing"}
              class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
            >
              💰 Spot Pricing
            </.link>
            <.link
              navigate={~p"/s3-explorer"}
              class="bg-teal-600 text-white px-4 py-2 rounded-md hover:bg-teal-700 transition"
            >
              🗂️ S3 Explorer
            </.link>
            <.link
              navigate={~p"/"}
              class="bg-gray-600 text-white px-4 py-2 rounded-md hover:bg-gray-700 transition"
            >
              ← Dashboard
            </.link>
            <button
              phx-click="refresh"
              class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition"
            >
              🔄 Refresh
            </button>
          </div>
        </div>

        <!-- Tabs -->
        <div class="mb-6 border-b border-gray-200">
          <nav class="-mb-px flex space-x-8">
            <button
              phx-click="switch_tab"
              phx-value-tab="instances"
              class={"#{if @active_tab == "instances", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium"}
            >
              Instances
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="amis"
              class={"#{if @active_tab == "amis", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium"}
            >
              AMI Management
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="configs"
              class={"#{if @active_tab == "configs", do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-4 px-1 border-b-2 font-medium"}
            >
              Configurations
            </button>
          </nav>
        </div>

        <!-- Tab Content -->
        <%= if @active_tab == "instances" do %>
          <.instance_panel
            instances={@instances}
            expanded_instance={@expanded_instance}
            deployments={@deployments}
          />
        <% end %>
        
        <%= if @active_tab == "amis" do %>
          <.ami_panel amis={@amis} pending_amis={@pending_amis} />
        <% end %>

        <%= if @active_tab == "configs" do %>
          <.config_panel configs={@configs} config_content={@config_content} />
        <% end %>
      </div>

      <!-- Modals -->
      <%= if @show_create_ami_modal do %>
        <.create_ami_modal ami_name={@ami_name} regions={@regions} selected_region={@selected_region} />
      <% end %>

      <%= if @show_copy_ami_modal do %>
        <.copy_ami_modal 
          copy_source_ami={@copy_source_ami} 
          copy_source_region={@copy_source_region}
          copy_target_region={@copy_target_region}
          regions={@regions}
        />
      <% end %>

      <%= if @show_launch_instance_modal do %>
        <.launch_instance_modal 
          configs={@configs} 
          selected_config={@selected_config}
          amis={@amis}
          availability_zones={@availability_zones}
          instance_types={@instance_types}
          launch_instance_type={@launch_instance_type}
          launch_availability_zone={@launch_availability_zone}
          launch_ami_id={@launch_ami_id}
          launch_spot_max_price={@launch_spot_max_price}
        />
      <% end %>

      <%= if @show_logs_modal do %>
        <.logs_modal log_content={@log_content} instance_id={@selected_instance} />
      <% end %>

      <%= if @show_deploy_config_modal do %>
        <.deploy_config_modal
          uploads={@uploads}
          deploy_key_file={@deploy_key_file}
          deploy_host={@deploy_host}
          deploy_branch={@deploy_branch}
          deploy_start={@deploy_start}
          deploy_auto_terminate={@deploy_auto_terminate}
          deploy_instance_id={@deploy_instance_id}
          available_branches={@available_branches}
        />
      <% end %>

      <%= if @show_terminal_modal do %>
        <.terminal_modal
          title={@terminal_title}
          output={@terminal_output}
          running={@operation_running}
        />
      <% end %>
    </div>
    """
  end

  # Components
  defp ami_panel(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-xl font-semibold">AMI Images</h2>
        <button
          phx-click="show_create_ami_modal"
          class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
        >
          ➕ Create AMI
        </button>
      </div>

      <%= if Enum.empty?(@amis) and Enum.empty?(@pending_amis) do %>
        <div class="text-center py-12 text-gray-500">
          No AMIs found. Create one to get started.
        </div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">AMI ID</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Region</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">State</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for ami <- @pending_amis do %>
                <tr class="bg-yellow-50 hover:bg-yellow-100 cursor-pointer transition" phx-click="view_operation_logs" phx-value-operation_id={ami.operation_id}>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-400">
                    <div class="flex items-center space-x-2">
                      <div class="animate-spin h-4 w-4 border-2 border-yellow-500 border-t-transparent rounded-full"></div>
                      <span>Creating...</span>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium"><%= ami.name %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600"><%= Map.get(ami, :region, "us-east-1") %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">In progress</td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class="px-2 py-1 text-xs rounded-full bg-yellow-100 text-yellow-800 animate-pulse">
                      <%= ami.state %>
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <button
                      phx-click="view_operation_logs"
                      phx-value-operation_id={ami.operation_id}
                      class="text-blue-600 hover:text-blue-800"
                    >
                      📋 View Logs
                    </button>
                  </td>
                </tr>
              <% end %>
              
              <%= for ami <- @amis do %>
                <tr class="hover:bg-gray-50 transition">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono"><%= ami.id %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm"><%= ami.name %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600"><%= Map.get(ami, :region, System.get_env("AWS_DEFAULT_REGION", "us-east-1")) %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm"><%= ami.created_at %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class="px-2 py-1 text-xs rounded-full bg-green-100 text-green-800">
                      <%= ami.state %>
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm space-x-2">
                    <button
                      phx-click="show_copy_ami_modal"
                      phx-value-ami_id={ami.id}
                      phx-value-region={Map.get(ami, :region, System.get_env("AWS_DEFAULT_REGION", "us-east-1"))}
                      class="text-blue-600 hover:text-blue-800"
                      title="Copy to another region"
                    >
                      📋 Copy
                    </button>
                    <button
                      phx-click="delete_ami"
                      phx-value-ami_id={ami.id}
                      data-confirm="Are you sure you want to delete this AMI?"
                      class="text-red-600 hover:text-red-800"
                    >
                      🗑️ Delete
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp instance_panel(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-xl font-semibold">EC2 Instances</h2>
        <button
          phx-click="show_launch_instance_modal"
          class="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition"
        >
          🚀 Launch Instance
        </button>
      </div>

      <%= if Enum.empty?(@instances) do %>
        <div class="text-center py-12 text-gray-500">
          No instances running. Launch one to get started.
        </div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Launch Time</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Instance ID</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Region</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">State</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for instance <- @instances do %>
                <tr>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    <%= format_launch_time(instance.launch_time) %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono">
                    <button
                      phx-click="toggle_instance_details"
                      phx-value-instance_id={instance.id}
                      class="text-blue-600 hover:text-blue-800 flex items-center space-x-1"
                    >
                      <span><%= if @expanded_instance == instance.id, do: "▼", else: "▶" %></span>
                      <span><%= instance.id %></span>
                    </button>
                  </td>
                  <td class="px-6 py-4 text-sm max-w-xs break-words"><%= instance.name %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm"><%= instance.type %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm"><%= Map.get(instance, :region, "unknown") %></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <span class={"px-2 py-1 text-xs rounded-full #{state_color(instance.state)}"}>
                      <%= instance.state %>
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm space-x-3">
                    <.link
                      navigate={"/aws-deployment/instance/#{instance.id}"}
                      class="text-purple-600 hover:text-purple-800 text-lg"
                      title="View Details"
                    >
                      📊
                    </.link>
                    <button
                      phx-click="show_logs"
                      phx-value-instance_id={instance.id}
                      class="text-blue-600 hover:text-blue-800 text-lg"
                      title="View Console Logs"
                    >
                      📋
                    </button>
                    <%= if Map.get(assigns, :deployments, %{}) |> Map.has_key?(instance.id) do %>
                      <button
                        phx-click="show_deploy_config_modal"
                        phx-value-instance_id={instance.id}
                        phx-value-ip={instance.ip}
                        class="text-green-600 hover:text-green-800 text-lg"
                        title="Config Deployed - Redeploy"
                      >
                        ✅
                      </button>
                    <% else %>
                      <button
                        phx-click="show_deploy_config_modal"
                        phx-value-instance_id={instance.id}
                        phx-value-ip={instance.ip}
                        class="text-orange-600 hover:text-orange-800 text-lg"
                        title="Deploy Configuration"
                      >
                        🚀
                      </button>
                    <% end %>
                    <button
                      phx-click="terminate_instance"
                      phx-value-instance_id={instance.id}
                      data-confirm="Are you sure you want to terminate this instance?"
                      class="text-red-600 hover:text-red-800 text-lg"
                      title="Terminate Instance"
                    >
                      ⛔
                    </button>
                  </td>
                </tr>
                <%= if @expanded_instance == instance.id do %>
                  <tr class="bg-blue-50">
                    <td colspan="7" class="px-6 py-4">
                      <div class="bg-white rounded-lg p-4 border-2 border-blue-200">
                        <h4 class="font-semibold text-gray-900 mb-3">Instance Details</h4>
                        <div class="grid grid-cols-2 gap-4 text-sm">
                          <div>
                            <span class="font-medium text-gray-700">Instance ID:</span>
                            <span class="ml-2 font-mono text-gray-900"><%= instance.id %></span>
                          </div>
                          <div>
                            <span class="font-medium text-gray-700">Instance Type:</span>
                            <span class="ml-2 text-gray-900"><%= instance.type %></span>
                          </div>
                          <div>
                            <span class="font-medium text-gray-700">Public IP:</span>
                            <span class="ml-2 font-mono text-gray-900"><%= instance.ip %></span>
                          </div>
                          <div>
                            <span class="font-medium text-gray-700">State:</span>
                            <span class="ml-2 text-gray-900"><%= instance.state %></span>
                          </div>
                          <div>
                            <span class="font-medium text-gray-700">Launch Time:</span>
                            <span class="ml-2 text-gray-900"><%= instance.launch_time %></span>
                          </div>
                          <div>
                            <span class="font-medium text-gray-700">Name:</span>
                            <span class="ml-2 text-gray-900"><%= instance.name %></span>
                          </div>
                        </div>
                        
                        <%= if Map.get(assigns, :deployments, %{}) |> Map.has_key?(instance.id) do %>
                          <div class="mt-4 pt-4 border-t border-green-200 bg-green-50 rounded p-3">
                            <div class="flex items-center space-x-2 mb-2">
                              <span class="text-green-600 text-lg">✅</span>
                              <span class="font-semibold text-green-800">Config Deployed</span>
                            </div>
                            <div class="text-sm space-y-1 text-gray-700">
                              <div>
                                <span class="font-medium">Branch:</span>
                                <span class="ml-2 font-mono"><%= @deployments[instance.id].branch %></span>
                              </div>
                              <div>
                                <span class="font-medium">Deployed:</span>
                                <span class="ml-2"><%= format_datetime(@deployments[instance.id].deployed_at) %></span>
                              </div>
                              <%= if @deployments[instance.id].started do %>
                                <div>
                                  <span class="font-medium">Status:</span>
                                  <span class="ml-2 text-green-600">🟢 Training Started</span>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                        
                        <%= if instance.ip != "N/A" do %>
                          <div class="mt-4 pt-4 border-t border-gray-200">
                            <span class="font-medium text-gray-700 mb-3 block">Quick Commands</span>
                            <div class="space-y-3">
                              <div>
                                <div class="flex items-center justify-between mb-1">
                                  <p class="text-xs text-gray-600">SSH Connection:</p>
                                  <button
                                    onclick={"navigator.clipboard.writeText('ssh -i AWS-Deployment/output/#{get_key_filename(instance.id)} ubuntu@#{instance.ip}')"}
                                    class="text-xs text-blue-600 hover:text-blue-800"
                                  >
                                    📋 Copy
                                  </button>
                                </div>
                                <code class="block bg-gray-900 text-green-400 p-2 rounded text-xs font-mono break-all select-all">ssh -i AWS-Deployment/output/<%= get_key_filename(instance.id) %> ubuntu@<%= instance.ip %></code>
                              </div>
                              <%= if Map.get(assigns, :deployments, %{}) |> Map.has_key?(instance.id) do %>
                                <div>
                                  <div class="flex items-center justify-between mb-1">
                                    <p class="text-xs text-gray-600">Attach to Training:</p>
                                    <button
                                      onclick="navigator.clipboard.writeText('tmux attach -t trader')"
                                      class="text-xs text-blue-600 hover:text-blue-800"
                                    >
                                      📋 Copy
                                    </button>
                                  </div>
                                  <code class="block bg-gray-900 text-green-400 p-2 rounded text-xs font-mono select-all">tmux attach -t trader</code>
                                </div>
                                <div>
                                  <div class="flex items-center justify-between mb-1">
                                    <p class="text-xs text-gray-600">View Logs:</p>
                                    <button
                                      onclick="navigator.clipboard.writeText('tail -f /var/log/dxnn-run.log')"
                                      class="text-xs text-blue-600 hover:text-blue-800"
                                    >
                                      📋 Copy
                                    </button>
                                  </div>
                                  <code class="block bg-gray-900 text-green-400 p-2 rounded text-xs font-mono select-all">tail -f /var/log/dxnn-run.log</code>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp config_panel(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <h2 class="text-xl font-semibold mb-6">Configuration Files</h2>

      <%= if Enum.empty?(@configs) do %>
        <div class="text-center py-12 text-gray-500">
          No configuration files found.
        </div>
      <% else %>
        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <%= for config <- @configs do %>
            <div class="border-2 border-gray-200 rounded-lg p-4 hover:shadow-lg transition">
              <h3 class="font-semibold text-lg mb-2"><%= config.name %></h3>
              <div class="text-sm text-gray-600 mb-3">
                <div>Type: <span class="font-medium"><%= config.instance_type %></span></div>
                <div>AMI: <span class="font-mono text-xs"><%= config.ami_id %></span></div>
              </div>
              <button
                phx-click="view_config"
                phx-value-config={config.name}
                class="w-full bg-blue-600 text-white px-3 py-2 rounded-md text-sm hover:bg-blue-700 transition"
              >
                View Config
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @config_content do %>
        <div class="mt-6 border-t pt-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-semibold">Configuration Content</h3>
            <button
              phx-click="close_config"
              class="text-gray-600 hover:text-gray-800"
            >
              ✕ Close
            </button>
          </div>
          <pre class="bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto text-sm"><%= @config_content %></pre>
        </div>
      <% end %>
    </div>
    """
  end

  defp create_ami_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 max-w-md w-full">
        <h3 class="text-lg font-semibold mb-4">Create New AMI</h3>
        <form phx-change="update_ami_name" phx-submit="create_ami">
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              AMI Name (optional)
            </label>
            <input
              type="text"
              name="ami_name"
              value={@ami_name}
              placeholder="Leave empty for auto-generated name"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Region
            </label>
            <select
              name="region"
              phx-change="select_region"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <%= for region <- @regions do %>
                <option value={region.name} selected={@selected_region == region.name}>
                  <%= region.display_name %> (<%= region.name %>)
                </option>
              <% end %>
            </select>
          </div>
          <p class="text-sm text-gray-600 mb-4">
            This will take approximately 10-15 minutes. You can monitor progress in the terminal.
          </p>
          <div class="flex justify-end space-x-2">
            <button
              type="button"
              phx-click="hide_create_ami_modal"
              class="px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
            >
              Create AMI
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp copy_ami_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 max-w-md w-full">
        <h3 class="text-lg font-semibold mb-4">Copy AMI to Another Region</h3>
        <form phx-submit="copy_ami">
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Source AMI
            </label>
            <input
              type="text"
              value={@copy_source_ami}
              class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50"
              readonly
            />
          </div>
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Source Region
            </label>
            <input
              type="text"
              value={@copy_source_region}
              class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50"
              readonly
            />
          </div>
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Target Region
            </label>
            <select
              name="target_region"
              phx-change="select_target_region"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="">-- Select Target Region --</option>
              <%= for region <- @regions do %>
                <%= if region.name != @copy_source_region do %>
                  <option value={region.name} selected={@copy_target_region == region.name}>
                    <%= region.display_name %> (<%= region.name %>)
                  </option>
                <% end %>
              <% end %>
            </select>
          </div>
          <p class="text-sm text-gray-600 mb-4">
            This will take approximately 10-15 minutes. You can monitor progress in the terminal.
          </p>
          <div class="flex justify-end space-x-2">
            <button
              type="button"
              phx-click="hide_copy_ami_modal"
              class="px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
            >
              Copy AMI
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp launch_instance_modal(assigns) do
    # Common instance types
    instance_types = [
      "t2.micro", "t2.small", "t2.medium", "t2.large",
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge",
      "c7i.large", "c7i.xlarge", "c7i.2xlarge", "c7i.4xlarge"
    ]
    
    assigns = assign(assigns, :instance_types, instance_types)
    
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <h3 class="text-lg font-semibold mb-4">Launch Instance</h3>
        <form phx-change="select_config" phx-submit="launch_instance">
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Select Configuration
            </label>
            <select
              name="config"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="">-- Select Config --</option>
              <%= for config <- @configs do %>
                <option value={config.name} selected={@selected_config == config.name}>
                  <%= config.name %> (<%= config.instance_type %>)
                </option>
              <% end %>
            </select>
          </div>

          <%= if @selected_config do %>
            <div class="border-t pt-4 mt-4">
              <h4 class="text-sm font-semibold text-gray-700 mb-3">Override Settings (Optional)</h4>
              
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Instance Type
                  </label>
                  <select
                    name="instance_type"
                    phx-change="update_launch_field"
                    phx-value-field="instance_type"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <%= for type <- @instance_types do %>
                      <option value={type} selected={@launch_instance_type == type}>
                        <%= type %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Spot Max Price
                  </label>
                  <input
                    type="text"
                    name="spot_max_price"
                    value={@launch_spot_max_price}
                    phx-change="update_launch_field"
                    phx-value-field="spot_max_price"
                    placeholder="0.38"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Availability Zone
                  </label>
                  <select
                    name="availability_zone"
                    phx-change="update_launch_field"
                    phx-value-field="availability_zone"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="">-- Auto Select --</option>
                    <%= for zone <- @availability_zones do %>
                      <option value={zone.name} selected={@launch_availability_zone == zone.name}>
                        <%= zone.name %> (<%= zone.region %>)
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    AMI ID
                  </label>
                  <select
                    name="ami_id"
                    phx-change="update_launch_field"
                    phx-value-field="ami_id"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <%= for ami <- @amis do %>
                      <option value={ami.id} selected={@launch_ami_id == ami.id}>
                        <%= ami.id %> - <%= ami.name %> [<%= Map.get(ami, :region, System.get_env("AWS_DEFAULT_REGION", "us-east-1")) %>]
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>

              <div class="mt-3 bg-blue-50 border border-blue-200 rounded p-3">
                <p class="text-xs text-blue-800">
                  Leave fields unchanged to use config defaults. Override only what you need.
                </p>
              </div>
            </div>
          <% end %>

          <div class="flex justify-end space-x-2 mt-6">
            <button
              type="button"
              phx-click="hide_launch_instance_modal"
              class="px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
            >
              Launch
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp logs_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 max-w-4xl w-full max-h-[80vh] flex flex-col">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-semibold">Instance Logs: <%= @instance_id %></h3>
          <button
            phx-click="hide_logs_modal"
            class="text-gray-600 hover:text-gray-800"
          >
            ✕ Close
          </button>
        </div>
        <div class="flex-1 overflow-auto">
          <pre class="bg-gray-900 text-gray-100 p-4 rounded-lg text-xs"><%= @log_content %></pre>
        </div>
      </div>
    </div>
    """
  end

  defp deploy_config_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <h3 class="text-lg font-semibold mb-4">Deploy Configuration</h3>
        
        <form phx-submit="deploy_config" phx-change="validate_upload">
          <input type="hidden" name="instance_id" value={@deploy_instance_id || ""} />
          <input type="hidden" name="key_file" value={@deploy_key_file} />
          <input type="hidden" name="host" value={@deploy_host} />
          <input type="hidden" name="start" value={to_string(@deploy_start)} />
          <input type="hidden" name="auto_terminate" value={to_string(@deploy_auto_terminate)} />
          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                SSH Key File
              </label>
              <div class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50 font-mono text-sm">
                <%= if @deploy_key_file != "" do %>
                  <%= Path.basename(@deploy_key_file) %>
                  <div class="text-xs text-gray-500 mt-1">
                    Full path: <%= @deploy_key_file %>
                  </div>
                <% else %>
                  <span class="text-red-600">⚠️ No key file found</span>
                <% end %>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Host IP
              </label>
              <input
                type="text"
                value={@deploy_host}
                class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50"
                readonly
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Files to Upload (Optional)
              </label>
              <p class="text-xs text-gray-500 mb-2">
                Upload files to override GitHub versions. Leave empty to use GitHub code only.
              </p>
              <div
                class="border-2 border-dashed border-gray-300 rounded-lg p-4 text-center hover:border-blue-400 transition"
                phx-drop-target={@uploads.config_file.ref}
              >
                <.live_file_input upload={@uploads.config_file} class="hidden" />
                <label for={@uploads.config_file.ref} class="cursor-pointer">
                  <div class="text-gray-600">
                    📁 Click to upload or drag and drop
                  </div>
                  <div class="text-sm text-gray-500 mt-1">
                    Any file type • Multiple files allowed
                  </div>
                </label>
              </div>
              
              <%= if length(@uploads.config_file.entries) > 0 do %>
                <div class="mt-3 space-y-2">
                  <p class="text-sm font-medium text-gray-700">Files to upload:</p>
                  <%= for entry <- @uploads.config_file.entries do %>
                    <div class="flex items-center justify-between bg-green-50 border border-green-200 rounded px-3 py-2">
                      <div class="flex items-center space-x-2">
                        <span class="text-green-600">✓</span>
                        <span class="text-sm font-mono"><%= entry.client_name %></span>
                        <span class="text-xs text-gray-500">(<%= Float.round(entry.client_size / 1024, 1) %> KB)</span>
                      </div>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="text-red-600 hover:text-red-800 text-sm"
                      >
                        ✕ Remove
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Git Branch / Version
              </label>
              <select
                name="branch"
                phx-change="update_branch_select"
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <%= for branch <- @available_branches do %>
                  <option value={branch} selected={@deploy_branch == branch}>
                    <%= branch %>
                  </option>
                <% end %>
                <option value="custom" selected={@deploy_branch not in @available_branches}>
                  Custom (enter below)
                </option>
              </select>
              
              <%= if @deploy_branch not in @available_branches do %>
                <input
                  type="text"
                  name="branch"
                  value={@deploy_branch}
                  phx-change="update_deploy_field"
                  phx-value-field="branch"
                  placeholder="Enter custom branch name"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md mt-2"
                />
              <% end %>
              
              <p class="text-xs text-gray-500 mt-1">
                Select a branch or version tag. If not selected, defaults to 'main'.
              </p>
            </div>

            <div class="flex items-center space-x-2">
              <input
                type="checkbox"
                id="deploy_start"
                checked={@deploy_start}
                phx-click="toggle_deploy_start"
                class="h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
              />
              <label for="deploy_start" class="text-sm text-gray-700 cursor-pointer">
                Start DXNN training after deployment
              </label>
            </div>

            <div class="flex items-center space-x-2">
              <input
                type="checkbox"
                id="deploy_auto_terminate"
                checked={@deploy_auto_terminate}
                phx-click="toggle_auto_terminate"
                class="h-4 w-4 text-red-600 border-gray-300 rounded focus:ring-red-500"
              />
              <label for="deploy_auto_terminate" class="text-sm text-gray-700 cursor-pointer">
                Auto-terminate on successful completion
              </label>
            </div>
            
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-3">
              <p class="text-sm text-blue-800">
                <strong>Deployment Order:</strong>
              </p>
              <ol class="text-xs text-blue-700 mt-2 space-y-1 ml-4 list-decimal">
                <li>Pull latest code from GitHub branch: <span class="font-mono"><%= @deploy_branch %></span></li>
                <li>Copy uploaded files (overwriting if exists)</li>
                <li>Compile all Erlang files</li>
                <%= if @deploy_start do %>
                  <li>Start DXNN training</li>
                <% end %>
                <%= if @deploy_auto_terminate do %>
                  <li class="text-red-700 font-medium">⚠️ Terminate instance only when training exits successfully</li>
                <% end %>
              </ol>
            </div>
          </div>

          <div class="flex justify-end space-x-2 mt-6">
            <button
              type="button"
              phx-click="hide_deploy_config_modal"
              class="px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
            >
              Deploy
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp terminal_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-900 bg-opacity-75 flex items-center justify-center z-50" phx-hook="PreventClose" id="terminal-modal">
      <div class="bg-gray-900 rounded-lg shadow-2xl max-w-6xl w-full max-h-[90vh] flex flex-col border-2 border-gray-700">
        <!-- Terminal Header -->
        <div class="bg-gray-800 px-4 py-3 rounded-t-lg flex justify-between items-center border-b border-gray-700">
          <div class="flex items-center space-x-2">
            <div class="flex space-x-2">
              <div class="w-3 h-3 rounded-full bg-red-500"></div>
              <div class="w-3 h-3 rounded-full bg-yellow-500"></div>
              <div class="w-3 h-3 rounded-full bg-green-500"></div>
            </div>
            <span class="text-gray-300 text-sm font-mono ml-4"><%= @title %></span>
          </div>
          <div class="flex items-center space-x-3">
            <%= if @running do %>
              <div class="flex items-center space-x-2">
                <div class="animate-pulse w-2 h-2 rounded-full bg-green-500"></div>
                <span class="text-green-400 text-xs font-mono">Running...</span>
              </div>
            <% else %>
              <span class="text-gray-400 text-xs font-mono">Completed</span>
            <% end %>
            <%= if not @running do %>
              <button
                phx-click="hide_terminal_modal"
                class="text-gray-400 hover:text-white transition"
              >
                ✕
              </button>
            <% end %>
          </div>
        </div>
        
        <!-- Terminal Body -->
        <div class="flex-1 overflow-auto p-4 bg-gray-900">
          <pre
            id="terminal-output"
            phx-hook="ScrollToBottom"
            class="text-green-400 font-mono text-sm whitespace-pre-wrap"
          ><%= @output %></pre>
        </div>
        
        <!-- Terminal Footer -->
        <div class="bg-gray-800 px-4 py-2 rounded-b-lg border-t border-gray-700">
          <div class="flex justify-between items-center text-xs text-gray-400 font-mono">
            <span>AWS Deployment Terminal</span>
            <%= if @running do %>
              <span class="text-yellow-400">⚠️ Operation running in background - safe to close browser</span>
            <% else %>
              <button
                phx-click="hide_terminal_modal"
                class="text-blue-400 hover:text-blue-300"
              >
                Press ESC or click ✕ to close
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp state_color("running"), do: "bg-green-100 text-green-800"
  defp state_color("pending"), do: "bg-yellow-100 text-yellow-800"
  defp state_color("stopping"), do: "bg-orange-100 text-orange-800"
  defp state_color("stopped"), do: "bg-red-100 text-red-800"
  defp state_color(_), do: "bg-gray-100 text-gray-800"
end
