defmodule DxnnAnalyzerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="page-header">
      <div class="min-w-0">
        <h1 class="page-title"><%= @title %></h1>
        <p :if={@description} class="page-description"><%= @description %></p>
      </div>
      <div :if={@actions != []} class="page-actions"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  attr :name, :string, required: true, values: ~w(grid chart flask layers folder server)
  attr :class, :string, default: "h-4 w-4 shrink-0"

  def icon(assigns) do
    paths = %{
      "grid" => "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
      "chart" => "M4 3v17h17 M8 15v-4 M13 15V7 M18 15V4",
      "flask" => "M9 3h6 M10 3v6L4 19a1 1 0 0 0 1 2h14a1 1 0 0 0 1-2L14 9V3 M8 14h8",
      "layers" => "m12 3 10 5-10 5L2 8z M2 12l10 5 10-5 M2 16l10 5 10-5",
      "folder" => "M3 6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z",
      "server" => "M4 3h16v7H4z M4 14h16v7H4z M7 6.5h.01 M7 17.5h.01 M11 6.5h6 M11 17.5h6"
    }

    assigns = assign(assigns, :path, Map.fetch!(paths, assigns.name))

    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d={@path} />
    </svg>
    """
  end

  @doc """
  Renders flash notices.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :warning, :error], doc: "used for styling"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      role="alert"
      class={[
        "flash-notice",
        @kind == :info && "border-emerald-200 text-emerald-800",
        @kind == :warning && "border-amber-200 text-amber-800",
        @kind == :error && "border-red-200 text-red-800"
      ]}
    >
      <p class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <span class="text-[0.8125rem]"><%= msg %></span>
      </p>
      <button
        type="button"
        class="absolute top-1 right-1 p-2"
        aria-label="Dismiss notification"
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("#flash-#{@kind}")}
      >
        <span aria-hidden="true">&times;</span>
      </button>
    </div>
    """
  end

  @doc """
  Renders a group of flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="flash-stack">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:translate-x-0",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:translate-x-2"}
    )
  end
end
