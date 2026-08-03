defmodule Drafter.Widget do
  @moduledoc ~S"""
  Behaviour for a Drafter widget: a component that owns state, draws itself into a
  rect, and handles events.

  A widget module does `use Drafter.Widget, opts` and implements at least `c:mount/1`
  and `c:render/2`. Everything else is optional and has a default.

      defmodule MyWidgets.Counter do
        use Drafter.Widget, handles: [:keyboard, :press], focusable: true

        alias Drafter.Draw.{Segment, Strip}

        defstruct count: 0, focused: false

        def component_tag, do: :counter
        def from_component_opts(_args, opts), do: %{count: Keyword.get(opts, :count, 0)}

        @impl true
        def mount(props), do: %__MODULE__{count: Map.get(props, :count, 0)}

        @impl true
        def render(%__MODULE__{count: count}, _rect) do
          [Strip.new([Segment.new("count: #{count}", %{})])]
        end

        def handle_key(:up, state), do: {:ok, %{state | count: state.count + 1}}
        def handle_key(_key, state), do: {:bubble, state}

        def handle_press(_x, _y, state), do: {:ok, %{state | count: state.count + 1}}
      end

  `component_tag/0` and `from_component_opts/2` are what let the widget appear in a
  component tree as `{:counter, count: 3}`; they belong to
  the widget registry, not to this behaviour. Without them a widget is still
  usable as `{MyWidgets.Counter, %{count: 3}}`.

  ## `use Drafter.Widget` options

  Handles mode — the default, chosen whenever `:traits` is absent or empty:

    * `:handles` - the event kinds the widget wants, as a list of atoms. Default `[]`.
      `:keyboard`, `:char`, `:paste`, `:press` (`:click` is accepted for it),
      `:mouse_up`, `:drag`, `:hover`, `:scroll`. An event kind that is not declared
      is never routed to the widget, whatever callbacks it exports.
    * `:focusable` - `boolean()`. Default `:keyboard in handles`. A focusable widget
      takes part in tab order and gets `:focused` set on its state by `{:focus}` and
      `{:blur}`.
    * `:capture_handles` - event kinds the widget sees during the capture phase,
      before they reach their target. Default `[]`; requires
      `c:handle_event_capture/2`.
    * `:scroll` - keyword list configuring default scrolling: `:direction`
      (`:horizontal` default), `:step` (`5` default), `:wrap` (`false` default).
      Default `nil`, which becomes `%{direction: :horizontal, step: 5}` when
      `:scroll` is in `:handles`.
    * `:layout_impact` - how far a state change invalidates layout: `:self`
      (default), `:below`, `:above`, `:left`, `:right`, `:parent`, or `:all`.

  Trait mode — chosen when `:traits` is a non-empty list:

    * `:traits` - trait specs resolved by `Drafter.Widget.Trait`, e.g.
      `[:focusable, :scrollable]`. The traits supply the handles, focusability,
      default state, and the `handle_event/2` pipeline.
    * `:handles` - extra event kinds merged with the ones the traits declare.
    * `:scroll` - passed to the traits as `Drafter.Widget.Trait.scroll_config/2`
      reads it.
    * `:layout_impact` - as above.

  Trait mode reads no `:focusable` and no `:capture_handles`: focusability comes
  from the traits and the generated `__widget_capabilities__/0` reports
  `capture_handles: []`.

  Both modes generate `handle_event/2`, `__widget_capabilities__/0`, and
  `__layout_impact__/0`, and overridable defaults for `c:mount/1`, `c:render/2`,
  `c:update/2`, `c:unmount/1`, `focused/1`, `update_props_from_mount/3`, and
  `preferred_height/2`. Trait mode additionally generates `__widget_traits__/0`,
  `__widget_capabilities_bitmap__/0`, `__render_affecting_fields__/0`,
  `__layout_static__/0`, and `__trait_default_state__/0`.

  ## Event callbacks and their results

  `Drafter.Widget.EventRouter` turns each event into the matching callback, and only
  when the kind is declared and the function is exported. Every event callback
  returns one of:

    * `{:ok, new_state}` - handled. The event stops here and does not reach the
      parent.
    * `{:ok, new_state, actions}` - handled, plus a list of actions for the app; see
      `Drafter.EventResult`.
    * `{:bubble, new_state}` / `{:bubble, new_state, actions}` - the state is kept
      and the event continues to the parent widget, and then to the app.
    * `{:noreply, state}` - treated as *not handled*: the event continues **and the
      returned state is discarded**. Return `{:bubble, new_state}` to keep a change
      while still letting the event through.
    * an action tuple — `{:pop, result}`, `{:push, module, props}`,
      `{:replace, module, props}`, `{:app_callback, name, data}` - the action is
      recorded, the event stops, and the widget's state is left as it was before the
      event.

  Anything else counts as not handled and the state is left unchanged.

  ## Paste

  A widget receives pasted text only if it declares `:paste`:

      use Drafter.Widget, handles: [:keyboard, :paste], focusable: true

      def handle_paste(text, state), do: {:ok, %{state | value: state.value <> text}}

  `text` has already been through `Drafter.Clipboard.sanitize/1` and carries no
  escape sequences. A widget that does not declare `:paste` bubbles the event
  instead. `Drafter.Clipboard.copy/1` is the other direction.
  """

  alias Drafter.Draw.Strip
  alias Drafter.Event

  @type props :: map()
  @type state :: term()
  @type render_result :: [Strip.t()] | {:error, term()}

  @typedoc """
  An action a widget hands back to the app or the screen stack.

  `Drafter.EventResult.parse/2` recognises exactly these four shapes, records them
  and stops the event. `{:app_callback, name, data}` is the one the app itself
  handles, through `handle_event/3`.
  """
  @type action ::
          {:pop, term()}
          | {:push, module(), props()}
          | {:replace, module(), props()}
          | {:app_callback, atom(), term()}

  @typedoc """
  What an event callback may return.

  `Drafter.EventResult.parse/2` maps these onto `{state, actions, mode}`; anything
  else, including `{:error, reason}`, counts as not handled and leaves the state
  as it was.
  """
  @type event_result ::
          {:ok, state()}
          | {:ok, state(), [action()]}
          | {:bubble, state()}
          | {:bubble, state(), [action()]}
          | {:noreply, state()}
          | {:error, term()}
          | action()
  @type rect :: %{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer()
        }
  @type expand_option :: :fill | :content | pos_integer()
  @type scroll_direction :: :up | :down
  @type key :: atom()
  @type modifiers :: [:ctrl | :alt | :shift | :meta]
  @type layout_impact :: :self | :below | :above | :left | :right | :all | :parent

  @doc """
  Builds the widget's initial state from its props map.

  `props` comes from `from_component_opts/2` for a tag element, or is the map given
  directly in a `{Module, props}` element. The returned term is the widget's state,
  usually its own struct.
  """
  @callback mount(props()) :: state()

  @doc """
  Draws the widget into `rect`.

  `rect` is `%{x: , y: , width: , height: }` in absolute screen cells. Returns a list
  of `Drafter.Draw.Strip` structs, one per row starting at `rect.y`, or
  `{:error, reason}`. Called on every frame the widget is visible, so it must be
  free of side effects.
  """
  @callback render(state(), rect()) :: render_result()

  @doc """
  Handles an event.

  Generated by `use Drafter.Widget` and rarely written by hand: the generated version
  dispatches to `c:handle_key/2`, `c:handle_press/3`, and the rest according to the
  declared handles. Overriding it replaces that dispatch entirely.
  """
  @callback handle_event(Event.t(), state()) :: event_result()

  @doc """
  Folds a fresh props map into an existing state when the widget is re-rendered.

  Returns the state to keep. A widget that defines no `update/2` keeps its state
  unchanged, so state a widget owns and props do not describe — scroll offset, cursor
  position, drag state — survives a re-render.
  """
  @callback update(props(), state()) :: state()

  @doc "Releases the widget's resources as it leaves the hierarchy. Returns `:ok`."
  @callback unmount(state()) :: :ok

  @doc """
  Handles a scroll wheel event. Requires `:scroll` in `:handles`.

  `direction` is `:up` or `:down`. When `:scroll` is declared but this is not
  exported, the router moves `:_scroll_offset` on the state by the scroll config's
  `:step` instead.
  """
  @callback handle_scroll(scroll_direction(), state()) :: event_result()

  @doc """
  Handles a key press with no modifiers. Requires `:keyboard` in `:handles`.

  `key` is the key atom — `:enter`, `:up`, or a printable ASCII character as an atom.
  Also receives `{:key, key, []}` events when `c:handle_key/3` is not exported.
  """
  @callback handle_key(key(), state()) :: event_result()

  @doc """
  Handles a key press with modifiers. Requires `:keyboard` in `:handles`.

  `modifiers` is a subset of `[:ctrl, :alt, :shift]` in that order. Takes precedence
  over `c:handle_key/2` for every `{:key, key, modifiers}` event, including one with
  an empty modifier list.
  """
  @callback handle_key(key(), modifiers(), state()) :: event_result()

  @doc """
  Handles pasted text. Requires `:paste` in `:handles`.

  `text` has already passed through `Drafter.Clipboard.sanitize/1`.
  """
  @callback handle_paste(text :: String.t(), state()) :: event_result()

  @doc """
  Handles a mouse button press. Requires `:press` (or its alias `:click`) in
  `:handles`. `x` and `y` are absolute zero-based screen cells.
  """
  @callback handle_press(x :: integer(), y :: integer(), state()) :: event_result()

  @doc """
  Handles a mouse button release, the event that activates a widget. Requires
  `:mouse_up` in `:handles`. `x` and `y` are absolute zero-based screen cells.
  """
  @callback handle_mouse_up(x :: integer(), y :: integer(), state()) :: event_result()

  @doc """
  Handles mouse motion with a button held. Requires `:drag` in `:handles`.
  `x` and `y` are absolute zero-based screen cells.
  """
  @callback handle_drag(x :: integer(), y :: integer(), state()) :: event_result()

  @doc """
  Handles mouse motion with no button held. Requires `:hover` in `:handles`, and the
  app to have been started with hover tracking on.
  """
  @callback handle_hover(x :: integer(), y :: integer(), state()) :: event_result()

  @doc """
  Handles any event with no callback of its own — `{:timer, id}`, `{:custom, term}`,
  and `{:char, codepoint}` when `:char` is not declared. Needs no entry in `:handles`.
  """
  @callback handle_custom_event(Event.t(), state()) :: event_result()

  @doc """
  Inspects an event on its way down to its target, before the target sees it.
  Requires the event's kind in `:capture_handles`.

  Returns `{:continue, event, state}` to let it carry on to the target,
  `{:prevent, event, state}` to suppress the target's default behaviour, or
  `{:stop, event, state, actions}` to end the dispatch here and emit `actions`.
  """
  @callback handle_event_capture(Event.Object.t(), state()) ::
              {:continue, Event.Object.t(), state()}
              | {:stop, Event.Object.t(), state(), list()}
              | {:prevent, Event.Object.t(), state()}

  @doc """
  Whether the widget is drawing a transmitted image right now.

  A widget that exports `image/3` but only paints in some of its modes implements this
  so the runtime can skip the image pipeline entirely in the others: no per-frame
  placement, no generation task, no bytes. Absent, a widget exporting `image/3` counts
  as always active.

  Called on the current state on every frame, so it must be cheap.
  """
  @callback image_active?(state()) :: boolean()

  @doc """
  Folds the items accumulated in the widget's data channel into its state.

  Called when the throttle window of a widget declared with `:buffer` and `:refresh`
  opens. `buffer` is the `Drafter.RingBuffer` holding everything pushed since the
  last call; `rect` is the widget's current rect, so a widget can keep only as many
  points as it can draw. Returns the new state.
  """
  @callback apply_data_buffer(state(), Drafter.RingBuffer.t(), rect()) :: state()

  @optional_callbacks [
    update: 2,
    unmount: 1,
    handle_scroll: 2,
    handle_key: 2,
    handle_key: 3,
    handle_paste: 2,
    handle_press: 3,
    handle_mouse_up: 3,
    handle_drag: 3,
    handle_hover: 3,
    handle_custom_event: 2,
    handle_event_capture: 2,
    apply_data_buffer: 3,
    image_active?: 1
  ]

  @doc """
  Whether `module` draws a transmitted image for `state`.

  True only for a module exporting `image/3`, and then only when its `c:image_active?/1`
  says so; a module without that callback is active whenever it exports `image/3`. The
  runtime asks this before placing an image or asking one to be generated, so a widget
  in a character-drawing mode costs nothing on the image path.

      iex> Drafter.Widget.image_active?(Drafter.Widget.Label, %{})
      false

      iex> Drafter.Widget.image_active?(Drafter.Widget.Slider, Drafter.Widget.Slider.mount(%{renderer: :text}))
      false
  """
  @spec image_active?(module(), state()) :: boolean()
  def image_active?(module, state) do
    function_exported?(module, :image, 3) and
      (not function_exported?(module, :image_active?, 1) or module.image_active?(state))
  end

  @doc """
  Default `c:mount/1`: ignores the props and returns `%{}`.

      iex> Drafter.Widget.mount(%{count: 3})
      %{}
  """
  @spec mount(props()) :: state()
  def mount(_props), do: %{}

  @doc """
  Default `c:render/2`: draws nothing, returning `[]`.

      iex> Drafter.Widget.render(%{}, %{x: 0, y: 0, width: 10, height: 1})
      []
  """
  @spec render(state(), rect()) :: render_result()
  def render(_state, _rect), do: []

  @doc """
  Default `c:handle_event/2`: handles nothing, returning `{:noreply, state}`.

      iex> Drafter.Widget.handle_event({:key, :up}, %{count: 0})
      {:noreply, %{count: 0}}
  """
  @spec handle_event(Event.t(), state()) :: event_result()
  def handle_event(_event, state), do: {:noreply, state}

  @doc """
  Default `c:update/2`: ignores the props and returns `state` unchanged.

      iex> Drafter.Widget.update(%{count: 9}, %{count: 0})
      %{count: 0}
  """
  @spec update(props(), state()) :: state()
  def update(_props, state), do: state

  @doc """
  Default `c:unmount/1`: returns `:ok`.

      iex> Drafter.Widget.unmount(%{count: 0})
      :ok
  """
  @spec unmount(state()) :: :ok
  def unmount(_state), do: :ok

  @doc """
  Applies re-render props to a widget's state, using that widget's own `update/2`.

  `module` is the widget module, `props` the map from the new render, `state` the
  state as it stands. Returns the state to keep. A module that exports no `update/2`
  gets `state` back unchanged, so state the props do not describe — scroll offset,
  cursor and drag positions — survives.

  Both the in-hierarchy path and the widget's process go through this, so a widget
  behaves the same whether or not it runs in its own process.
  """
  @spec apply_props(module(), map(), state()) :: state()
  def apply_props(module, props, state) do
    if function_exported?(module, :update, 2) do
      module.update(props, state)
    else
      update(props, state)
    end
  end

  defmacro __using__(opts) do
    traits = Keyword.get(opts, :traits, [])

    if traits != [] do
      generate_trait_based_widget(traits, opts)
    else
      generate_handles_based_widget(opts)
    end
  end

  @handle_aliases %{click: :press}

  @doc """
  The event names a `handles:` list resolves to.

  Maps `:click` to `:press`, the name `Drafter.Widget.EventRouter` dispatches on, and
  removes duplicates. Every other atom is returned as given. A non-list argument is
  returned unchanged.

      iex> Drafter.Widget.normalize_handles([:click, :press, :keyboard])
      [:press, :keyboard]

      iex> Drafter.Widget.normalize_handles([:keyboard, :scroll])
      [:keyboard, :scroll]

      iex> Drafter.Widget.normalize_handles(nil)
      nil
  """
  @spec normalize_handles([atom()]) :: [atom()]
  @spec normalize_handles(term()) :: term()
  def normalize_handles(handles) when is_list(handles) do
    handles |> Enum.map(&Map.get(@handle_aliases, &1, &1)) |> Enum.uniq()
  end

  def normalize_handles(handles), do: handles

  defp generate_trait_based_widget(trait_specs, opts) do
    escaped_opts = Macro.escape(opts)
    extra_handles = opts |> Keyword.get(:handles, []) |> normalize_handles()
    layout_impact = Keyword.get(opts, :layout_impact, :self)

    quote do
      @behaviour Drafter.Widget

      alias Drafter.Widget.Trait
      alias Drafter.Widget.Trait.Pipeline

      @__trait_modules__ Trait.resolve_all(unquote(trait_specs), unquote(escaped_opts))
      @__extra_handles__ unquote(extra_handles)
      @__trait_handles__ Enum.uniq(
                           Trait.collect_handles(@__trait_modules__) ++ @__extra_handles__
                         )
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
        Pipeline.run(
          __MODULE__,
          @__trait_modules__,
          event,
          state,
          @__trait_handles__,
          @__trait_focusable__
        )
      end

      unquote(shared_widget_defaults())
    end
  end

  defp generate_handles_based_widget(opts) do
    handles = opts |> Keyword.get(:handles, []) |> normalize_handles()
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
          __MODULE__,
          event,
          state,
          @__widget_handles__,
          @__widget_focusable__,
          @__widget_scroll_config__
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

      defoverridable focused: 1,
                     update_props_from_mount: 3,
                     preferred_height: 2,
                     __layout_impact__: 0
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
