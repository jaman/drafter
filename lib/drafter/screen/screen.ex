defmodule Drafter.Screen do
  @moduledoc """
  Behaviour and data structure for screens in a TUI application.

  A screen encapsulates a full view with its own mount/render/event lifecycle.
  `use Drafter.Screen` injects the behaviour, `import Drafter.App` (so every
  element helper — `label/2`, `button/2`, `vertical/2` — is in scope), and
  overridable no-op implementations of `c:mount/1`, `c:render/1`,
  `c:handle_event/2`, `c:handle_event/3`, `c:on_resume/2`, `c:unmount/1` and
  `keybindings/0`, so a module only writes what it uses.

  Screens are layered. The screen manager keeps a stack; a screen pushes a
  child, replaces itself, opens a modal, or pops with a value by returning the
  matching tuple from `c:handle_event/2` or `c:handle_event/3` — see `t:result/0`
  for the shapes the runtime dispatches. When a child is popped the parent's
  `c:on_resume/2` receives the popped value.

      defmodule ConfirmDialog do
        use Drafter.Screen

        @impl true
        def mount(props), do: %{message: Map.get(props, :message, "Are you sure?")}

        @impl true
        def render(state) do
          vertical([
            label(state.message),
            button("OK", on_click: :confirm),
            button("Cancel", on_click: :cancel)
          ])
        end

        @impl true
        def handle_event(:confirm, _data, _state), do: {:pop, :confirmed}
        def handle_event(:cancel, _data, _state), do: {:pop, :cancelled}
        def handle_event(_event, _data, state), do: {:noreply, state}
      end

      Drafter.ScreenManager.show_modal(ConfirmDialog, %{message: "Delete?"},
        title: "Confirm",
        width: 40,
        height: 8
      )

  ## Screen types and their options

  The type is chosen with `:type` in the `opts` of `new/3`, and of
  `Drafter.App.push_screen/3` and `Drafter.App.replace_screen/3`, which pass `opts` straight
  through. Default `:default`. Any other value raises `FunctionClauseError`.
  Every key below is read once, when the screen is created; the map it produces
  is the `:options` field of `t:t/0`. Sizes are in terminal cells.

  `:default` — a full-screen view. Takes no options at all: `:options` is `%{}`
  and any other key passed with it is discarded.

  `:modal` — a centered overlay:

    * `:width` - `t:dimension/0`. Default `:auto`, which is 60 cells or the
      screen width minus 4, whichever is smaller.
    * `:height` - `t:dimension/0`. Default `:auto`, which is 20 rows or the
      screen height minus 4, whichever is smaller.
    * `:position` - `t:position/0`. Default `:center`.
    * `:overlay` - `boolean()`, whether the screen behind is dimmed. Default `true`.
    * `:overlay_color` - `{r, g, b}` with each component `0..255`. Default `{0, 0, 0}`.
    * `:overlay_opacity` - `float()` from `0.0` (invisible) to `1.0` (opaque).
      Default `0.5`.
    * `:dismissable` - `boolean()`. Default `true`. It decides who gets Escape,
      not what Escape does: `true` delivers Escape to this screen's
      `c:handle_event/2`, which must return `{:pop, result}` to close; `false`
      passes Escape down to the layer below untouched.
    * `:title` - `String.t()` shown in the border, or `nil`. Default `nil`.
    * `:border` - `boolean()`. Default `true`.

  `:popover` — a small anchored overlay:

    * `:width` - `t:dimension/0`. Default `:auto`, which is 30 cells or the screen
      width minus 4, whichever is smaller.
    * `:height` - `t:dimension/0`. Default `:auto`, which is 10 rows or the screen
      height minus 4, whichever is smaller.
    * `:position` - `t:position/0`. Default `{:at, 0, 0}`. The resulting rect is
      clamped to stay on screen.
    * `:anchor` - the widget id the popover is placed against, or `nil`. Default `nil`.
    * `:anchor_offset` - `{dx, dy}` in cells from the anchor. Default `{0, 1}`.
    * `:overlay` - `boolean()`. Default `false`.
    * `:dismissable` - `boolean()`. Default `true`, with the same meaning as for
      `:modal`: it routes Escape to the screen rather than closing it.
    * `:border` - `boolean()`. Default `true`.

  `:toast` — a timed notification pushed onto the screen stack:

    * `:width` - `pos_integer()`. Default `40`. The height is always 3 rows.
    * `:position` - `t:toast_position/0`. Default `:bottom_right`.
    * `:duration` - milliseconds on screen. Default `3000`.
    * `:variant` - `:info`, `:success`, `:warning`, or `:error`. Default `:info`.
    * `:dismissable` - `boolean()`. Default `true`.

  These are the options of a screen pushed with `type: :toast`.
  `Drafter.App.show_toast/2` is a different mechanism: it builds no
  screen, keeps its own toast list, and reads only `:variant` (default `:info`),
  `:duration` (default `3000`) and `:position` (default `:bottom_right`) from the
  options given to it.

  `:panel` — an edge-docked side panel:

    * `:width` - `t:dimension/0`. Default `30`. Used for `:left` and `:right`;
      a top or bottom panel is always the full screen width.
    * `:height` - `t:dimension/0`. Default `:full`. Used for `:top` and `:bottom`;
      a left or right panel is always the full screen height.
    * `:position` - `:left`, `:right`, `:top`, or `:bottom`. Default `:right`.
    * `:overlay` - `boolean()`. Default `false`.
    * `:resizable` - `boolean()`. Default `false`.
    * `:collapsible` - `boolean()`. Default `true`.

  ## Relationship to `Drafter.App`

  A screen is not an app. `Drafter.App` owns the terminal session, the timers,
  and the top-level event loop; a screen is one entry on the stack that session
  renders.

  A screen module can still be handed to `Drafter.run/2` or
  `Drafter.Test.start_headless/3`, because it exports the `mount/1`, `render/1`
  and `handle_event/2` the loop calls — but only if its `c:render/1` returns a
  non-empty tree. The loop falls back to `render/2` when `render/1` returns `[]`,
  and a screen defines no `render/2`, so an empty render raises
  `UndefinedFunctionError`. Nothing else app-specific applies: `on_ready/1`,
  `on_timer/2` and `__mouse_hover__/0` are absent and skipped, and the
  screen-stack results (`{:pop, _}` and friends) mean nothing at the top level.

  `keybinding/3` is imported along with the rest of `Drafter.App`, and it does
  compile inside a screen, but it does not work: `use Drafter.Screen` sets no
  `@before_compile` hook and no `@keybinding_hints` attribute, so the macro emits
  a warning about the undefined attribute, `keybindings/0` keeps returning `[]`
  (`Drafter.Widget.Footer` therefore shows nothing for the screen), and because
  the generated `c:handle_event/2` is overridable the keybinding clause replaces
  it outright — every event that does not match a `keybinding/3` clause raises
  `FunctionClauseError`. Write the key clauses by hand as `handle_event({:key, :q}, state)`
  with a catch-all clause, and define `keybindings/0` directly to feed the footer.
  """

  @type props :: map()
  @type state :: term()

  @typedoc """
  A screen's rect, and the screen area it is measured against, in terminal cells.
  """
  @type rect :: %{x: integer(), y: integer(), width: integer(), height: integer()}

  @typedoc """
  A width or height option.

  `:auto` takes the per-type default clamped to the screen minus 4 cells, `:full`
  takes the whole screen, an integer is that many cells clamped to the screen, and
  `{:percent, pct}` is `pct` percent of the screen. Any other value behaves as
  `:auto`.
  """
  @type dimension :: :auto | :full | pos_integer() | {:percent, 0..100}

  @typedoc """
  Where a `:modal` or `:popover` is placed.

  `{:at, x, y}` is an absolute cell. Any other value, including `:left` and
  `:right`, is treated as `:center`.
  """
  @type position :: :center | :top | :bottom | {:at, integer(), integer()}

  @typedoc "Where a `:toast` is placed. Any other value is treated as `:bottom_right`."
  @type toast_position ::
          :top_left
          | :top_center
          | :top_right
          | :bottom_left
          | :bottom_center
          | :bottom_right

  @typedoc "Which edge a `:panel` docks to. Any other value is treated as `:right`."
  @type panel_position :: :left | :right | :top | :bottom

  @typedoc """
  What `c:handle_event/2` and `c:handle_event/3` may return.

  These are the shapes the screen manager dispatches on. Anything else —
  including the three-element `{:push, module, props}` and
  `{:replace, module, props}`, `{:show_toast, message, opts}`, and
  `{:stop, reason}` — is discarded: the event is passed through to the layer
  below and the screen's state is left as it was.

    * `{:ok, state}` - keep `state` and redraw.
    * `{:noreply, state}` - keep `state`. The event carries on to the layer below
      unless the screen type captures it.
    * `{:pop, result}` - pop this screen; `result` reaches the parent's
      `c:on_resume/2`.
    * `{:push, module, props, opts}` - push a child screen; `opts` is the option
      list of the screen type given by its `:type` key.
    * `{:replace, module, props, opts}` - replace this screen with another.
    * `{:show_modal, module, props, opts}` - push `module` with `:type` forced to
      `:modal`.
  """
  @type result ::
          {:ok, state()}
          | {:noreply, state()}
          | {:pop, term()}
          | {:push, module(), props(), keyword()}
          | {:replace, module(), props(), keyword()}
          | {:show_modal, module(), props(), keyword()}

  @doc """
  Builds the screen's initial state from the props it was pushed with.

  `props` is the map given to `new/3`, `Drafter.App.push_screen/3`, or
  `show_modal/3`. The returned term becomes the `:state` field of `t:t/0` and is
  handed to every other callback. Called once, by `mount_screen/1`, before the
  first render. The generated default returns `%{}`.
  """
  @callback mount(props()) :: state()

  @doc """
  Builds the screen's element tree from its state.

  Returns what the element helpers of `Drafter.App` return — a `{:layout, ...}`
  or other element tuple, or a list of them. Called on every frame the screen is
  visible, so it must be free of side effects. The generated default returns `[]`.
  """
  @callback render(state()) :: term()

  @doc """
  Handles an event that reached this screen, without a payload.

  `event` is a raw terminal event (`{:key, key}`, `{:key, key, modifiers}`,
  `{:mouse, data}`), the atom `:passthrough_event` when a widget below changed
  but claimed nothing, or a widget callback name when the screen defines no
  `c:handle_event/3`.

  Returns a `t:result/0`. The generated default is `{:noreply, state}`.

  Because `use Drafter.Screen` always generates `c:handle_event/3`, the dispatcher
  always calls the three-argument form; a screen that defines only this one is
  reached through the generated bridge, which forwards with the payload dropped.
  Defining any clause here replaces the generated default entirely, so always
  finish with a catch-all clause.
  """
  @callback handle_event(term(), state()) :: result()

  @doc """
  Handles an event together with its payload.

  Called for every event the screen sees. `data` is the payload of a widget
  callback — the row a `DataTable` selected, the text a `TextInput` holds — and is
  `nil` for raw terminal events, which carry none.

  Returns a `t:result/0`. The generated default forwards to `c:handle_event/2`,
  discarding `data`.
  """
  @callback handle_event(term(), data :: term(), state()) :: result()

  @doc """
  Folds the value a popped child screen returned back into this screen's state.

  `result` is the term the child passed to `{:pop, result}`, and `nil` when the
  child was popped by `Drafter.App.pop_screen/1` with no argument. Returns the
  new state; there is no tuple to return. The generated default returns `state`
  unchanged.

      @impl true
      def on_resume(:confirmed, state), do: %{state | deleted: true}
      def on_resume(_result, state), do: state
  """
  @callback on_resume(result :: term(), state()) :: state()

  @doc """
  Releases the screen's resources as it leaves the stack. Returns `:ok`.

  Called by `unmount_screen/1` when the screen is popped or replaced. The return
  value is ignored. The generated default returns `:ok`.
  """
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

  @typedoc "The layout a screen is drawn with, chosen by the `:type` option of `new/3`."
  @type screen_type :: :default | :modal | :popover | :toast | :panel

  @typedoc """
  One entry on the screen stack.

  `:id` is assigned by `new/3` and identifies the screen to
  the screen manager. `:state` is `nil` until `mount_screen/1` runs.
  `:options` is the type's option map described in the module doc. `:parent_id`
  and `:rect` are filled in by the screen manager, and `:widget_hierarchy` by the
  renderer.
  """
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

  @doc """
  Builds an unmounted screen struct.

  `module` is the screen module, `props` the map its `c:mount/1` will receive
  (default `%{}`), and `opts` a keyword list whose `:type` picks the screen type
  (default `:default`) and whose remaining keys are that type's options, listed in
  the module doc. Keys the type does not read are discarded, and a `:type` that is
  not one of the five raises `FunctionClauseError`.

  The returned struct has a fresh `:id`, `:state` `nil` — `mount_screen/1` fills
  it in — and `:widget_hierarchy`, `:parent_id` and `:rect` `nil`.

      iex> screen = Drafter.Screen.new(MyModal, %{title: "Hi"}, type: :modal, width: 40)
      iex> screen.type
      :modal
      iex> screen.options.width
      40
      iex> screen.options.overlay_opacity
      0.5
      iex> screen.state
      nil

      iex> Drafter.Screen.new(MainScreen).options
      %{}
  """
  @spec new(module(), props(), keyword()) :: t()
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

  @doc """
  Calls the screen module's `c:mount/1` with the struct's props and stores the result.

  Returns the screen with `:state` set. Raises `FunctionClauseError` on anything
  that is not a `t:t/0`.
  """
  @spec mount_screen(t()) :: t()
  def mount_screen(%__MODULE__{} = screen) do
    state = screen.module.mount(screen.props)
    %{screen | state: state}
  end

  @doc """
  Calls the screen module's `c:unmount/1` if it exports one. Returns `:ok`.

  The callback's return value is ignored, and a module without one is left alone.
  """
  @spec unmount_screen(t()) :: :ok
  def unmount_screen(%__MODULE__{} = screen) do
    if function_exported?(screen.module, :unmount, 1) do
      screen.module.unmount(screen.state)
    end

    :ok
  end

  @doc """
  Runs one event through the screen module and folds the answer back into the struct.

  An `{:app_callback, name, data}` event is delivered as `name` with `data`; every
  other event is delivered as itself with `nil` for the payload. Both go to
  `c:handle_event/3` whenever the module exports it, which every module built with
  `use Drafter.Screen` does.

  `{:ok, state}` and `{:noreply, state}` come back as `{:ok, screen}` and
  `{:noreply, screen}` with the new state stored. Every other value — the
  navigation results of `t:result/0`, and anything unrecognised — is returned
  exactly as the callback produced it, with the screen struct unchanged.
  """
  @spec handle_screen_event(t(), term()) :: {:ok, t()} | {:noreply, t()} | term()
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

  @doc """
  Hands `result` to the screen module's `c:on_resume/2` and stores the state it returns.

  `result` is the value the popped child screen passed to `{:pop, result}`.
  Returns the screen unchanged when the module exports no `on_resume/2`.
  """
  @spec resume_screen(t(), term()) :: t()
  def resume_screen(%__MODULE__{} = screen, result) do
    if function_exported?(screen.module, :on_resume, 2) do
      new_state = screen.module.on_resume(result, screen.state)
      %{screen | state: new_state}
    else
      screen
    end
  end

  @doc """
  Calls the screen module's `c:render/1` with the stored state and returns its element tree.
  """
  @spec render_screen(t()) :: term()
  def render_screen(%__MODULE__{} = screen) do
    screen.module.render(screen.state)
  end

  @doc """
  The rect a screen occupies inside `screen_rect`, from its type and options.

  `screen_rect` is the whole terminal area as `t:rect/0`. The result is a
  `t:rect/0` too. `:default` returns `screen_rect` itself. `:modal` is sized and
  placed by its options and is not clamped, so an oversized `:position` can put it
  partly off screen; `:popover` is clamped into `screen_rect`. `:toast` is always
  3 rows tall and sits 2 cells in from the corner its `:position` names. A `:left`
  or `:right` `:panel` is always the full screen height and a `:top` or `:bottom`
  panel the full width, whatever `:height` and `:width` say.

      iex> modal = Drafter.Screen.new(MyModal, %{}, type: :modal, width: 40, height: 10)
      iex> Drafter.Screen.calculate_rect(modal, %{x: 0, y: 0, width: 80, height: 24})
      %{x: 20, y: 7, width: 40, height: 10}

      iex> toast = Drafter.Screen.new(Banner, %{}, type: :toast)
      iex> Drafter.Screen.calculate_rect(toast, %{x: 0, y: 0, width: 80, height: 24})
      %{x: 38, y: 19, width: 40, height: 3}

      iex> panel = Drafter.Screen.new(Sidebar, %{}, type: :panel, width: 30)
      iex> Drafter.Screen.calculate_rect(panel, %{x: 0, y: 0, width: 80, height: 24})
      %{x: 50, y: 0, width: 30, height: 24}

      iex> full = Drafter.Screen.new(MainScreen)
      iex> Drafter.Screen.calculate_rect(full, %{x: 0, y: 0, width: 80, height: 24})
      %{x: 0, y: 0, width: 80, height: 24}
  """
  @spec calculate_rect(t(), rect()) :: rect()
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
