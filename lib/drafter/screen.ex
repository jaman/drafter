defmodule Drafter.Screen do
  @moduledoc """
  Behaviour and data structure for screens in a TUI application.

  A screen encapsulates a full view with its own mount/render/event lifecycle.
  The `__using__` macro injects the `Drafter.Screen` behaviour and default
  no-op implementations for all callbacks, so modules only need to override
  what they use.

  Screens are layered: a screen can push a child screen onto the navigation
  stack, show a modal, popover, panel, or toast by returning the appropriate
  tagged tuple from `handle_event/2`. When a child screen is popped, the parent
  receives the return value via `on_resume/2`.

  Screen types and their options:

  - `:default` — full-screen view, no additional options
  - `:modal` — centered overlay with optional title and border; options: `width`, `height`, `position`, `overlay`, `overlay_opacity`, `dismissable`, `title`, `border`
  - `:popover` — small anchored overlay; options: `width`, `height`, `position`, `anchor`, `anchor_offset`, `dismissable`, `border`
  - `:toast` — timed notification; options: `width`, `position`, `duration`, `variant`, `dismissable`
  - `:panel` — edge-docked side panel; options: `width`, `height`, `position`, `overlay`, `resizable`, `collapsible`
  """

  @type props :: map()
  @type state :: term()
  @type result ::
          {:ok, state()}
          | {:noreply, state()}
          | {:pop, term()}
          | {:push, module(), props()}
          | {:replace, module(), props()}

  @callback mount(props()) :: state()
  @callback render(state()) :: term()
  @callback handle_event(term(), state()) :: result()
  @callback handle_event(term(), data :: term(), state()) :: result()
  @callback on_resume(result :: term(), state()) :: state()
  @callback unmount(state()) :: :ok

  @optional_callbacks [handle_event: 3, on_resume: 2, unmount: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Drafter.Screen
      import Drafter.App

      def mount(_props), do: %{}
      def render(_state), do: []
      def handle_event(_event, state), do: {:noreply, state}
      def handle_event(event, _data, state), do: handle_event(event, state)
      def on_resume(_result, state), do: state
      def unmount(_state), do: :ok
      def keybindings, do: []

      defoverridable mount: 1,
                     render: 1,
                     handle_event: 2,
                     handle_event: 3,
                     on_resume: 2,
                     unmount: 1,
                     keybindings: 0
    end
  end

  defstruct [
    :id,
    :module,
    :state,
    :props,
    :type,
    :options,
    :widget_hierarchy,
    :parent_id,
    :rect
  ]

  @type screen_type :: :default | :modal | :popover | :toast | :panel
  @type position :: :center | :top | :bottom | :left | :right | {:at, integer(), integer()}

  @type t :: %__MODULE__{
          id: reference(),
          module: module(),
          state: term(),
          props: map(),
          type: screen_type(),
          options: map(),
          widget_hierarchy: term(),
          parent_id: reference() | nil,
          rect: map() | nil
        }

  def new(module, props \\ %{}, opts \\ []) do
    type = Keyword.get(opts, :type, :default)
    options = build_options(type, opts)

    %__MODULE__{
      id: make_ref(),
      module: module,
      state: nil,
      props: props,
      type: type,
      options: options,
      widget_hierarchy: nil,
      parent_id: nil,
      rect: nil
    }
  end

  defp build_options(:modal, opts) do
    %{
      width: Keyword.get(opts, :width, :auto),
      height: Keyword.get(opts, :height, :auto),
      position: Keyword.get(opts, :position, :center),
      overlay: Keyword.get(opts, :overlay, true),
      overlay_color: Keyword.get(opts, :overlay_color, {0, 0, 0}),
      overlay_opacity: Keyword.get(opts, :overlay_opacity, 0.5),
      dismissable: Keyword.get(opts, :dismissable, true),
      title: Keyword.get(opts, :title, nil),
      border: Keyword.get(opts, :border, true)
    }
  end

  defp build_options(:popover, opts) do
    %{
      width: Keyword.get(opts, :width, :auto),
      height: Keyword.get(opts, :height, :auto),
      position: Keyword.get(opts, :position, {:at, 0, 0}),
      anchor: Keyword.get(opts, :anchor, nil),
      anchor_offset: Keyword.get(opts, :anchor_offset, {0, 1}),
      overlay: Keyword.get(opts, :overlay, false),
      dismissable: Keyword.get(opts, :dismissable, true),
      border: Keyword.get(opts, :border, true)
    }
  end

  defp build_options(:toast, opts) do
    %{
      width: Keyword.get(opts, :width, 40),
      position: Keyword.get(opts, :position, :bottom_right),
      duration: Keyword.get(opts, :duration, 3000),
      variant: Keyword.get(opts, :variant, :info),
      dismissable: Keyword.get(opts, :dismissable, true)
    }
  end

  defp build_options(:panel, opts) do
    %{
      width: Keyword.get(opts, :width, 30),
      height: Keyword.get(opts, :height, :full),
      position: Keyword.get(opts, :position, :right),
      overlay: Keyword.get(opts, :overlay, false),
      resizable: Keyword.get(opts, :resizable, false),
      collapsible: Keyword.get(opts, :collapsible, true)
    }
  end

  defp build_options(:default, _opts) do
    %{}
  end

  def mount_screen(%__MODULE__{} = screen) do
    state = screen.module.mount(screen.props)
    %{screen | state: state}
  end

  def unmount_screen(%__MODULE__{} = screen) do
    if function_exported?(screen.module, :unmount, 1) do
      screen.module.unmount(screen.state)
    end

    :ok
  end

  def handle_screen_event(%__MODULE__{} = screen, {:app_callback, name, data}) do
    result =
      if function_exported?(screen.module, :handle_event, 3) do
        screen.module.handle_event(name, data, screen.state)
      else
        screen.module.handle_event(name, screen.state)
      end

    normalize_screen_result(result, screen)
  end

  def handle_screen_event(%__MODULE__{} = screen, event) do
    result = dispatch_event(screen, event, nil)
    normalize_screen_result(result, screen)
  end

  defp dispatch_event(screen, event, extra_arg) do
    if function_exported?(screen.module, :handle_event, 3) do
      screen.module.handle_event(event, extra_arg, screen.state)
    else
      screen.module.handle_event(event, screen.state)
    end
  end

  defp normalize_screen_result({:ok, new_state}, screen), do: {:ok, %{screen | state: new_state}}

  defp normalize_screen_result({:noreply, new_state}, screen),
    do: {:noreply, %{screen | state: new_state}}

  defp normalize_screen_result(other, _screen), do: other

  def resume_screen(%__MODULE__{} = screen, result) do
    if function_exported?(screen.module, :on_resume, 2) do
      new_state = screen.module.on_resume(result, screen.state)
      %{screen | state: new_state}
    else
      screen
    end
  end

  def render_screen(%__MODULE__{} = screen) do
    screen.module.render(screen.state)
  end

  def calculate_rect(%__MODULE__{type: :default}, screen_rect) do
    screen_rect
  end

  def calculate_rect(%__MODULE__{type: :modal, options: opts}, screen_rect) do
    width = resolve_dimension(opts.width, screen_rect.width, 60)
    height = resolve_dimension(opts.height, screen_rect.height, 20)

    {x, y} = calculate_position(opts.position, width, height, screen_rect)

    %{x: x, y: y, width: width, height: height}
  end

  def calculate_rect(%__MODULE__{type: :popover, options: opts}, screen_rect) do
    width = resolve_dimension(opts.width, screen_rect.width, 30)
    height = resolve_dimension(opts.height, screen_rect.height, 10)

    {x, y} = calculate_position(opts.position, width, height, screen_rect)

    x = max(0, min(x, screen_rect.width - width))
    y = max(0, min(y, screen_rect.height - height))

    %{x: x, y: y, width: width, height: height}
  end

  def calculate_rect(%__MODULE__{type: :toast, options: opts}, screen_rect) do
    width = opts.width
    height = 3

    {x, y} =
      case opts.position do
        :bottom_right -> {screen_rect.width - width - 2, screen_rect.height - height - 2}
        :bottom_left -> {2, screen_rect.height - height - 2}
        :top_right -> {screen_rect.width - width - 2, 2}
        :top_left -> {2, 2}
        :bottom_center -> {div(screen_rect.width - width, 2), screen_rect.height - height - 2}
        :top_center -> {div(screen_rect.width - width, 2), 2}
        _ -> {screen_rect.width - width - 2, screen_rect.height - height - 2}
      end

    %{x: x, y: y, width: width, height: height}
  end

  def calculate_rect(%__MODULE__{type: :panel, options: opts}, screen_rect) do
    width = resolve_dimension(opts.width, screen_rect.width, 30)
    height = resolve_dimension(opts.height, screen_rect.height, screen_rect.height)

    {x, y} =
      case opts.position do
        :right -> {screen_rect.width - width, 0}
        :left -> {0, 0}
        :top -> {0, 0}
        :bottom -> {0, screen_rect.height - height}
        _ -> {screen_rect.width - width, 0}
      end

    case opts.position do
      pos when pos in [:left, :right] ->
        %{x: x, y: y, width: width, height: screen_rect.height}

      pos when pos in [:top, :bottom] ->
        %{x: 0, y: y, width: screen_rect.width, height: height}

      _ ->
        %{x: x, y: y, width: width, height: height}
    end
  end

  defp resolve_dimension(:auto, available, default), do: min(default, available - 4)
  defp resolve_dimension(:full, available, _default), do: available

  defp resolve_dimension(value, available, _default) when is_integer(value),
    do: min(value, available)

  defp resolve_dimension({:percent, pct}, available, _default), do: div(available * pct, 100)
  defp resolve_dimension(_, available, default), do: min(default, available)

  defp calculate_position(:center, width, height, screen_rect) do
    x = div(screen_rect.width - width, 2)
    y = div(screen_rect.height - height, 2)
    {x, y}
  end

  defp calculate_position(:top, width, _height, screen_rect) do
    {div(screen_rect.width - width, 2), 1}
  end

  defp calculate_position(:bottom, width, height, screen_rect) do
    {div(screen_rect.width - width, 2), screen_rect.height - height - 1}
  end

  defp calculate_position({:at, x, y}, _width, _height, _screen_rect) do
    {x, y}
  end

  defp calculate_position(_, width, height, screen_rect) do
    calculate_position(:center, width, height, screen_rect)
  end
end
