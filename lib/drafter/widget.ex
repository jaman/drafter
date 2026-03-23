defmodule Drafter.Widget do
  @moduledoc """
  Widget behavior for TUI components.
  
  Defines the contract that all widgets must implement and provides
  utilities for widget lifecycle management.
  """

  alias Drafter.Draw.Strip
  alias Drafter.Event

  @type props :: map()
  @type state :: term()
  @type render_result :: [Strip.t()] | {:error, term()}
  @type event_result :: {:ok, state()} | {:error, term()} | {:noreply, state()} | {:bubble, state()}
  @type rect :: %{x: non_neg_integer(), y: non_neg_integer(), width: pos_integer(), height: pos_integer()}
  @type expand_option :: :fill | :content | pos_integer()
  @type scroll_direction :: :up | :down
  @type key :: atom()

  @doc "Initialize widget with props"
  @callback mount(props()) :: state()

  @doc "Render widget to strips"
  @callback render(state(), rect()) :: render_result()

  @doc "Handle events"
  @callback handle_event(Event.t(), state()) :: event_result()

  @doc "Update widget with new props"
  @callback update(props(), state()) :: state()

  @doc "Cleanup widget resources"
  @callback unmount(state()) :: :ok

  @doc "Handle scroll events"
  @callback handle_scroll(scroll_direction(), state()) :: event_result()

  @doc "Handle keyboard events"
  @callback handle_key(key(), state()) :: event_result()

  @doc "Handle mouse press (button down) events"
  @callback handle_press(x :: integer(), y :: integer(), state()) :: event_result()

  @doc "Handle mouse up events"
  @callback handle_mouse_up(x :: integer(), y :: integer(), state()) :: event_result()

  @doc "Handle drag events"
  @callback handle_drag(x :: integer(), y :: integer(), state()) :: event_result()

  @doc "Handle hover events"
  @callback handle_hover(x :: integer(), y :: integer(), state()) :: event_result()

  @doc "Handle custom events not covered by standard event types"
  @callback handle_custom_event(Event.t(), state()) :: event_result()

  @doc "Handle events during capture phase (before target widget)"
  @callback handle_event_capture(Event.Object.t(), state()) ::
              {:continue, Event.Object.t(), state()}
              | {:stop, Event.Object.t(), state(), list()}
              | {:prevent, Event.Object.t(), state()}

  @optional_callbacks [
    update: 2,
    unmount: 1,
    handle_scroll: 2,
    handle_key: 2,
    handle_press: 3,
    handle_mouse_up: 3,
    handle_drag: 3,
    handle_hover: 3,
    handle_custom_event: 2,
    handle_event_capture: 2
  ]

  @doc "Default mount implementation"
  def mount(_props), do: %{}

  @doc "Default render implementation"
  def render(_state, _rect), do: []

  @doc "Default event handler"
  def handle_event(_event, state), do: {:noreply, state}

  @doc "Default update implementation"
  def update(_props, state), do: state

  @doc "Default unmount implementation"
  def unmount(_state), do: :ok

  defmacro __using__(opts) do
    handles = Keyword.get(opts, :handles, [])
    capture_handles = Keyword.get(opts, :capture_handles, [])
    focusable = Keyword.get(opts, :focusable, :keyboard in handles)
    scroll_opts = Keyword.get(opts, :scroll)

    has_scroll = :scroll in handles
    scroll_config = parse_scroll_config(scroll_opts, has_scroll)

    quote do
      @behaviour Drafter.Widget

      alias Drafter.Widget.EventRouter

      @__widget_handles__ unquote(handles)
      @__widget_capture_handles__ unquote(capture_handles)
      @__widget_focusable__ unquote(focusable)
      @__widget_scroll_config__ unquote(Macro.escape(scroll_config))

      def __widget_capabilities__ do
        %{
          handles: @__widget_handles__,
          capture_handles: @__widget_capture_handles__,
          focusable: @__widget_focusable__,
          scroll: @__widget_scroll_config__
        }
      end

      def mount(props), do: Drafter.Widget.mount(props)
      def render(state, rect), do: Drafter.Widget.render(state, rect)
      def update(props, state), do: Drafter.Widget.update(props, state)
      def unmount(state), do: Drafter.Widget.unmount(state)

      def handle_event(event, state) do
        EventRouter.route_event(
          __MODULE__,
          event,
          state,
          @__widget_handles__,
          @__widget_focusable__,
          @__widget_scroll_config__
        )
      end

      def focused(state) when is_map(state) do
        Map.get(state, :focused, false)
      end

      def focused(_state), do: false

      def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

      def preferred_height(_args, _opts), do: 1

      defoverridable Drafter.Widget
      defoverridable focused: 1, update_props_from_mount: 3, preferred_height: 2
    end
  end

  defp parse_scroll_config(nil, false), do: nil
  defp parse_scroll_config(nil, true), do: %{direction: :horizontal, step: 5}

  defp parse_scroll_config(opts, _has_scroll) when is_list(opts) do
    %{
      direction: Keyword.get(opts, :direction, :horizontal),
      step: Keyword.get(opts, :step, 5),
      wrap: Keyword.get(opts, :wrap, false)
    }
  end
end
