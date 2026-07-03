defmodule Drafter.Widget do
  @moduledoc """
  Widget behavior for TUI components.

  Defines the contract that all widgets must implement and provides
  utilities for widget lifecycle management.

  Supports two modes:

  **Legacy mode** (handles-based):
      use Drafter.Widget, handles: [:keyboard, :scroll], focusable: true

  **Trait mode** (composable traits):
      use Drafter.Widget, traits: [:focusable, :scrollable]
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
  @type layout_impact :: :self | :below | :above | :left | :right | :all | :parent

  @callback mount(props()) :: state()
  @callback render(state(), rect()) :: render_result()
  @callback handle_event(Event.t(), state()) :: event_result()
  @callback update(props(), state()) :: state()
  @callback unmount(state()) :: :ok
  @callback handle_scroll(scroll_direction(), state()) :: event_result()
  @callback handle_key(key(), state()) :: event_result()
  @callback handle_press(x :: integer(), y :: integer(), state()) :: event_result()
  @callback handle_mouse_up(x :: integer(), y :: integer(), state()) :: event_result()
  @callback handle_drag(x :: integer(), y :: integer(), state()) :: event_result()
  @callback handle_hover(x :: integer(), y :: integer(), state()) :: event_result()
  @callback handle_custom_event(Event.t(), state()) :: event_result()

  @callback handle_event_capture(Event.Object.t(), state()) ::
              {:continue, Event.Object.t(), state()}
              | {:stop, Event.Object.t(), state(), list()}
              | {:prevent, Event.Object.t(), state()}

  @callback apply_data_buffer(state(), Drafter.RingBuffer.t(), rect()) :: state()

  @callback on_rect_change(rect(), state()) :: state()

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
    handle_event_capture: 2,
    apply_data_buffer: 3,
    on_rect_change: 2
  ]

  def mount(_props), do: %{}
  def render(_state, _rect), do: []
  def handle_event(_event, state), do: {:noreply, state}
  def update(_props, state), do: state
  def unmount(_state), do: :ok

  defmacro __using__(opts) do
    traits = Keyword.get(opts, :traits, [])

    if traits != [] do
      generate_trait_based_widget(traits, opts)
    else
      generate_handles_based_widget(opts)
    end
  end

  defp generate_trait_based_widget(trait_specs, opts) do
    escaped_opts = Macro.escape(opts)
    extra_handles = Keyword.get(opts, :handles, [])
    layout_impact = Keyword.get(opts, :layout_impact, :self)

    quote do
      @behaviour Drafter.Widget

      alias Drafter.Widget.Trait
      alias Drafter.Widget.Trait.Pipeline

      @__trait_modules__ Trait.resolve_all(unquote(trait_specs), unquote(escaped_opts))
      @__extra_handles__ unquote(extra_handles)
      @__trait_handles__ Enum.uniq(Trait.collect_handles(@__trait_modules__) ++ @__extra_handles__)
      @__trait_focusable__ Trait.any_focusable?(@__trait_modules__)
      @__trait_default_state__ Trait.merge_default_states(@__trait_modules__)
      @__trait_bitmap__ Trait.build_bitmap(@__trait_modules__)
      @__trait_render_fields__ Trait.collect_render_affecting_fields(@__trait_modules__)
      @__trait_layout_static__ Trait.all_layout_static?(@__trait_modules__)
      @__layout_impact__ unquote(layout_impact)

      def __widget_capabilities__ do
        %{
          handles: @__trait_handles__,
          capture_handles: [],
          focusable: @__trait_focusable__,
          scroll: Trait.scroll_config(@__trait_modules__, unquote(escaped_opts)),
          traits: Enum.map(@__trait_modules__, & &1.name()),
          layout_impact: @__layout_impact__
        }
      end

      def __widget_traits__, do: @__trait_modules__
      def __widget_capabilities_bitmap__, do: @__trait_bitmap__
      def __render_affecting_fields__, do: @__trait_render_fields__
      def __layout_static__, do: @__trait_layout_static__
      def __trait_default_state__, do: @__trait_default_state__
      def __layout_impact__, do: @__layout_impact__

      def handle_event(event, state) do
        Pipeline.run(__MODULE__, @__trait_modules__, event, state, @__trait_handles__, @__trait_focusable__)
      end

      unquote(shared_widget_defaults())
    end
  end

  defp generate_handles_based_widget(opts) do
    handles = Keyword.get(opts, :handles, [])
    capture_handles = Keyword.get(opts, :capture_handles, [])
    focusable = Keyword.get(opts, :focusable, :keyboard in handles)
    scroll_config = parse_scroll_config(Keyword.get(opts, :scroll), :scroll in handles)
    layout_impact = Keyword.get(opts, :layout_impact, :self)

    quote do
      @behaviour Drafter.Widget

      alias Drafter.Widget.EventRouter

      @__widget_handles__ unquote(handles)
      @__widget_capture_handles__ unquote(capture_handles)
      @__widget_focusable__ unquote(focusable)
      @__widget_scroll_config__ unquote(Macro.escape(scroll_config))
      @__layout_impact__ unquote(layout_impact)

      def __widget_capabilities__ do
        %{
          handles: @__widget_handles__,
          capture_handles: @__widget_capture_handles__,
          focusable: @__widget_focusable__,
          scroll: @__widget_scroll_config__,
          layout_impact: @__layout_impact__
        }
      end

      def __layout_impact__, do: @__layout_impact__

      def handle_event(event, state) do
        EventRouter.route_event(
          __MODULE__, event, state, @__widget_handles__, @__widget_focusable__, @__widget_scroll_config__
        )
      end

      unquote(shared_widget_defaults())
    end
  end

  defp shared_widget_defaults do
    quote do
      def mount(props), do: Drafter.Widget.mount(props)
      def render(state, rect), do: Drafter.Widget.render(state, rect)
      def update(props, state), do: Drafter.Widget.update(props, state)
      def unmount(state), do: Drafter.Widget.unmount(state)

      def focused(state) when is_map(state), do: Map.get(state, :focused, false)
      def focused(_state), do: false

      def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props
      def preferred_height(_args, _opts), do: 1

      defoverridable Drafter.Widget
      defoverridable focused: 1, update_props_from_mount: 3, preferred_height: 2, __layout_impact__: 0
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
