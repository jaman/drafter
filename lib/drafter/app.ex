defmodule Drafter.App do
  @moduledoc ~S"""
  Declarative API for building a Drafter terminal application.

  An application is a module that does `use Drafter.App` and implements
  `c:mount/1`, `c:render/1`, and one or both `handle_event` callbacks. Drafter owns
  the terminal, the event loop, layout, theming, and rendering; the module supplies
  state and a component tree.

  ## Complete application

  This module compiles and runs as written:

      defmodule Counter do
        use Drafter.App

        def mount(_props), do: %{count: 0}

        def render(state) do
          vertical([
            header("Counter"),
            label("Count: #{state.count}", style: %{bold: true}),
            horizontal(
              [
                button("Decrement", on_click: :decrement),
                button("Increment", on_click: :increment, variant: :primary)
              ],
              gap: 2
            ),
            footer()
          ])
        end

        keybinding :q, "quit" do
          {:stop, :normal}
        end

        def handle_event(:increment, _data, state), do: {:ok, %{state | count: state.count + 1}}
        def handle_event(:decrement, _data, state), do: {:ok, %{state | count: state.count - 1}}
        def handle_event(_name, _data, state), do: {:noreply, state}
      end

      Drafter.run(Counter)

  ## `use Drafter.App` options

    * `:css_path` - `String.t()`, path to a CSS file used for widget styling.
      Default `nil`.
    * `:styles` - `map()` of inline style overrides. Default `%{}`.
    * `:mouse_hover` - `boolean()`. `true` (default) puts the terminal into hover
      tracking mode for this app. `false` cuts mouse event volume for apps with no
      hover effects.
    * `:runtime` - the runtime backend: a module, or the shorthand `:callback`,
      `:reducer`, or `:shared`. Default `Drafter.Runtime.Callback`, the
      `mount`/`render`/`handle_event` style described here. See `Drafter.Runtime`.

  No other key is read; an unknown one is silently ignored. Each of these four is
  exposed on the module as `__css_path__/0`, `__inline_styles__/0`,
  `__mouse_hover__/0`, and `__runtime__/0`, which the loop calls and which are not
  overridable.

  `use Drafter.App` imports this module, so every element constructor
  (`vertical/2`, `label/2`, `button/2`, …) and the `keybinding/3` macro are
  available unqualified. A separate `import Drafter.App` is redundant.

  It also defines overridable defaults for `c:mount/1` (returns `%{}`),
  `c:render/1` (returns `[]`), `c:on_ready/1`, `c:unmount/1`, and `keybindings/0`,
  and appends catch-all clauses for `handle_event/2` (returns `{:noreply, state}`)
  and `c:on_timer/2` (returns the state) after every clause the module defined.
  A module therefore never has to write those two catch-alls. `handle_event/3` gets
  no catch-all: a module that defines any `handle_event/3` clause must define its
  own final clause or an unmatched named callback raises `FunctionClauseError`.

  ## Callbacks

    * `c:mount/1` — `mount(props :: map()) :: state`. Builds the initial state from
      the map passed under `:props` to `Drafter.run/2` (`%{}` when absent). `state`
      is any term; a map is what the element constructors and `Drafter.Test` expect.
    * `c:render/1` — `render(state) :: element | [element]`. Returns the component
      tree: the tuples produced by the constructors in this module, the
      `{WidgetModule, props_map}` tuples produced by `Drafter.label/2` and friends,
      or a list of either. Called after every state change; it must be pure.
    * `handle_event/2` — `handle_event(event, state) :: result`. Raw input events:
      `{:key, key}`, `{:key, key, modifiers}`, `{:char, codepoint}`, `{:mouse, map}`,
      `{:resize, {width, height}}`, and the other members of `t:Drafter.Event.t/0`.
      Printable ASCII arrives as a named key — `q` is `{:key, :q}`, `/` is
      `{:key, :/}` — and only codepoints above ASCII 126 arrive as
      `{:char, codepoint}`. See `Drafter.Terminal.ANSI` for the full set of shapes,
      and "Where a key is handled" below for which keys reach this callback at all.
    * `handle_event/3` — `handle_event(name, data, state) :: result`. Named
      callbacks: `name` is the atom given to a widget as `on_click:`, `on_change:`,
      and so on; `data` is that widget's payload (`nil` for widgets with no
      payload). Also how `Drafter.send_app_event/2` and a popped screen's result
      arrive.

  Optional lifecycle callbacks, each returning the new state — omit them and the
  state passes through unchanged:

    * `c:on_ready/1` — after the first render, before the first event. The place to
      start timers with `Drafter.set_interval/2`.
    * `c:on_timer/2` — `on_timer(timer_id, state)`, once per firing of a timer
      registered with `Drafter.set_interval/2` or `Drafter.set_timeout/2`.
    * `c:on_message/2` — `on_message(msg, state)` for any process message delivered
      to the loop that Drafter does not itself handle (PubSub broadcasts, `send/2`).
    * `c:on_scroll_active/1` — on the first scroll event of a scroll gesture.
    * `c:on_scroll_idle/1` — 150 ms after the last scroll event of a gesture.
    * `c:update/2` — `update(props, state)`, when a parent re-renders this module
      with new props.
    * `c:unmount/1` — returns `:ok`; called once as the app stops.
    * `c:refresh_rate/0` — the frame interval: `"30fps"`, `"7.5fps"`, a millisecond
      integer, or `:unlimited`. Default `"30fps"`.

  ## Where a key is handled

  `handle_event/2` — and therefore every `keybinding/3` clause, which is only a
  `handle_event/2` clause — is not the first thing to see an input event. Three
  things run ahead of it.

  **`Ctrl+Q` stops the loop** before any callback runs, always. A
  `keybinding {:q, [:ctrl]}` clause and a hand-written `{:key, :q, [:ctrl]}` clause
  are both unreachable. `Ctrl+C` is *not* reserved and does reach the module.

  **A non-empty `Drafter.ScreenManager` stack takes every event.** After a
  `{:push, ...}`, `{:replace, ...}` or `{:show_modal, ...}` the root application
  module's `handle_event/2` is not called at all; input goes to the screen stack.
  Its `keybinding/3` clauses are dormant until the last screen pops.

  **The widget hierarchy runs before the app whenever a widget holds focus.** A tree
  containing no focusable widget has no focus and never enters this path; a tree
  containing focusable widgets focuses the first of them on the initial render. So:

    * *Nothing focused* — `handle_event/2` runs first, and `{:noreply, state}` then
      offers the event to the hierarchy.
    * *Something focused* — the hierarchy runs first. Only events it leaves
      unconsumed reach `handle_event/2`, and the hierarchy has already had its turn
      by then, so `{:noreply, state}` does not offer the event a second time.

  The hierarchy counts an event as consumed when a widget produced an action or when
  focus moved. That makes the following keys reserved **while a widget is focused**:

    * `Tab` and `Shift+Tab` cycle focus and are consumed. The exception is a tree
      holding exactly one focusable widget: focus cannot move, so the key falls
      through to `handle_event/2`. A focused widget carrying both `focused` and
      `trap_focus` in its state — `Drafter.Widget.TextArea` with `trap_focus: true` —
      receives the key itself instead of moving focus.
    * `↑`, `↓`, `←`, `→` are offered to directional focus navigation first. They are
      consumed when a neighbouring widget takes focus, and otherwise fall through to
      the focused widget and then to `handle_event/2`.
    * Every other key is dispatched to the focused widget, so what is reserved
      depends on which widget that is. A focused `Drafter.Widget.Button` consumes
      `Enter` and `Space` and fires its `:on_click`. A focused
      `Drafter.Widget.TextInput` consumes every printable key, `Space` and the
      editing keys, but leaves `Enter` alone.

  `Esc`, `PageUp`/`PageDown`, `Home`/`End`, `Ctrl+C` and the function keys are not
  reserved by the framework and reach `handle_event/2` unless the focused widget
  claims them.

  A key the hierarchy consumed still reaches the module through `handle_event/3` when
  the widget carried a callback: `Enter` on `button("Save", on_click: :save)` calls
  `handle_event(:save, nil, state)`.

  ## Event results

  Both `handle_event` callbacks return one of:

    * `{:ok, new_state}` — the app handled the event. `new_state` replaces the state
      and the app re-renders. The event is not offered to the widget hierarchy again.
    * `{:noreply, new_state}` — the app did not handle the event. `new_state`
      replaces the state, and the event is routed to the widget hierarchy — the
      focused widget first, then bubbling to its ancestors — **only if the hierarchy
      has not already been offered it**, which per "Where a key is handled" it has
      whenever a widget holds focus. This is what a catch-all clause returns;
      returning `{:ok, state}` from a catch-all swallows every event the hierarchy
      did not already claim.
    * `{:stop, reason}` — the loop terminates. `:normal` makes `Drafter.run/2`
      return `:ok`; any other reason makes it return `{:error, reason}`. Inside a
      nested session, control returns to the parent app instead of exiting.
    * `{:error, reason}` — the event is discarded and the state is left unchanged.
    * `{:show_modal, screen_module, props, opts}` — see `show_modal/3`.
    * `{:show_toast, message, opts}` — see `show_toast/2`.
    * `{:pop, result}` — see `pop_screen/1`.
    * `{:push, screen_module, props, opts}` and
      `{:replace, screen_module, props, opts}` — push a screen onto, or replace the
      top of, the `Drafter.ScreenManager` stack.

  Any other term returned from `handle_event/3` is offered to the handlers
  registered with `Drafter.ActionRegistry`; see `Drafter.ActionHandler`. An
  unrecognised term leaves the state unchanged. Any other term returned from
  `handle_event/2` raises `FunctionClauseError` in the loop.

  ## Element options

  Every constructor takes a trailing keyword list. These keys are read for all of
  them:

    * `:id` - `atom()`, the widget id used by `Drafter.get_widget_value/1`,
      `Drafter.focus/1`, and `Drafter.Test`. Default `nil`, which generates
      `:"<LastModulePart>_<type>_<n>"`, e.g. `:Counter_label_1`.
    * `:key` - a stable identity for a widget whose position in the tree moves, used
      in place of the positional part of the generated id. Default `nil`. A `:key`
      produces a **`String.t()`** widget id of the form `"Counter_label#abc"`, not an
      atom, so pass that string to `Drafter.focus/1` and `Drafter.Test.query_one/2`.
      Ignored when `:id` is also given.
    * `:visible` - `boolean()`, default `true`. `false` omits the element and its
      children from the hierarchy entirely and its siblings close the gap.
    * `:visibility` - `:hidden` allots the element its space and draws nothing in it.
      Default `nil`, which draws normally.
    * `:margin` - space outside the element: an integer for all four sides, a
      `{vertical, horizontal}` tuple, or a `{top, right, bottom, left}` tuple.
      Default `nil`, i.e. no margin. Any other shape is treated as no margin.
    * `:dock` - `:top`, `:bottom`, `:left`, or `:right`. Default `nil`. A docked
      element leaves the normal flow and takes the full span of that edge; the
      remaining space is shared by its undocked siblings. A `footer/1` element is
      docked to `:bottom` whether or not the option is given. Only a `vertical/2`
      container honours this — inside a `horizontal/2` a docked child is laid out
      like any other.

  A layout container reads `:gap` (default `0`) and `:padding` from its own options,
  and `:width`, `:height`, `:flex`, `:min_width`/`:max_width`, and
  `:min_height`/`:max_height` from each child's options to divide its space.
  `:width` and `:height` take a cell count, `{:percent, n}`, `{:fr, n}` for a share
  of what is left after fixed siblings, or `:auto` for the child's own preferred
  size. `:padding` takes the same shapes as `:margin`.

  Remaining keys are the individual widget's props; each is documented on the widget
  module under `Drafter.Widget`. Note that the element constructors here do not
  forward every prop a widget's `mount/1` accepts — each constructor below names the
  keys its own widget reads only when mounted directly.
  """

  alias Drafter.{Event, Widget}

  @type props :: map()
  @type state :: term()
  @type rect :: Widget.rect()

  @typedoc "The trailing keyword list every element constructor accepts."
  @type opts :: keyword()

  @typedoc """
  A node of a component tree.

  Either a tag tuple built by one of the constructors in this module — the tag atom,
  zero to two positional arguments, and the options keyword list last — or a
  `{WidgetModule, props_map}` tuple as `Drafter.label/2` and friends build.
  """
  @type element ::
          {atom(), opts()}
          | {atom(), term(), opts()}
          | {atom(), term(), term(), opts()}
          | {module(), map()}

  @typedoc "The direction a layout container arranges its children in."
  @type direction :: :vertical | :horizontal

  @typedoc """
  A screen-stack instruction both `handle_event` callbacks dispatch.

  Note the four-element `{:push, ...}` and `{:replace, ...}`, which are what the loop
  matches — not the tags `push_screen/3` and `replace_screen/3` build.
  """
  @type screen_action ::
          {:show_modal, module(), props(), opts()}
          | {:show_toast, String.t(), opts()}
          | {:push, module(), props(), opts()}
          | {:replace, module(), props(), opts()}
          | {:pop, term()}

  @doc """
  Builds the application's initial state from its mount props.

  `props` is the map passed under `:props` to `Drafter.run/2`, `Drafter.run_session/3`,
  or `Drafter.Test.start_headless/3`, and is `%{}` when none were given. The returned
  term is the state handed to every other callback.
  """
  @callback mount(props()) :: state()

  @doc """
  Returns the component tree for the current state.

  An element tuple from a constructor in this module, a `{WidgetModule, props_map}`
  tuple, or a list of either. Called after every state change, so it must be free of
  side effects.
  """
  @callback render(state()) :: term()

  @doc """
  Handles a named callback.

  `event_name` is whatever term a widget was given as `on_click:`, `on_change:`, and
  so on, or the name passed to `Drafter.send_app_event/2`. It is normally an atom,
  but any non-function term is passed through unchanged — `switch_group/2` delivers
  the tuple `{:switch_group_changed, group_name, value}` this way. `data` is the
  widget's payload, `nil` for widgets that carry none.

  Returns `{:ok, new_state}` to accept the change and re-render, `{:noreply, new_state}`
  to accept it without claiming the event, `{:stop, reason}` to end the app, or
  `{:error, reason}` to discard it, or a `t:screen_action/0`. Any other term is offered
  to the handlers registered with `Drafter.ActionRegistry`, and an unrecognised one
  leaves the state unchanged — which is why the return type here is `term()` rather
  than a closed union.

  No catch-all clause is generated for this callback: a module that defines any
  clause must also define a final one, or an unmatched name raises `FunctionClauseError`.
  """
  @callback handle_event(event_name :: term(), data :: term(), state()) :: term()

  @doc """
  Handles a raw input event.

  `event` is a `t:Drafter.Event.t/0` tuple — `{:key, key}`, `{:key, key, modifiers}`,
  `{:char, codepoint}`, `{:mouse, map}`, `{:resize, {width, height}}`, and the rest.
  Printable ASCII 32..126 arrives as a named key (`{:key, :q}`, `{:key, :" "}`); only
  codepoints above 126 arrive as `{:char, codepoint}`.

  This callback does **not** see every event. `Ctrl+Q` stops the loop first; a
  non-empty `Drafter.ScreenManager` stack takes the event instead; and whenever a
  widget holds focus the widget hierarchy is offered the event before this callback
  and anything it consumes never arrives. See "Where a key is handled" in
  `Drafter.App`.

  Return `{:noreply, state}` for events the app does not claim: the event is then
  routed to the focused widget and its ancestors, unless the hierarchy was already
  offered it. `{:ok, new_state}` consumes the event and re-renders, `{:stop, reason}`
  ends the app, `{:error, reason}` discards the event, and a `t:screen_action/0`
  manipulates the screen stack. Any other term raises `FunctionClauseError` in the
  loop.

  A catch-all clause returning `{:noreply, state}` is appended automatically, so a
  module need only define the clauses it cares about.
  """
  @callback handle_event(Event.t(), state()) ::
              {:ok, state()}
              | {:error, term()}
              | {:noreply, state()}
              | {:stop, term()}
              | screen_action()

  @doc """
  Rebuilds the state when the module is re-rendered with new props.

  `props` is the new prop map, `state` the state as it stands. Returns the state to
  continue with.
  """
  @callback update(props(), state()) :: state()

  @doc """
  Runs once after the first render, before the first event.

  Returns the state to continue with. Timers started here with
  `Drafter.set_interval/2` are registered before the loop begins receiving.
  """
  @callback on_ready(state()) :: state()

  @doc """
  Runs once per firing of a registered timer.

  The first argument is the `timer_id` given to `Drafter.set_interval/2` or
  `Drafter.set_timeout/2`. Returns the new state.
  """
  @callback on_timer(atom(), state()) :: state()

  @doc """
  Handles a process message delivered to the loop that Drafter does not itself
  consume — PubSub broadcasts, `send/2` from a task, GenServer replies.

  Returns the new state.
  """
  @callback on_message(msg :: term(), state()) :: state()

  @doc """
  Runs on the first scroll event of a scroll gesture. Returns the new state.
  """
  @callback on_scroll_active(state()) :: state()

  @doc """
  Runs once a scroll gesture settles, 150 ms after its last scroll event.
  Returns the new state.
  """
  @callback on_scroll_idle(state()) :: state()

  @doc """
  Releases resources as the application stops. Returns `:ok`.
  """
  @callback unmount(state()) :: :ok

  @doc """
  The application's frame interval.

  Returns `"30fps"`-style strings, `"7.5fps"`, a positive millisecond integer, or
  `:unlimited` to render without pacing. `"30fps"` is used when the callback is not
  defined. Anything else raises `ArgumentError` when the loop starts.
  """
  @callback refresh_rate() :: pos_integer() | String.t() | :unlimited

  @optional_callbacks [
    update: 2,
    unmount: 1,
    on_ready: 1,
    on_timer: 2,
    handle_event: 3,
    on_scroll_active: 1,
    on_scroll_idle: 1,
    on_message: 2,
    refresh_rate: 0
  ]

  defmacro __using__(opts) do
    quote do
      @behaviour Drafter.App
      import Drafter.App
      @before_compile Drafter.App

      @css_path Keyword.get(unquote(opts), :css_path)
      @inline_styles Keyword.get(unquote(opts), :styles, %{})
      @mouse_hover Keyword.get(unquote(opts), :mouse_hover, true)
      @runtime_backend Keyword.get(unquote(opts), :runtime, Drafter.Runtime.Callback)
      @keybinding_hints []

      def mount(_props), do: %{}
      def render(_state), do: []
      def on_ready(state), do: state
      def unmount(_state), do: :ok
      def keybindings, do: []
      defoverridable keybindings: 0

      def __css_path__, do: @css_path
      def __inline_styles__, do: @inline_styles
      def __mouse_hover__, do: @mouse_hover
      def __runtime__, do: @runtime_backend
      def __theme__(action) when action == :get, do: Drafter.ThemeManager.get_current_theme()

      defoverridable mount: 1,
                     render: 1,
                     on_ready: 1,
                     unmount: 1
    end
  end

  @doc """
  Appends the catch-all `handle_event/2` and `on_timer/2` clauses after every clause
  the module defined, and defines `keybindings/0` when `keybinding/3` was used.
  """
  defmacro __before_compile__(env) do
    hints = Module.get_attribute(env.module, :keybinding_hints)

    keybindings =
      if hints != [] do
        quote do
          def keybindings, do: Enum.reverse(@keybinding_hints)
        end
      end

    quote do
      unquote(keybindings)

      def handle_event(_event, state), do: {:noreply, state}
      def on_timer(_timer_id, state), do: state
    end
  end

  @doc ~S"""
  Defines a `handle_event/2` clause for a key, and registers it for display in the
  footer.

  `key_spec` is either a bare key atom (`:q`, `:enter`, `:f1`) or a
  `{key, modifiers}` tuple whose modifiers are drawn from `:ctrl`, `:shift`, and
  `:alt` (`{:s, [:ctrl]}`). `hint` is the `String.t()` shown beside the key label in
  `footer/1` and returned from the module's generated `keybindings/0` as
  `{"Ctrl+S", "save"}`.

  The block is the body of the clause. The current state is bound to `state`, and
  the block must return one of the `handle_event/2` results.

      keybinding :q, "quit" do
        {:stop, :normal}
      end

      keybinding {:s, [:ctrl]}, "save" do
        {:ok, %{state | saved: true}}
      end

  A bare key atom generates a clause matching `{:key, key}` exactly, so it does not
  fire when a modifier is held; a `{key, modifiers}` spec generates a clause matching
  `{:key, key, modifiers}` with that modifier list exactly. A codepoint above ASCII
  126 arrives as `{:char, codepoint}` and needs a hand-written `handle_event/2` clause.

  ## Clause order

  The generated clause is placed where the macro call appears, in source order among
  the module's own `handle_event/2` clauses and ahead of the catch-all
  `__before_compile__/1` appends. A `keybinding/3` written after a hand-written
  catch-all `handle_event(_event, state)` is unreachable and the compiler warns.

  ## Which keys can be bound

  A `keybinding/3` clause is a `handle_event/2` clause, so it is subject to
  everything under "Where a key is handled" in `Drafter.App`. It is not a global
  hotkey and it does not pre-empt the widget hierarchy. In particular:

    * `{:q, [:ctrl]}` never fires. `Ctrl+Q` stops the loop before any callback runs.
    * No keybinding on the root application module fires while the
      `Drafter.ScreenManager` stack is non-empty. Bind the key on the screen module
      that is on top instead.
    * With a widget focused — which is the normal case, since the first focusable
      widget in the tree is focused on the initial render — the hierarchy sees the
      key first and a key it consumes never reaches the clause. `Enter` and `Space`
      are consumed by a focused `Drafter.Widget.Button`; the printable keys, `Space`
      and the editing keys are consumed by a focused `Drafter.Widget.TextInput`;
      `Tab` and `Shift+Tab` are consumed whenever the tree has two or more focusable
      widgets; the arrow keys are consumed whenever directional navigation finds a
      neighbour to move focus to.
    * With no focusable widget in the tree, nothing is reserved except `Ctrl+Q`, and
      every binding — `Tab`, `Enter`, `:" "` included — fires.

  The bindings that behave the way their footer hint implies regardless of what is
  focused are the letters, punctuation and function keys no focused widget claims —
  `:q`, `:k`, `:f1` and the like. A modifier combination is not automatically safe:
  a focused `Drafter.Widget.TextInput` claims `Ctrl+A`, `Ctrl+←` and `Ctrl+→` among
  others, and each widget's own moduledoc lists what it takes.
  """
  defmacro keybinding(key_spec, hint, do: body) do
    pattern = build_key_pattern(key_spec)
    display = build_key_hint(key_spec)

    quote do
      @keybinding_hints [{unquote(display), unquote(hint)} | @keybinding_hints]
      def handle_event(unquote(pattern), var!(state)) do
        _ = var!(state)
        unquote(body)
      end
    end
  end

  defp build_key_pattern({key, mods}) when is_list(mods) do
    quote do: {:key, unquote(key), unquote(mods)}
  end

  defp build_key_pattern(key) when is_atom(key) do
    quote do: {:key, unquote(key)}
  end

  defp build_key_hint({key, mods}) when is_list(mods) do
    mod_prefix = Enum.map_join(mods, "+", &mod_label/1)
    "#{mod_prefix}+#{key_label(key)}"
  end

  defp build_key_hint(key) when is_atom(key), do: key_label(key)

  defp mod_label(:ctrl), do: "Ctrl"
  defp mod_label(:shift), do: "Shift"
  defp mod_label(:alt), do: "Alt"
  defp mod_label(m), do: to_string(m)

  defp key_label(:escape), do: "Esc"
  defp key_label(:enter), do: "Enter"
  defp key_label(:tab), do: "Tab"
  defp key_label(:" "), do: "Space"
  defp key_label(:backspace), do: "Backspace"
  defp key_label(:delete), do: "Delete"
  defp key_label(:up), do: "↑"
  defp key_label(:down), do: "↓"
  defp key_label(:left), do: "←"
  defp key_label(:right), do: "→"
  defp key_label(:page_up), do: "PageUp"
  defp key_label(:page_down), do: "PageDown"
  defp key_label(:home), do: "Home"
  defp key_label(:end), do: "End"

  for n <- 1..12 do
    defp key_label(unquote(:"f#{n}")), do: unquote("F#{n}")
  end

  defp key_label(k), do: k |> to_string() |> String.upcase()

  @doc ~S"""
  A line of text. Returns `{:label, text, opts}`.

  `text` is a `String.t()`; embedded newlines wrap onto further rows.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Label`:

    * `:style` - `map()` of style attributes, e.g. `%{bold: true, fg: :cyan}`.
      Default `%{}`.
    * `:align` - `:left` (default), `:center`, or `:right`.
    * `:variant` - theme variant atom. Default `:default`.
    * `:class` - an atom or list of atoms matched by CSS selectors. Default `[]`;
      reaches the widget as `:classes`.

      iex> label("Ready")
      {:label, "Ready", []}

      iex> label("Count: 3", style: %{bold: true}, align: :center)
      {:label, "Count: 3", [style: %{bold: true}, align: :center]}
  """
  @spec label(String.t(), opts()) :: {:label, String.t(), opts()}
  def label(text, opts \\ []) do
    {:label, text, opts}
  end

  @doc """
  A pressable button. Returns `{:button, text, opts}`.

  `text` is the `String.t()` caption.

  A focused button consumes `Enter` and `Space`, so neither key reaches the app's
  `handle_event/2` or a `keybinding/3` clause while it holds focus. Activation
  arrives as `handle_event(on_click_atom, nil, state)` instead.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Button`:

    * `:on_click` - the atom delivered to `handle_event/3` when the button is
      activated, or a zero-arity function. Default `nil`, and no callback fires.
      Forced to `nil` when `:disabled` is `true`.
    * `:variant` - `:default` (the default), `:primary`, and the other theme
      variants. `:type` is read as a fallback when `:variant` is absent.
    * `:disabled` - `boolean()`, default `false`. A disabled button takes no
      focus and fires no callback.
    * `:compact` - `boolean()`, default `false`. Drops the button's border rows.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms matched by CSS selectors. Default `[]`.

      iex> button("Save", on_click: :save, variant: :primary)
      {:button, "Save", [on_click: :save, variant: :primary]}
  """
  @spec button(String.t(), opts()) :: {:button, String.t(), opts()}
  def button(text, opts \\ []) do
    {:button, text, opts}
  end

  @doc """
  A checkbox with a caption. Returns `{:checkbox, label, opts}`.

  `label` is the `String.t()` shown beside the box. `Drafter.get_widget_value/1`
  returns the checked `boolean()`. A focused checkbox consumes `Space`.

  Options beyond the shared element keys, all forwarded to
  `Drafter.Widget.Checkbox`:

    * `:checked` - `boolean()` initial state. Default `false`.
    * `:bind` - app-state key atom for two-way binding of the checked state.
      Default `nil`. Only with a `:bind` does a later `:checked` change reach the
      mounted widget.
    * `:on_change` - atom event name or one-arity function called with the new
      `boolean()`. Default `nil`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

      iex> checkbox("Enable logging", checked: true, on_change: :toggle_logging)
      {:checkbox, "Enable logging", [checked: true, on_change: :toggle_logging]}
  """
  @spec checkbox(String.t(), opts()) :: {:checkbox, String.t(), opts()}
  def checkbox(label, opts \\ []) do
    {:checkbox, label, opts}
  end

  @doc """
  A single-line text field. Returns `{:text_input, opts}`.

  `Drafter.get_widget_value/1` returns the current text as a `String.t()`.
  `Drafter.Widget.TextInput` documents every option and every key it binds; the
  frequently used ones are `:value` (default `""`), `:placeholder` (default `""`),
  `:on_change`, `:on_submit`, `:disabled` (default `false`), `:readonly` (default
  `false`), `:password` (default `false`), and `:type` (`:text` by default).

  `:max_length` and `:width` are read by the widget's `mount/1` only — this element
  does not forward them, so setting either here has no effect.

  While this widget has focus it consumes every printable key, `Space`, `←`, `→`,
  `Home`, `End`, `Backspace` and `Ctrl+A`, so none of those reach `handle_event/2` or
  a `keybinding/3` clause. `↑`, `↓`, `Escape`, `PageUp` and `PageDown` pass through,
  and so does `Enter` unless `:on_submit` is set.

      iex> text_input(id: :name, placeholder: "Your name")
      {:text_input, [id: :name, placeholder: "Your name"]}
  """
  @spec text_input(opts()) :: {:text_input, opts()}
  def text_input(opts \\ []) do
    {:text_input, opts}
  end

  @doc """
  A multi-line text editor. Returns `{:text_area, opts}`.

  `Drafter.get_widget_value/1` returns the current text as a `String.t()`.
  `Drafter.Widget.TextArea` documents every option; the frequently used ones are
  `:value` (default `""`), `:show_line_numbers` (default `false`), `:read_only`
  (default `false`), `:language` (default `nil`), `:trap_focus` (default `false`),
  `:tab_behavior` (`:focus` by default), and `:tab_size` (default `2`).

  `:placeholder_style`, `:focused_style`, `:selection_style`, `:line_number_style`
  and `:max_checkpoints` are read by the widget's `mount/1` only — this element does
  not forward them.

  `:width` and `:height` are taken from the rect the parent allocated rather than
  from the widget's own defaults. With `trap_focus: true` the editor receives `Tab`
  itself instead of `Tab` moving focus.

      iex> text_area(id: :body, show_line_numbers: true, language: :elixir)
      {:text_area, [id: :body, show_line_numbers: true, language: :elixir]}
  """
  @spec text_area(opts()) :: {:text_area, opts()}
  def text_area(opts \\ []) do
    {:text_area, opts}
  end

  @doc """
  A scrollable table with selectable rows. Returns `{:data_table, opts}`.

  Options are the widget's props; `Drafter.Widget.DataTable` documents all of them.
  There is no positional argument: columns go in `:columns` and rows in `:data`,
  **not** `:rows`. `:width` and `:height` default to the rect the parent allocated.
  `Drafter.get_widget_value/1` returns the list of selected row indices.

  A focused data table consumes `↑`, `↓`, `PageUp`, `PageDown`, `Home`, `End`,
  `Enter` and `Space`, so none of those reach a `keybinding/3` clause.

      iex> data_table(id: :rows, columns: [{:name, "Name"}], data: [%{name: "a"}])
      {:data_table, [id: :rows, columns: [{:name, "Name"}], data: [%{name: "a"}]]}
  """
  @spec data_table(opts()) :: {:data_table, opts()}
  def data_table(opts \\ []) do
    {:data_table, opts}
  end

  @doc """
  An expandable tree of nodes. Returns `{:tree, opts}`.

  Options are the widget's props; see `Drafter.Widget.Tree`, whose "Key bindings"
  section lists what a focused tree acts on — the arrow keys, `Enter`, `Space`, `+`,
  `-`, `*` and `/` among them. A key it acts on does not reach `handle_event/2` or a
  `keybinding/3` clause; one that leaves the tree unchanged, such as `←` on an
  already-collapsed node, falls through. `Drafter.get_widget_value/1` returns the
  list of selected node ids.

      iex> tree(id: :files, nodes: [])
      {:tree, [id: :files, nodes: []]}
  """
  @spec tree(opts()) :: {:tree, opts()}
  def tree(opts \\ []) do
    {:tree, opts}
  end

  @doc """
  A horizontal progress bar. Returns `{:progress_bar, opts}`.

  Options are the widget's props; see `Drafter.Widget.ProgressBar`. Not focusable,
  so it reserves no keys. `:width` and `:height` fall back to the rect the parent
  allocated.

      iex> progress_bar(value: 0.4)
      {:progress_bar, [value: 0.4]}
  """
  @spec progress_bar(opts()) :: {:progress_bar, opts()}
  def progress_bar(opts \\ []) do
    {:progress_bar, opts}
  end

  @doc """
  A dial-style gauge. Returns `{:gauge, opts}`.

  Options are the widget's props; see `Drafter.Widget.Gauge`.

      iex> gauge(value: 72, max: 100)
      {:gauge, [value: 72, max: 100]}
  """
  @spec gauge(opts()) :: {:gauge, opts()}
  def gauge(opts \\ []) do
    {:gauge, opts}
  end

  @doc """
  An on/off switch. Returns `{:switch, opts}`.

  `Drafter.get_widget_value/1` returns a `boolean()`. A focused switch acts on
  `Enter` and `Space` to toggle and on `←`/`→` to force off/on; a key that leaves the
  state as it was falls through to `handle_event/2`.

  Options beyond the shared element keys, forwarded to `Drafter.Widget.Switch`:

    * `:enabled` - `boolean()` initial state. Default `false`. **This is the key
      the widget reads**, not `:value`.
    * `:bind` - app-state key atom for two-way binding. Default `nil`. Only with a
      `:bind` does a later `:enabled` change reach the mounted widget.
    * `:label` - `String.t()` shown to the right of the track. Default `nil`.
    * `:on_change` - atom event name or one-arity function receiving the new
      `boolean()`. Default `nil`.
    * `:size` - `:normal` (default), `:small`, or `:compact`.
    * `:width` / `:height` - column and row counts. Default: the width and height of
      the rect the parent allocated.

  `:on_color` and `:off_color` are read by the widget's `mount/1` only and are not
  forwarded by this element.

      iex> switch(enabled: true, label: "Dark mode", on_change: :toggle_theme)
      {:switch, [enabled: true, label: "Dark mode", on_change: :toggle_theme]}
  """
  @spec switch(opts()) :: {:switch, opts()}
  def switch(opts \\ []) do
    {:switch, opts}
  end

  @doc """
  A draggable value slider. Returns `{:slider, opts}`.

  `Drafter.get_widget_value/1` returns the `number()` it sits at. A focused slider
  moves on `←`/`↓` and `→`/`↑`, ten steps on `PageUp`/`PageDown`, and to the ends of
  the range on `Home`/`End`; a press or drag anywhere on the track moves the thumb
  there.

  Options beyond the shared element keys, forwarded to `Drafter.Widget.Slider`:

    * `:value` - `number()` to start at, clamped and snapped. Default: `:min`.
    * `:min` / `:max` - ends of the range. Default `0.0` and `1.0`.
    * `:step` - `number()` the value moves in. Default `nil`, a hundredth of the
      range, or whole numbers when `:min` and `:max` are both integers.
    * `:bind` - app-state key atom for two-way binding. Default `nil`. Only with a
      `:bind` does a later `:value` change reach the mounted widget.
    * `:label` - `String.t()` drawn ahead of the track. Default `nil`.
    * `:show_value` - draw the readout after the track. Default `true`.
    * `:format` - `(number() -> String.t())` for the readout. Default `nil`.
    * `:precision` - decimals in the readout. Default: as many as `:step` needs.
    * `:orientation` - `:horizontal` (default) or `:vertical`.
    * `:disabled` - `boolean()`. Default `false`.
    * `:on_change` - atom event name or one-arity function receiving the new number.
    * `:track_color` / `:fill_color` / `:thumb_color` - `{r, g, b}` overrides.
    * `:renderer` - `:text` (default), `:braille`, or a graphics protocol atom, which
      draws the track through `french_curve`.

      iex> slider(value: 0.5, label: "Gain", on_change: :set_gain)
      {:slider, [value: 0.5, label: "Gain", on_change: :set_gain]}
  """
  @spec slider(opts()) :: {:slider, opts()}
  def slider(opts \\ []) do
    {:slider, opts}
  end

  @doc """
  Returns `{:slider, [{:value, value} | opts]}`.

      iex> slider(0.25, label: "Mix")
      {:slider, [value: 0.25, label: "Mix"]}
  """
  @spec slider(number(), opts()) :: {:slider, opts()}
  def slider(value, opts) when is_number(value) and is_list(opts) do
    {:slider, Keyword.put(opts, :value, value)}
  end

  @doc """
  Returns `{:switch, [{:value, value} | opts]}`.

  `value` is stored under `:value`, which `Drafter.Widget.Switch` does not read — the
  widget's on/off state comes from `:enabled`. Use this form only for
  `switch_group/2`, which reads `:value` itself to build each switch's callback
  payload; use `switch/1` with `enabled:` to set the state of a standalone switch.

      iex> switch("compact", label: "Compact")
      {:switch, [value: "compact", label: "Compact"]}
  """
  @spec switch(term(), opts()) :: {:switch, opts()}
  def switch(value, opts) when is_list(opts) do
    {:switch, Keyword.put(opts, :value, value)}
  end

  @doc """
  A two-column block of switches that all report to one callback.

  `group_name` is any term; `switches` is a list of keyword lists, each the options
  for one `switch/1`. Each switch's `:on_change` is **overwritten** with
  `{:switch_group_changed, group_name, value}`, where `value` is that switch's
  `:value` option or, absent that, its `:label`. Its `:label` is re-set from its own
  `:label`, and every other option is passed through.

  That tuple reaches the module as `handle_event({:switch_group_changed, group_name,
  value}, enabled?, state)` — `handle_event/3` with a tuple rather than an atom as its
  first argument, and the switch's new `boolean()` as `data`.

  Returns the `horizontal/2` element holding two `vertical/2` columns of `width: 30`
  with `gap: 2` between them. The first `div(length(switches) + 1, 2)` entries fill
  the left column, so an odd count puts the extra switch on the left.

      iex> switch_group(:sizes, [[label: "Small", value: :s], [label: "Large"]])
      {:layout, :horizontal,
       [
         {:layout, :vertical,
          [{:switch, [value: :s, label: "Small",
             on_change: {:switch_group_changed, :sizes, :s}]}], [width: 30]},
         {:layout, :vertical,
          [{:switch, [label: "Large",
             on_change: {:switch_group_changed, :sizes, "Large"}]}], [width: 30]}
       ], [layout: :horizontal, gap: 2]}
  """
  @spec switch_group(term(), [opts()]) :: {:layout, :horizontal, [element()], opts()}
  def switch_group(group_name, switches) when is_list(switches) do
    {left_col, right_col} = Enum.split(switches, div(length(switches) + 1, 2))

    left_switches =
      Enum.map(left_col, fn opts ->
        label = Keyword.get(opts, :label)
        value = Keyword.get(opts, :value, label)

        switch(
          Keyword.merge(opts,
            label: label,
            on_change: {:switch_group_changed, group_name, value}
          )
        )
      end)

    right_switches =
      Enum.map(right_col, fn opts ->
        label = Keyword.get(opts, :label)
        value = Keyword.get(opts, :value, label)

        switch(
          Keyword.merge(opts,
            label: label,
            on_change: {:switch_group_changed, group_name, value}
          )
        )
      end)

    horizontal(
      [
        vertical(left_switches, width: 30),
        vertical(right_switches, width: 30)
      ],
      gap: 2
    )
  end

  @doc """
  A list of the installed themes that switches theme on selection.

  Returns `{:theme_selector, opts}`. **Every option is accepted and ignored**,
  including `:id` and `:key`: the widget is a `Drafter.Widget.OptionList` built from
  `Drafter.ThemeManager`'s registered themes, its id is always `:theme_selector_<n>`
  from its position in the tree, and it takes focus the first time it renders.
  Highlighting or selecting an entry applies that theme immediately.

      iex> theme_selector()
      {:theme_selector, []}
  """
  @spec theme_selector(opts()) :: {:theme_selector, opts()}
  def theme_selector(opts \\ []) do
    {:theme_selector, opts}
  end

  @doc """
  A single-selection list. Returns `{:option_list, items, opts}`.

  `items` is the list of options; see `Drafter.Widget.OptionList` for their shape
  and for the widget's options. `Drafter.get_widget_value/1` returns the selected
  option's id.

  A focused option list consumes `↓`, `Home`, `End`, `PageUp`, `PageDown`, `Enter`
  and `Space`, and `↑` except on the first entry, where it bubbles so focus can
  leave upwards.

      iex> option_list([%{id: :a, label: "Alpha"}], on_select: :chose)
      {:option_list, [%{id: :a, label: "Alpha"}], [on_select: :chose]}
  """
  @spec option_list([term()], opts()) :: {:option_list, [term()], opts()}
  def option_list(items, opts \\ []) do
    {:option_list, items, opts}
  end

  @doc """
  Lays `children` out left to right. Returns `{:layout, :horizontal, children, opts}`
  with `layout: :horizontal` added to `opts`.

  `children` is a list of elements.

  Options beyond the shared element keys:

    * `:gap` - `non_neg_integer()` columns between children. Default `0`.
    * `:padding` - space inside the container, in the same shapes as `:margin`.
      Default `nil`, i.e. none.
    * `:layout` - overwritten with `:horizontal`; passing it has no effect.

  Each child's own `:width` and `:flex` options decide how the row is divided. When
  no child carries either, the width is split evenly.

      iex> horizontal([button("No", on_click: :no)], gap: 2)
      {:layout, :horizontal, [{:button, "No", [on_click: :no]}],
       [layout: :horizontal, gap: 2]}
  """
  @spec horizontal([element()], opts()) :: {:layout, :horizontal, [element()], opts()}
  def horizontal(children, opts \\ []) do
    opts = Keyword.put(opts, :layout, :horizontal)
    container(children, opts)
  end

  @doc """
  A fixed-width column beside a column that takes the rest of the width.

  `left_children` and `right_children` are lists of elements. `opts` is passed on to
  the enclosing `horizontal/2` unchanged — including `:sidebar_width` itself, which
  the layout ignores — and is additionally read for:

    * `:sidebar_width` - `pos_integer()` columns for the left column. Default `20`.

  The left column becomes `vertical(left_children, width: sidebar_width)` and the
  right `vertical(right_children, flex: 1)`. Neither column receives any of `opts`.

      iex> sidebar([label("nav")], [label("body")], sidebar_width: 12)
      {:layout, :horizontal,
       [
         {:layout, :vertical, [{:label, "nav", []}], [width: 12]},
         {:layout, :vertical, [{:label, "body", []}], [flex: 1]}
       ], [layout: :horizontal, sidebar_width: 12]}
  """
  @spec sidebar([element()], [element()], opts()) ::
          {:layout, :horizontal, [element()], opts()}
  def sidebar(left_children, right_children, opts \\ []) do
    sidebar_width = Keyword.get(opts, :sidebar_width, 20)

    horizontal(
      [
        vertical(left_children, width: sidebar_width),
        vertical(right_children, flex: 1)
      ],
      opts
    )
  end

  @doc """
  A layout container whose direction comes from its options.

  Returns `{:layout, direction, children, opts}` where `direction` is the `:layout`
  option, default `:vertical`. Otherwise identical to `vertical/2` and
  `horizontal/2`, which are the direct forms.

    * `:layout` - `:vertical` (default) or `:horizontal`. Any other value is copied
      into the tuple unchanged and raises `FunctionClauseError` when the tree is
      rendered — the renderer has no clause for a third direction.

      iex> container([label("a")], layout: :horizontal)
      {:layout, :horizontal, [{:label, "a", []}], [layout: :horizontal]}

      iex> container([label("a")])
      {:layout, :vertical, [{:label, "a", []}], []}
  """
  @spec container([element()], opts()) :: {:layout, direction(), [element()], opts()}
  def container(children, opts \\ []) do
    layout = Keyword.get(opts, :layout, :vertical)
    {:layout, layout, children, opts}
  end

  @doc """
  Stacks `children` top to bottom. Returns `{:layout, :vertical, children, opts}`.

  `children` is a list of elements. `opts` is stored verbatim; unlike `horizontal/2`
  no `:layout` key is added.

  Options beyond the shared element keys:

    * `:gap` - `non_neg_integer()` rows between children. Default `0`.
    * `:padding` - space inside the container, in the same shapes as `:margin`.
      Default `nil`, i.e. none.
    * `:width` - the column width given to every child. Default `nil`, which uses
      the container's own width.

  Each child's `:height` and `:flex` divide the column.

      iex> vertical([header("Title"), footer()])
      {:layout, :vertical, [{:header, "Title", []}, {:footer, []}], []}
  """
  @spec vertical([element()], opts()) :: {:layout, :vertical, [element()], opts()}
  def vertical(children, opts \\ []) do
    {:layout, :vertical, children, opts}
  end

  @doc """
  A bordered container. Returns `{:box, children, opts}`.

  `children` is a list of child elements, laid out inside the rect left after the
  border and padding are subtracted.

  Options beyond the shared element keys — these four are the only ones this element
  forwards to `Drafter.Widget.Box`:

    * `:title` - `String.t()` embedded in the top border. Default `nil`.
    * `:border` - `:none`, `:single`, `:double`, `:rounded`, `:heavy`, `:dashed`, or
      `:ascii`. Default: the current character set's border style, falling back to
      `:rounded`. `:none` still costs no rows.
    * `:padding` - `non_neg_integer()` cells inside the border. Default: the
      character set's padding, falling back to `1` — not `0`.
    * `:style` - `map()` of style attributes for the box as a whole. Default `%{}`.

  `:border_style`, `:title_style`, `:content_style` and `:classes` are documented on
  `Drafter.Widget.Box` because its `mount/1` reads them, but this element does not
  forward them and passing them here does nothing.

      iex> box([label("Ready")], title: "Status", border: :double)
      {:box, [{:label, "Ready", []}], [title: "Status", border: :double]}
  """
  @spec box([element()], opts()) :: {:box, [element()], opts()}
  def box(children, opts \\ []) do
    {:box, children, opts}
  end

  @doc """
  A titled panel. Returns `{:card, children, opts}`.

  `children` must be a list of **strings**, one per content row. Each entry is run
  through `to_string/1`, so passing element tuples — the natural reading of
  "children" and what `box/2` and `vertical/2` take — raises
  `Protocol.UndefinedError` for `String.Chars` when the tree renders. A card is a
  text panel, not a layout container.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Card`:

    * `:title` - `String.t()` in the top border. Default `nil`.
    * `:border` - border style atom. Default: the current character set's border
      style, falling back to `:rounded`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:border_color` - border colour. Default `nil`.
    * `:background` - panel background colour. Default `nil`.
    * `:color` - content foreground colour. Default `nil`.
    * `:class` - an atom or list of atoms. Default `[]`; reaches the widget as
      `:classes`.

      iex> card(["3 files changed"], title: "Summary")
      {:card, ["3 files changed"], [title: "Summary"]}
  """
  @spec card([String.t()], opts()) :: {:card, [String.t()], opts()}
  def card(children, opts \\ []) do
    {:card, children, opts}
  end

  @doc """
  Large seven-segment style digits. Returns `{:digits, value, opts}`.

  `value` is the text to draw; it is run through `to_string/1`, so an integer or
  float works as well as a `String.t()`.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Digits`:

    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:align` - `:left` (default), `:center`, or `:right`.
    * `:size` - `:large` (default) and the other sizes the widget lists.
    * `:font` - glyph set name. Default `nil`, i.e. the built-in font.
    * `:renderer` - `:text` (default) or the image renderers.
    * `:color` - `{r, g, b}` for the lit segments. Default `{0, 150, 255}`.
    * `:bg_data`, `:bg_min`, `:bg_max` - background sparkline data and its range.
      Defaults `nil`, `0`, and `nil`.

      iex> digits("12:04", align: :center)
      {:digits, "12:04", [align: :center]}
  """
  @spec digits(term(), opts()) :: {:digits, term(), opts()}
  def digits(value, opts \\ []) do
    {:digits, value, opts}
  end

  @doc """
  Rendered Markdown. Returns `{:markdown, content, opts}`.

  `content` is the Markdown source as a `String.t()`, or `nil` to take the `:content`
  option instead.

  Options beyond the shared element keys, all forwarded to
  `Drafter.Widget.Markdown`:

    * `:content` - fallback source, used when `content` is `nil`. Default `""`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:padding` - `non_neg_integer()` cells of inset. Default `1`.

  Only `:content` reaches an already-mounted widget, so changing `:style` or
  `:padding` on a re-render has no effect. Not focusable, so it reserves no keys.

      iex> markdown("# Title", padding: 0)
      {:markdown, "# Title", [padding: 0]}
  """
  @spec markdown(String.t() | nil, opts()) :: {:markdown, String.t() | nil, opts()}
  def markdown(content, opts \\ []) do
    {:markdown, content, opts}
  end

  @doc """
  A divider line. Returns `{:rule, opts}`.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Rule`:

    * `:orientation` - `:horizontal` (default) or `:vertical`.
    * `:title` - `String.t()` set into the line. Default `nil`.
    * `:title_align` - `:center` (default), `:left`, or `:right`.
    * `:line_style` - `:solid` (default) and the other styles the widget lists.
    * `:style` - `map()` of style attributes. Default `%{}`.

  Every option is live-updatable through the component tree.

      iex> rule(title: "Details")
      {:rule, [title: "Details"]}
  """
  @spec rule(opts()) :: {:rule, opts()}
  def rule(opts \\ []) do
    {:rule, opts}
  end

  @doc """
  A labelled block that fills its space, for laying out a screen before its content
  exists. Returns `{:placeholder, opts}`.

  Options beyond the shared element keys, all forwarded to
  `Drafter.Widget.Placeholder`:

    * `:label` - the caption. Default: the `:text` option, itself defaulting to
      `"Placeholder"`.
    * `:text` - fallback caption when `:label` is absent. Default `"Placeholder"`.
    * `:padding` - `non_neg_integer()` cells of inset. Default `2`.
    * `:align` - `:center` (default), `:left`, or `:right`.
    * `:border` - `boolean()`. Default `false`.
    * `:style` - `map()` of style attributes. Default `%{}`.

  Only the caption reaches an already-mounted widget; `:padding`, `:align`,
  `:border` and `:style` are read at mount time.

      iex> placeholder(label: "Chart goes here", border: true)
      {:placeholder, [label: "Chart goes here", border: true]}
  """
  @spec placeholder(opts()) :: {:placeholder, opts()}
  def placeholder(opts \\ []) do
    {:placeholder, opts}
  end

  @doc """
  Pre-rendered content that is drawn as given. Returns `{:static, content, opts}`.

  `content` is the text to draw. It becomes a `Drafter.Widget.Label` whose style is
  the theme's foreground and background merged with `:style`.

    * `:style` - `map()` of style attributes merged over the theme's. Default `%{}`.

  Every other option is ignored, **including `:id` and `:key`**: a static element's
  widget id is always `:static_<n>` from its position in the tree, so it cannot be
  reached by `Drafter.get_widget_value/1` or `Drafter.focus/1` under a name you
  chose. Use `label/2` when you need an id.

      iex> static("v1.4.0", style: %{dim: true})
      {:static, "v1.4.0", [style: %{dim: true}]}
  """
  @spec static(term(), opts()) :: {:static, term(), opts()}
  def static(content, opts \\ []) do
    {:static, content, opts}
  end

  @doc """
  An animated spinner. Returns `{:loading_indicator, opts}`.

  Options beyond the shared element keys, all forwarded to
  `Drafter.Widget.LoadingIndicator`:

    * `:text` - caption beside the spinner. Default `"Loading..."`.
    * `:spinner_type` - `:default` (default), `:dots`, `:line`, or `:points`.
    * `:running` - `boolean()`. Default `true`.
    * `:gradient_colors` - list of `{r, g, b}` cycled through the caption.
      Default `nil`, i.e. a plain caption.
    * `:gradient_speed` - milliseconds per gradient step. Default `50`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

  A re-render only refreshes the animation timestamp, so changing any of these
  options after the first mount has no effect.

      iex> loading_indicator(text: "Fetching…", spinner_type: :line)
      {:loading_indicator, [text: "Fetching…", spinner_type: :line]}
  """
  @spec loading_indicator(opts()) :: {:loading_indicator, opts()}
  def loading_indicator(opts \\ []) do
    {:loading_indicator, opts}
  end

  @doc """
  A single-row trend line. Returns `{:sparkline, data, opts}`.

  `data` is a list of numbers. A keyword list, or an empty list, is treated as
  absent and the `:data` option is used instead.

  Options beyond the shared element keys, all forwarded to
  `Drafter.Widget.Sparkline`:

    * `:data` - fallback series. Default `[]`.
    * `:min_value` / `:max_value` - fix the vertical range. Defaults `nil`, i.e.
      taken from the data.
    * `:color` - `{r, g, b}` for the whole line. Default `nil`.
    * `:min_color` / `:max_color` - endpoints of a value-based gradient.
      Defaults `nil`.
    * `:summary` - `boolean()`, appends min/max/last. Default `false`.
    * `:orientation` - `:vertical` (default) or `:horizontal`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

      iex> sparkline([1, 4, 2, 8], summary: true)
      {:sparkline, [1, 4, 2, 8], [summary: true]}
  """
  @spec sparkline([number()], opts()) :: {:sparkline, [number()], opts()}
  def sparkline(data, opts \\ []) do
    {:sparkline, data, opts}
  end

  @doc """
  A line, bar, or area chart. Returns `{:chart, data, opts}`.

  `data` is the series to plot; any non-list is treated as absent and the `:data`
  option is used instead. See `Drafter.Widget.Chart` for the accepted series shapes
  and the full option list. The chart kind is `:chart_type` (default `:line`), not
  `:type`. `:width` and `:height` default to the rect the parent allocated.

      iex> chart([1, 2, 3], chart_type: :bar)
      {:chart, [1, 2, 3], [chart_type: :bar]}
  """
  @spec chart(term(), opts()) :: {:chart, term(), opts()}
  def chart(data, opts \\ []) do
    {:chart, data, opts}
  end

  @doc """
  A pie chart. Returns `{:pie_chart, data, opts}`.

  `data` is the list of slices, each `{label, value}` or `{label, value, {r, g, b}}`.
  An empty list or a keyword list is treated as absent and the `:data` option is used
  instead. See `Drafter.Widget.PieChart` for the rest of its options; the ones with
  non-obvious defaults are `:show_legend` (`true`), `:show_percentages` (`true`), and
  `:renderer` (`:text`).

      iex> pie_chart([{"Elixir", 3}, {"Erlang", 1}], show_legend: false)
      {:pie_chart, [{"Elixir", 3}, {"Erlang", 1}], [show_legend: false]}
  """
  @spec pie_chart(term(), opts()) :: {:pie_chart, term(), opts()}
  def pie_chart(data, opts \\ []) do
    {:pie_chart, data, opts}
  end

  @doc """
  A month calendar. Returns `{:calendar, opts}`.

  See `Drafter.Widget.Calendar` for its options; the positional argument the widget
  would take is not used by this element, so everything comes from `opts`. A focused
  calendar consumes the four arrow keys, `Enter` and `Space`.

      iex> calendar(id: :when)
      {:calendar, [id: :when]}
  """
  @spec calendar(opts()) :: {:calendar, opts()}
  def calendar(opts \\ []) do
    {:calendar, opts}
  end

  @doc """
  A path trail. Returns `{:breadcrumb, items, opts}`.

  `items` is a list of crumbs, each either a `String.t()` used as both label and id
  or a `{label, id}` tuple.

  Options beyond the shared element keys, all forwarded to
  `Drafter.Widget.Breadcrumb`:

    * `:separator` - `String.t()` between crumbs. Default `" › "`.
    * `:on_click` - atom event name or one-arity function receiving the crumb's id.
      Default `nil`.
    * `:active` - `boolean()`, whether crumbs respond to clicks. Default `true`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

  A focused breadcrumb consumes `←`, `→`, `Enter` and `Space`.

      iex> breadcrumb(["home", {"Reports", :reports}], on_click: :navigate)
      {:breadcrumb, ["home", {"Reports", :reports}], [on_click: :navigate]}
  """
  @spec breadcrumb([String.t() | {String.t(), term()}], opts()) ::
          {:breadcrumb, [term()], opts()}
  def breadcrumb(items, opts \\ []) do
    {:breadcrumb, items, opts}
  end

  @doc """
  A labelled value bar. Returns `{:meter, opts}`.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Meter`:

    * `:value` - the reading, `0.0`..`1.0`. Default `0.0`.
    * `:label` - `String.t()` caption. Default `nil`.
    * `:orientation` - `:horizontal` (default) or `:vertical`.
    * `:thresholds` - the widget's colour bands. Default: its own threshold list.
    * `:show_value` - `boolean()`. Default `true`.
    * `:show_label` - `boolean()`. Default `true`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

  `:style`, `:class` and the app module are read at mount time only; the rest are
  live-updatable. `:height` is ignored for a horizontal meter.

      iex> meter(value: 0.82, label: "CPU")
      {:meter, [value: 0.82, label: "CPU"]}
  """
  @spec meter(opts()) :: {:meter, opts()}
  def meter(opts \\ []) do
    {:meter, opts}
  end

  @doc """
  A clickable hyperlink. Returns `{:link, text, opts}`.

  `text` is the caption, or `nil` to take the `:text` option instead. The second
  argument is either the URL as a `String.t()`, which is wrapped into `[url: url]`
  and discards every other option, or a keyword list. Anything else — an atom, a
  map, an integer — raises `FunctionClauseError`.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Link`:

    * `:url` - the address opened when the link is activated. Default `nil`, and
      activating it does nothing.
    * `:text` - fallback caption, used when `text` is `nil`. Default `nil`.
    * `:tooltip` - `String.t()` shown on hover. Default `nil`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

  A focused link consumes `Enter`, which shells out to `open`, `xdg-open`, or
  `start` for the platform.

      iex> link("Docs", "https://hexdocs.pm/drafter")
      {:link, "Docs", [url: "https://hexdocs.pm/drafter"]}

      iex> link("Docs", url: "https://hexdocs.pm/drafter", tooltip: "Hex")
      {:link, "Docs", [url: "https://hexdocs.pm/drafter", tooltip: "Hex"]}
  """
  @spec link(String.t() | nil, String.t() | opts()) :: {:link, String.t() | nil, opts()}
  def link(text, opts \\ [])

  def link(text, url) when is_binary(url) do
    {:link, text, [url: url]}
  end

  def link(text, opts) when is_list(opts) do
    {:link, text, opts}
  end

  @doc """
  A text field that renders its content as mask characters.

  Returns `{:masked_input, opts}`. `opts` is required and must be a keyword list —
  there is no zero-arity form, so `masked_input()` is an `UndefinedFunctionError`
  and any non-list argument a `FunctionClauseError`. See `Drafter.Widget.MaskedInput`
  for its options.

  A focused masked input consumes `←`, `→` and `Enter`.

      iex> masked_input(id: :pin, mask: "****-****")
      {:masked_input, [id: :pin, mask: "****-****"]}
  """
  @spec masked_input(opts()) :: {:masked_input, opts()}
  def masked_input(opts) when is_list(opts) do
    {:masked_input, opts}
  end

  @doc """
  A scrolling line log. Returns `{:log, opts}`.

  See `Drafter.Widget.Log` for its options. Lines are appended with
  `Drafter.push_data/2` when the element carries both `:buffer` and `:refresh`;
  those two keys are lifted out of `opts` and used to open the widget's data
  channel, and `:image_throttle` is lifted the same way.

  Not focusable, so it reserves no keys.

      iex> log(id: :output, max_lines: 500)
      {:log, [id: :output, max_lines: 500]}
  """
  @spec log(opts()) :: {:log, opts()}
  def log(opts \\ []) do
    {:log, opts}
  end

  @doc """
  A scrolling log that keeps per-line styling. Returns `{:rich_log, opts}`.

  See `Drafter.Widget.RichLog` for its options. As with `log/1`, `:buffer`,
  `:refresh` and `:image_throttle` open a `Drafter.push_data/2` channel. Not
  focusable, so it reserves no keys.

      iex> rich_log(id: :events)
      {:rich_log, [id: :events]}
  """
  @spec rich_log(opts()) :: {:rich_log, opts()}
  def rich_log(opts \\ []) do
    {:rich_log, opts}
  end

  @doc """
  An inspected Elixir term, formatted and syntax-coloured.

  Returns `{:pretty, data, opts}`. `data` is any term.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Pretty`:

    * `:expand` - `boolean()`, print one field per line. Default `false`.
    * `:syntax_highlighting` - `boolean()`. Default `true`.
    * `:style` - `map()` of style attributes. Default `%{}`.
    * `:class` - an atom or list of atoms. Default `[]`.

  Only `:data` reaches an already-mounted widget, so changing any of the others on a
  re-render has no effect. Not focusable, so it reserves no keys.

      iex> pretty(%{status: :ok}, expand: true)
      {:pretty, %{status: :ok}, [expand: true]}
  """
  @spec pretty(term(), opts()) :: {:pretty, term(), opts()}
  def pretty(data, opts \\ []) do
    {:pretty, data, opts}
  end

  @doc """
  A browsable filesystem tree. Returns `{:directory_tree, opts}`.

  See `Drafter.Widget.DirectoryTree` for its `:path` and other options. A focused
  directory tree consumes the arrow keys, `Enter`, `Space`, `Escape`, `Home`, `End`,
  `PageUp`, `PageDown`, `Backspace` and the printable keys it uses to type-to-find,
  so almost nothing reaches a `keybinding/3` clause while it has focus.

      iex> directory_tree(id: :files, path: "/tmp")
      {:directory_tree, [id: :files, path: "/tmp"]}
  """
  @spec directory_tree(opts()) :: {:directory_tree, opts()}
  def directory_tree(opts \\ []) do
    {:directory_tree, opts}
  end

  @doc """
  A group of mutually exclusive radio buttons. Returns `{:radio_set, options, opts}`.

  `options` is the list of choices; see `Drafter.Widget.RadioSet` for their shape and
  for the widget's options. `Drafter.get_widget_value/1` returns the selected
  option's id. A `:width` given here is ignored: the set is drawn to the rect the
  parent allocated.

  A focused radio set consumes `↑`, `↓`, `Enter` and `Space` — except `↑` on the
  first entry, which bubbles so focus can leave upwards.

      iex> radio_set([%{id: :a, label: "A"}], on_change: :picked)
      {:radio_set, [%{id: :a, label: "A"}], [on_change: :picked]}
  """
  @spec radio_set([term()], opts()) :: {:radio_set, [term()], opts()}
  def radio_set(options, opts \\ []) do
    {:radio_set, options, opts}
  end

  @doc """
  A list whose entries can be checked. Returns `{:selection_list, options, opts}`.

  `options` is the list of choices; see `Drafter.Widget.SelectionList` for their
  shape and the widget's options. `Drafter.get_widget_value/1` returns the list of
  selected option ids. A focused selection list consumes `↑`, `↓`, `Home`, `End`,
  `Enter` and `Space`.

      iex> selection_list([%{id: :a, label: "A"}], on_change: :selected)
      {:selection_list, [%{id: :a, label: "A"}], [on_change: :selected]}
  """
  @spec selection_list([term()], opts()) :: {:selection_list, [term()], opts()}
  def selection_list(options, opts \\ []) do
    {:selection_list, options, opts}
  end

  @doc """
  A titled section that folds away. Returns `{:collapsible, title, content, opts}`.

  `title` is the `String.t()` on the header row; `content` is the list of elements
  shown while expanded. `Drafter.get_widget_value/1` returns the expanded
  `boolean()`, and a focused collapsible consumes `Enter` and `Space`.

  Options beyond the shared element keys — these three are the only ones this
  element forwards to `Drafter.Widget.Collapsible`:

    * `:expanded` - `boolean()` initial state. Default `false`.
    * `:on_toggle` - atom event name or one-arity function receiving the new
      `boolean()`. Default `nil`.
    * `:content_height` - `pos_integer()` rows reserved for the expanded content.
      Default `nil`, i.e. the content's own preferred height.

  Its widget id is not positional: absent an `:id` or `:key`, the generated id is
  derived from a hash of `title`, so two collapsibles with the same title in one
  tree collide.

      iex> collapsible("Advanced", [label("Verbose")], expanded: true)
      {:collapsible, "Advanced", [{:label, "Verbose", []}], [expanded: true]}
  """
  @spec collapsible(String.t(), [element()], opts()) ::
          {:collapsible, String.t(), [element()], opts()}
  def collapsible(title, content, opts \\ []) do
    {:collapsible, title, content, opts}
  end

  @doc """
  A tab bar over switchable panes. Returns `{:tabbed_content, tabs, opts}`.

  `tabs` is the list of tabs — a string label, a `{label, content}` tuple, or a map
  with `:id`, `:label` and `:content`. `Drafter.get_widget_value/1` returns the
  active tab index. See `Drafter.Widget.TabbedContent` for the widget's options;
  the non-obvious defaults are `:active_tab` (`0`), `:title_align` (`:left`), and
  `:width` (the available rect width).

  `:on_item_select` is read by the widget's `mount/1` only and is not forwarded by
  this element.

  A focused tabbed content consumes `→`, `↑`, `↓` and `Enter`, and `←` except on the
  first tab, where it falls through. It explicitly declines `Tab` so focus can still
  move on.

      iex> tabbed_content([%{id: :a, label: "A", content: ["x"]}], on_tab_change: :tab)
      {:tabbed_content, [%{id: :a, label: "A", content: ["x"]}], [on_tab_change: :tab]}
  """
  @spec tabbed_content([term()], opts()) :: {:tabbed_content, [term()], opts()}
  def tabbed_content(tabs, opts \\ []) do
    {:tabbed_content, tabs, opts}
  end

  @doc """
  The application's title bar. Returns `{:header, title, opts}`.

  `title` is the `String.t()` shown on the left, or `nil` to take the `:title`
  option instead.

  Options beyond the shared element keys:

    * `:title` - fallback title, used when the first argument is `nil`. Default `""`.
    * `:show_clock` - `boolean()`, default `false`. Draws a self-updating clock on
      the right, and starts the 1-second timer that keeps it current.
    * `:clock_format` - `:time` (default) or the other formats accepted by
      `Drafter.Widget.Header`.

  Only the title reaches an already-mounted header, so changing `:show_clock` or
  `:clock_format` on a re-render has no effect. Not focusable, so it reserves no
  keys.

      iex> header("Counter")
      {:header, "Counter", []}

      iex> header(nil, title: "Counter", show_clock: false)
      {:header, nil, [title: "Counter", show_clock: false]}
  """
  @spec header(String.t() | nil, opts()) :: {:header, String.t() | nil, opts()}
  def header(title, opts \\ []) do
    {:header, title, opts}
  end

  @doc """
  The application's key-hint bar. Returns `{:footer, opts}`.

  Takes options only — unlike `Drafter.footer/2`, there is no text argument.
  `use Drafter.App` imports this module and not `Drafter`, so an unqualified
  `footer(...)` in an application module is always this function; reaching
  `Drafter.footer/2` needs the `Drafter.` prefix. Adding `import Drafter` alongside
  `use Drafter.App` does not give you a choice — it makes `footer/1`, `vertical/1`
  and every other name the two modules share ambiguous, and the module fails to
  compile.

  A footer element is docked to the bottom of its enclosing `vertical/2` container
  whether or not `dock: :bottom` is given.

  Options beyond the shared element keys, all forwarded to `Drafter.Widget.Footer`:

    * `:bindings` - a list of `{key_label, hint}` tuples to show. Default `nil`,
      which reads the active screen's `keybindings/0` — the app module's when no
      screen is on the `Drafter.ScreenManager` stack — i.e. the hints registered by
      `keybinding/3`, and `[]` when the module defines none.
    * `:separator` - `String.t()` placed between entries. Default `" "`.
    * `:style` - `map()` of style attributes for the hint text. Default `nil`.
    * `:key_style` - `map()` of style attributes for the key labels. Default `nil`.

  The hints are what `keybinding/3` registered, which is not the same as what the
  keys do: a hint whose key the focused widget consumes is displayed anyway. See
  "Where a key is handled" in `Drafter.App`.

      iex> footer()
      {:footer, []}

      iex> footer(bindings: [{"Q", "quit"}], separator: " | ")
      {:footer, [bindings: [{"Q", "quit"}], separator: " | "]}
  """
  @spec footer(opts()) :: {:footer, opts()}
  def footer(opts \\ []) do
    {:footer, opts}
  end

  @doc """
  A viewport that scrolls its children. Returns `{:scrollable, children, opts}`.

  `children` is a list of elements, whose summed preferred heights become the
  scrollable content height. One column on the right is reserved for the vertical
  scrollbar.

  Options beyond the shared element keys — these five are the only ones this element
  reads, and the rest of `Drafter.Widget.ScrollableContainer`'s options are not
  forwarded:

    * `:focusable` - `boolean()`. Default `true`. `false` keeps the container out of
      the Tab order, and the keys below then reach whatever else has focus.
    * `:click_to_scroll` - `boolean()`, jump the viewport to a clicked position.
      Default `false`.
    * `:show_vertical_scrollbar` - `:auto` (default), `:always`, or `:never`.
    * `:show_horizontal_scrollbar` - `:never` (default), `:auto`, or `:always`.
    * `:height` - `pos_integer()` used as the element's preferred height in a
      parent's layout. Default: the summed heights of `children`.

  A focused scrollable consumes `↑`, `↓`, `Home`, `End`, `PageUp` and `PageDown`.

      iex> scrollable([label("row 1")], show_vertical_scrollbar: :always)
      {:scrollable, [{:label, "row 1", []}], [show_vertical_scrollbar: :always]}
  """
  @spec scrollable([element()], opts()) :: {:scrollable, [element()], opts()}
  def scrollable(children, opts \\ []) do
    {:scrollable, children, opts}
  end

  @doc """
  Two panes separated by a draggable divider.

  Returns `{:split_pane, children, opts}`. `children` is the list of pane elements;
  only the **first two** are laid out — a third and beyond are dropped.

  Options beyond the shared element keys:

    * `:orientation` - `:horizontal` (default) puts the panes side by side with a
      vertical divider; `:vertical` stacks them.
    * `:ratio` - `float()` in `0.0`..`1.0`, the divider's starting position.
      Default `0.5`. It is a mount-time value only: a later `:ratio` change does not
      reach the already-created divider.
    * `:show_handle` - `boolean()`, draw the grip glyph. Default `true`. Mount-time
      only.
    * `:resize_mode` - `:quick` (default) or the other modes
      `Drafter.Widget.SplitPaneDivider` accepts. Mount-time only.
    * `:id` - names the divider `:"<id>_divider"` rather than the generated
      `:"<Module>_split_divider_<n>"`.

  See `Drafter.Widget.SplitPaneDivider` for the divider itself.

      iex> split_pane([label("left"), label("right")], ratio: 0.3)
      {:split_pane, [{:label, "left", []}, {:label, "right", []}], [ratio: 0.3]}
  """
  @spec split_pane([element()], opts()) :: {:split_pane, [element()], opts()}
  def split_pane(children, opts \\ []) do
    {:split_pane, children, opts}
  end

  @doc """
  A syntax-highlighted source view. Returns `{:code_view, opts}`.

  Called with a single keyword list, the source comes from the options. Called as
  `code_view(content, opts)` with a `String.t()` first argument, the content is
  prepended as `source: content`, so an explicit `:source` in `opts` is shadowed by
  the positional argument. A non-list `opts` or a non-binary first argument raises
  `FunctionClauseError`.

  Highlighting requires `Drafter.run(app, syntax_highlighting: true)`; without it
  the source renders unstyled. See `Drafter.Widget.CodeView` for the options.

  A focused code view consumes the arrow keys, `Enter`, `Space`, `Escape`, `Home`,
  `End`, `PageUp`, `PageDown`, `Backspace` and the printable keys, so almost nothing
  reaches a `keybinding/3` clause while it has focus.

      iex> code_view(source: "IO.puts(:hi)", language: :elixir)
      {:code_view, [source: "IO.puts(:hi)", language: :elixir]}

      iex> code_view("IO.puts(:hi)", language: :elixir)
      {:code_view, [source: "IO.puts(:hi)", language: :elixir]}
  """
  @spec code_view(opts()) :: {:code_view, opts()}
  def code_view(opts \\ []) when is_list(opts) do
    {:code_view, opts}
  end

  @spec code_view(String.t(), opts()) :: {:code_view, opts()}
  def code_view(content, opts) when is_binary(content) and is_list(opts) do
    {:code_view, [source: content] ++ opts}
  end

  @doc """
  Returns `{:push_screen, screen_module, props, opts}`.

  `screen_module` is another `Drafter.App` module, `props` the map handed to its
  `mount/1` (default `%{}`), `opts` the screen options (default `[]`).

  The application loop and `Drafter.ActionHandler` dispatch on `{:push, module,
  props, opts}`, not on this tag: returning this tuple from `handle_event/2` raises
  `FunctionClauseError` in the loop, and returning it from `handle_event/3` leaves
  the state unchanged with no screen pushed. Return `{:push, screen_module, props,
  opts}` to push a screen.

      iex> push_screen(MyApp.Detail, %{id: 7})
      {:push_screen, MyApp.Detail, %{id: 7}, []}
  """
  @spec push_screen(module(), props(), opts()) :: {:push_screen, module(), props(), opts()}
  def push_screen(screen_module, props \\ %{}, opts \\ []) do
    {:push_screen, screen_module, props, opts}
  end

  @doc """
  Pops the top screen off the `Drafter.ScreenManager` stack.

  Returns `{:pop, result}`, which both `handle_event/2` and `handle_event/3`
  dispatch. `result` (default `nil`) is delivered to the revealed screen's
  `handle_event/3`.

      iex> pop_screen()
      {:pop, nil}

      iex> pop_screen({:selected, 3})
      {:pop, {:selected, 3}}
  """
  @spec pop_screen(term()) :: {:pop, term()}
  def pop_screen(result \\ nil) do
    {:pop, result}
  end

  @doc """
  Returns `{:replace, screen_module, props}`.

  `screen_module` is another `Drafter.App` module and `props` the map handed to its
  `mount/1` (default `%{}`). The third argument is accepted and discarded.

  The application loop and `Drafter.ActionHandler` dispatch on the four-element
  `{:replace, module, props, opts}`, not on this three-element tuple: returning this
  from `handle_event/2` raises `FunctionClauseError` in the loop, and returning it
  from `handle_event/3` leaves the state unchanged with no screen replaced. Return
  `{:replace, screen_module, props, opts}` to replace the top screen.

      iex> replace_screen(MyApp.Detail, %{id: 7}, title: "ignored")
      {:replace, MyApp.Detail, %{id: 7}}
  """
  @spec replace_screen(module(), props(), opts()) :: {:replace, module(), props()}
  def replace_screen(screen_module, props \\ %{}, _opts \\ []) do
    {:replace, screen_module, props}
  end

  @doc """
  Opens `screen_module` as a modal over the current screen.

  Returns `{:show_modal, screen_module, props, opts}`, which both `handle_event/2`
  and `handle_event/3` dispatch. `props` (default `%{}`) is the map handed to the
  modal's `mount/1`; `opts` (default `[]`) is passed to
  `Drafter.ScreenManager.show_modal/3` and carries the modal's `:title`, `:width`,
  `:height`, and `:border`.

      iex> show_modal(ConfirmModal, %{}, title: "Confirm", width: 45, height: 10)
      {:show_modal, ConfirmModal, %{}, [title: "Confirm", width: 45, height: 10]}
  """
  @spec show_modal(module(), props(), opts()) :: {:show_modal, module(), props(), opts()}
  def show_modal(screen_module, props \\ %{}, opts \\ []) do
    {:show_modal, screen_module, props, opts}
  end

  @doc """
  Returns `{:push_screen, screen_module, props, [{:type, :popover} | opts]}`.

  A `:type` already in `opts` is overwritten with `:popover`. Carries the same
  unmatched tag as `push_screen/3` and has the same failure modes: the loop raises
  `FunctionClauseError` on it from `handle_event/2`, and ignores it from
  `handle_event/3`.

      iex> show_popover(MyApp.Menu)
      {:push_screen, MyApp.Menu, %{}, [type: :popover]}
  """
  @spec show_popover(module(), props(), opts()) :: {:push_screen, module(), props(), opts()}
  def show_popover(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :popover)
    {:push_screen, screen_module, props, opts}
  end

  @doc """
  Returns `{:push_screen, screen_module, props, [{:type, :panel} | opts]}`.

  A `:type` already in `opts` is overwritten with `:panel`. Carries the same
  unmatched tag as `push_screen/3` and has the same failure modes.

      iex> show_panel(MyApp.Sidebar, %{}, width: 30)
      {:push_screen, MyApp.Sidebar, %{}, [type: :panel, width: 30]}
  """
  @spec show_panel(module(), props(), opts()) :: {:push_screen, module(), props(), opts()}
  def show_panel(screen_module, props \\ %{}, opts \\ []) do
    opts = Keyword.put(opts, :type, :panel)
    {:push_screen, screen_module, props, opts}
  end

  @doc """
  Shows a transient message over the current screen.

  Returns `{:show_toast, message, opts}`, which both `handle_event/2` and
  `handle_event/3` dispatch. `message` is a `String.t()`; `opts` (default `[]`) is
  passed to `Drafter.ScreenManager.show_toast/2`, which documents the keys it reads.

      iex> show_toast("Saved", duration: 2000)
      {:show_toast, "Saved", [duration: 2000]}
  """
  @spec show_toast(String.t(), opts()) :: {:show_toast, String.t(), opts()}
  def show_toast(message, opts \\ []) do
    {:show_toast, message, opts}
  end

  @doc """
  Closes the topmost modal. Returns `{:pop, :dismissed}`, so the revealed screen's
  `handle_event/3` receives `:dismissed` as its data.

  Identical to `pop_screen(:dismissed)`; it pops whatever is on top of the
  `Drafter.ScreenManager` stack, modal or not.

      iex> dismiss_modal()
      {:pop, :dismissed}
  """
  @spec dismiss_modal() :: {:pop, :dismissed}
  def dismiss_modal do
    {:pop, :dismissed}
  end

  @doc """
  Assembles a header/content/footer screen into one vertical layout.

  `parts` is a keyword list read for `:header`, `:content`, and `:footer`; each
  defaults to `nil` and an omitted part leaves no gap. Every other key is ignored.
  `:content` may be a single element or a list of them. When a `:footer` is present
  the content is wrapped in a `vertical(content, flex: 1)` so it absorbs the leftover
  rows; without a footer a list of content elements is spliced in directly.

  Returns a `vertical/2` element whose own options are always `[]`, so `:gap`,
  `:padding` and the shared element keys cannot be set through this function — build
  the `vertical/2` by hand when you need them.

      iex> screen_layout(header: header("Files"), content: [tree(id: :files)], footer: footer())
      {:layout, :vertical,
       [
         {:header, "Files", []},
         {:layout, :vertical, [{:tree, [id: :files]}], [flex: 1]},
         {:footer, []}
       ], []}

      iex> screen_layout(content: label("body"))
      {:layout, :vertical, [{:label, "body", []}], []}
  """
  @spec screen_layout(keyword()) :: {:layout, :vertical, [element()], []}
  def screen_layout(parts) when is_list(parts) do
    header = parts[:header]
    footer = parts[:footer]
    content = parts[:content]

    []
    |> maybe_prepend_header(header)
    |> append_content(content, footer)
    |> maybe_append_footer(footer)
    |> vertical()
  end

  defp maybe_prepend_header(parts, nil), do: parts
  defp maybe_prepend_header(parts, header), do: parts ++ [header]

  defp append_content(parts, nil, _footer), do: parts

  defp append_content(parts, content, footer) when not is_nil(footer) do
    parts ++ [vertical(content, flex: 1)]
  end

  defp append_content(parts, content, _footer) when is_list(content) do
    parts ++ content
  end

  defp append_content(parts, content, _footer) do
    parts ++ [content]
  end

  defp maybe_append_footer(parts, nil), do: parts
  defp maybe_append_footer(parts, footer), do: parts ++ [footer]
end
