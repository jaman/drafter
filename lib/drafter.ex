defmodule Drafter do
  @moduledoc ~S"""
  Entry point of the Drafter terminal UI framework.

  This module starts applications (`run/2`, `run_session/3`) and holds the runtime
  API an application calls from inside its callbacks: timers, focus, widget value
  reads and writes, data-channel pushes, selector queries, theming, and animation.

  An application module is written with `use Drafter.App`, which is where the
  callbacks, their return shapes, and the element constructors are documented.

      defmodule Counter do
        use Drafter.App

        def mount(_props), do: %{count: 0}

        def render(state) do
          vertical([
            header("Counter"),
            label("Count: #{state.count}"),
            button("Increment", on_click: :increment),
            footer()
          ])
        end

        keybinding :q, "quit" do
          {:stop, :normal}
        end

        def handle_event(:increment, _data, state), do: {:ok, %{state | count: state.count + 1}}
        def handle_event(_name, _data, state), do: {:noreply, state}
      end

      Drafter.run(Counter)

  ## Two ways to build a component tree

  `render/1` may return either shape, and they may be mixed in one tree:

    * the tag tuples from the constructors imported by `use Drafter.App` —
      `label("hi")` gives `{:label, "hi", []}`;
    * the `{WidgetModule, props_map}` tuples from the constructors in this module —
      `Drafter.label("hi")` gives `{Drafter.Widget.Label, %{text: "hi"}}`, which is
      also the shape a third-party widget library returns.

  ## Calling the runtime API

  The functions here that read or change widget state are meant to be called from
  the application process — inside `handle_event`, `on_timer`, `on_ready`, or
  `on_message`. Called from another process they resolve the loop through
  `Drafter.AppRegistry`, which needs that process to carry a session id; see
  `Drafter.AppRegistry.current_session/0`.

  ## Widget ids

  Every function here that names a widget takes a `t:widget_id/0`. An element's
  `:id` option becomes its id unchanged, so `id: :submit` stays the atom `:submit`.
  An element given `:key` instead gets a generated `String.t()` of the form
  `"App_button#key"`, and an element given neither gets a generated atom of the form
  `:App_button_3`. `query_one/1` and `query_all/1` return ids in whichever of those
  forms the element produced.

  ## Keys the runtime takes first

  `Ctrl+q`, with no other modifier held, is consumed by the application loop before
  any widget or app keybinding sees it, and stops the app with reason `:normal`.
  Keybindings themselves, and the keys the runtime claims, are documented in
  `Drafter.App`.
  """

  alias Drafter.{Compositor, Event, SkinManager, Terminal, ThemeManager}
  alias Drafter.Runtime
  alias Drafter.Runtime.{AppLoop, Renderer}
  alias Drafter.Session.Context
  alias Drafter.Session.SharedState
  alias Drafter.Widget.Chart.Pixel
  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetValue

  alias Drafter.Widget.{
    Button,
    Container,
    Digits,
    Footer,
    Grid,
    Label,
    Markdown,
    Placeholder,
    Rule
  }

  @typedoc """
  Identifies a widget in the running hierarchy.

  An `:id` given to an element is used unchanged; a generated id is an atom, or a
  `String.t()` when the element was given a `:key`.
  """
  @type widget_id :: atom() | String.t()

  @typedoc """
  An element in the `{WidgetModule, props}` form every constructor in this module
  returns, and the form a third-party widget library returns.

  The map reaches the widget module's `mount/1` with only `:app_module` and the
  renderer's own `:__rect__` and `:__widget_id__` added, so its keys are the widget's
  own prop names — `:classes` rather than the `:class` element option, and `:id` or
  `:key` to fix the widget id.
  """
  @type element :: {module(), map()}

  @doc """
  Declares an application module.

  `use Drafter` expands to `use Drafter.App` with the same options, plus an import of
  `state/1`. Every option `Drafter.App` accepts is accepted here:

    * `:css_path` - path to a stylesheet loaded at compile time. Default `nil`.
    * `:styles` - `map()` of inline styles. Default `%{}`.
    * `:mouse_hover` - `boolean()`, default `true`, enabling mouse motion tracking.
      `false` reports clicks only. `run/2` reads this from the app module, not from
      its own options.
    * `:runtime` - the callback backend, as a module or one of the shorthands
      `:callback`, `:reducer`, `:shared`. Default `Drafter.Runtime.Callback`, which
      is `:callback`; `:reducer` takes `update/2` in place of `handle_event/3`.

      use Drafter, runtime: :reducer
  """
  defmacro __using__(opts) do
    quote do
      use Drafter.App, unquote(opts)
      import Drafter, only: [state: 1]
    end
  end

  @doc """
  Declares the application's initial state in place of writing `mount/1`.

  `initial` is the term every `mount/1` call returns, ignoring its props. Defines an
  overridable `mount/1`, so a later `def mount(props)` in the same module wins.

      use Drafter
      state %{count: 0}
  """
  defmacro state(initial) do
    quote do
      def mount(_props), do: unquote(initial)
      defoverridable mount: 1
    end
  end

  @doc """
  Starts `app_module` on the terminal and blocks until it exits.

  `app_module` is a module that does `use Drafter.App`. `opts` is a keyword list;
  every key has a default, so `Drafter.run(MyApp)` is a complete call.

  Called from an application that is already running, this pushes `app_module` as a
  nested session and returns to the caller when that session stops, rather than
  starting a second terminal. A nested session always returns `:ok`, whatever reason
  it stopped for, and honours only `:props` and `:refresh_rate` from `opts` —
  `:log`, `:scroll_optimization` and `:halt_on_exit` belong to a standalone run.

  For a standalone run, returns `:ok` when the app stopped with `{:stop, :normal}` or
  the global `Ctrl+q`, and `{:error, reason}` for any other stop reason or a failure
  to start. With `halt_on_exit: true` — the default — the VM is halted before that
  value can be observed: exit status `0` for `:ok`, `1` otherwise.

  ## Options

    * `:props` - `map()` handed to the app's `mount/1`. Default `%{}`. A keyword list
      is accepted and converted to a map. The same key works for a nested session and
      for `run_session/3` behind the ssh and telnet transports, so an app receives the
      same map however it was started.
    * `:refresh_rate` - frame pacing: `"30fps"`, `"7.5fps"`, `"unlimited"`,
      `:unlimited`, or a millisecond integer. Anything else raises `ArgumentError`.
      Default: the app's `refresh_rate/0`, and `"30fps"` when that returns `nil`.
    * `:clipboard` - `true` (the default) lets `Drafter.Clipboard.copy/1` write to the
      user's clipboard via OSC 52 and the local clipboard tool. `false` makes copying
      a no-op returning `{:error, :disabled}` and drops bracketed pastes before any
      widget sees them. A keyword list sets the two directions separately, each
      defaulting to `true`: `clipboard: [copy: true, paste: false]`.
    * `:scroll_optimization` - `boolean()`, default `true`, rendering from the
      cached hierarchy during a scroll gesture and deferring a full re-render until
      150 ms after the last scroll event. `false` runs a full re-render on every
      scroll tick: maximum freshness at higher CPU cost.
    * `:syntax_highlighting` - `boolean()`, default `false`. `true` starts the
      tree-sitter server that `Drafter.Widget.CodeView` needs.
    * `:widget_libraries` - list of modules to register before the app mounts, each
      either a `Drafter.WidgetLibrary` or a single widget module defining
      `component_tag/0`. Default `[]`.
    * `:mode` - global chart rendering mode: `:auto`, `:pixel`, `:kitty`, `:iterm2`,
      `:sixel`, `:braille`, or `:text`. Default: unset, which `Drafter.Widget.Chart.Pixel`
      resolves as `:text`. The lowest-precedence layer — a per-widget `:renderer`
      overrides it, and the `DRAFTER_MODE` env var overrides both. See `render_mode/1`.
    * `:log` - file logging. `false` (default) silences the console handler so logs
      cannot corrupt the display, and writes no file; `true` writes `drafter.log` in
      the current directory; a path string writes there instead.
    * `:level` - minimum level for the file log, default `:debug`. Read only when
      `:log` is `true` or a path.
    * `:halt_on_exit` - `boolean()`, default `true`, calling `System.halt/1` once
      the app exits for an immediate quit rather than the BEAM's graceful
      application shutdown. Applies only to a standalone run; a nested session
      always returns to its parent. Set `false` when embedding a run in a
      longer-lived VM so the caller regains control.

  `:mouse_hover` is not an option here: hover tracking is enabled from the app
  module, with `use Drafter.App, mouse_hover: false`.

      Drafter.run(MyApp, props: %{user_id: 7}, refresh_rate: "60fps", log: "/tmp/app.log")
  """
  @spec run(module(), keyword()) :: :ok | {:error, term()}
  def run(app_module, opts \\ []) when is_atom(app_module) do
    apply_render_mode(opts)
    apply_clipboard_setting(opts)

    case Drafter.AppRegistry.whereis() do
      nil ->
        _ = Drafter.Logging.setup(opts)
        Drafter.Trace.stamp_on_exit()

        mouse_hover = app_mouse_hover(app_module)

        result =
          with :ok <- start_system(mouse_hover: mouse_hover),
               :ok <- maybe_start_tree_sitter(opts),
               :ok <- register_widget_libraries(opts),
               :ok <- run_app(app_module, opts) do
            :ok
          else
            {:error, reason} ->
              IO.puts("Failed to start TUI application: #{inspect(reason)}")
              {:error, reason}
          end

        maybe_halt(result, opts)

      loop_pid ->
        maybe_start_tree_sitter(opts)
        register_widget_libraries(opts)
        action_handlers = Drafter.ActionRegistry.collect()
        ref = make_ref()
        send(loop_pid, {:push_session, app_module, opts, action_handlers, self(), ref})

        receive do
          {:session_result, ^ref, result} -> result
        end
    end
  end

  @doc """
  A label element. Returns `{Drafter.Widget.Label, props}`.

  `props` is `opts` as a map with `:text` filled in from `text` unless `opts` already
  carries a `:text` key.

  ## Options

    * `:text` - the string to draw. Default: the `text` argument.
    * `:style` - `map()` of segment style overrides. Default `%{}`.
    * `:align` - `:left` (default), `:center`, or `:right`.
    * `:variant` - theme variant atom, added to the widget's classes when it is not
      `:default`. Default `:default`.
    * `:classes` - list of class atoms matched by `query_one/1` and CSS selectors.
      Default `[]`. Note the plural: `:class` is the element-tuple option, and is
      not read here.
    * `:id` - fixes the widget id. Default: a generated id.
    * `:key` - identity for a list item, producing a `String.t()` id. Default: none.

  ## Examples

      iex> Drafter.label("Ready")
      {Drafter.Widget.Label, %{text: "Ready"}}

      iex> Drafter.label("Ready", align: :center)
      {Drafter.Widget.Label, %{align: :center, text: "Ready"}}

      iex> Drafter.label("ignored", text: "wins")
      {Drafter.Widget.Label, %{text: "wins"}}

  """
  @spec label(String.t(), keyword()) :: {Label, map()}
  def label(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Label, props}
  end

  @doc """
  A button element. Returns `{Drafter.Widget.Button, props}`.

  `props` is `opts` as a map with `:text` filled in from `text` unless `opts` already
  carries a `:text` key. Pass `on_click:` an atom to have it delivered to the app's
  `handle_event/3`.

  ## Options

    * `:text` - the caption. Default: the `text` argument.
    * `:on_click` - atom delivered to `handle_event/3`, or a zero-arity function
      called, when the button is pressed. Default `nil`, which makes the button
      inert. A disabled button never fires it.
    * `:variant` - `:default` (the default), `:primary`, `:success`, `:warning`,
      `:error`. Added to the widget's classes when it is not `:default`.
    * `:button_type` - the same thing under an older name, read only when `:variant`
      is absent. Default `:default`.
    * `:disabled` - `boolean()`, default `false`. Adds the `:disabled` class.
    * `:compact` - `boolean()`, default `false`. `true` draws one row instead of
      three.
    * `:focused` - `boolean()`, default `false`, the initial focus state.
    * `:style` - `map()` of segment style overrides. Default `%{}`.
    * `:classes` - list of class atoms. Default `[]`.

  ## Examples

      iex> Drafter.button("Save", on_click: :save)
      {Drafter.Widget.Button, %{on_click: :save, text: "Save"}}

  """
  @spec button(String.t(), keyword()) :: {Button, map()}
  def button(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Button, props}
  end

  @doc """
  A layout container. Returns `{Drafter.Widget.Container, props}`.

  `children` is a list of elements, placed under `:children` unless `opts` already
  carries a `:children` key.

  ## Options

    * `:children` - the child elements. Default: the `children` argument.
    * `:layout` - `:vertical` (default) stacks children top to bottom,
      `:horizontal` lays them out left to right.
    * `:padding` - cells of inset on every side, an integer. Default `0`.
    * `:border_style` - `:none` (default), or a border style
      `Drafter.Widget.Container` draws around the content.
    * `:style` - `map()` of segment style overrides. Default `%{}`.

  ## Examples

      iex> Drafter.container([Drafter.label("hi")])
      {Drafter.Widget.Container, %{children: [{Drafter.Widget.Label, %{text: "hi"}}]}}

  """
  @spec container([element()], keyword()) :: {Container, map()}
  def container(children, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:children, children)
    {Container, props}
  end

  @doc """
  A container that stacks `children` top to bottom.

  `container/2` with `layout: :vertical` forced over `opts`, so a `:layout` in `opts`
  is discarded. Every other `container/2` option applies.

  ## Examples

      iex> Drafter.vertical([])
      {Drafter.Widget.Container, %{children: [], layout: :vertical}}

  """
  @spec vertical([element()], keyword()) :: {Container, map()}
  def vertical(children, opts \\ []) do
    opts = Keyword.put(opts, :layout, :vertical)
    container(children, opts)
  end

  @doc """
  A container that lays `children` out left to right.

  `container/2` with `layout: :horizontal` forced over `opts`, so a `:layout` in
  `opts` is discarded. Every other `container/2` option applies.

  ## Examples

      iex> Drafter.horizontal([], padding: 1)
      {Drafter.Widget.Container, %{children: [], layout: :horizontal, padding: 1}}

  """
  @spec horizontal([element()], keyword()) :: {Container, map()}
  def horizontal(children, opts \\ []) do
    opts = Keyword.put(opts, :layout, :horizontal)
    container(children, opts)
  end

  @doc """
  Large seven-segment style digits. Returns `{Drafter.Widget.Digits, props}`.

  `text` is the string to draw, placed under `:text` unless `opts` already carries a
  `:text` key.

  ## Options

    * `:text` - the string to draw. Default: the `text` argument.
    * `:style` - `map()` of segment style overrides. Default `%{}`.
    * `:align` - `:left` (default), `:center`, or `:right`.
    * `:size` - coarse size when no `:font` is given: `:large` (default, 7×5) or
      `:small` (5×3).
    * `:font` - a name from `Drafter.Widget.Digits.Font.names/0`, or a font map.
      Default `nil`; overrides `:size` when given.
    * `:renderer` - `:text` (default) or a pixel renderer atom.
    * `:color` - `{r, g, b}` foreground. Default `{0, 150, 255}`.
    * `:bg_data` - series driving a background fill. Default `nil`.
    * `:bg_min` - low bound for `:bg_data`. Default `0`.
    * `:bg_max` - high bound for `:bg_data`. Default `nil`, meaning the data's own
      maximum.

  ## Examples

      iex> Drafter.digits("12:00")
      {Drafter.Widget.Digits, %{text: "12:00"}}

  """
  @spec digits(String.t(), keyword()) :: {Digits, map()}
  def digits(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Digits, props}
  end

  @doc """
  A two-dimensional grid. Returns `{Drafter.Widget.Grid, props}`.

  `children` is a list of elements, placed under `:children` unless `opts` already
  carries a `:children` key. An empty child list renders nothing.

  ## Options

    * `:children` - the child elements. Default: the `children` argument.
    * `:grid_size` - number of columns. Default `2`.
    * `:grid_rows` - number of rows, or `:auto` (the default) to derive it from the
      child count and `:grid_size`.
    * `:padding` - cells of gap between cells. Default `1`.
    * `:style` - `map()` of segment style overrides. Default `%{}`.

  ## Examples

      iex> Drafter.grid([], grid_size: 3)
      {Drafter.Widget.Grid, %{children: [], grid_size: 3}}

  """
  @spec grid([element()], keyword()) :: {Grid, map()}
  def grid(children, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:children, children)
    {Grid, props}
  end

  @doc """
  A labelled block that fills its space. Returns `{Drafter.Widget.Placeholder, props}`.

  `text` is placed under `:text` unless `opts` already carries a `:text` key.

  ## Options

    * `:text` - the caption. Default: the `text` argument, which this constructor
      always supplies; `Drafter.Widget.Placeholder` falls back to `"Placeholder"`
      when no `:text` reaches it. The first run of digits anywhere in the text picks
      the pastel background, and text with no digits uses the first colour.
    * `:style` - `map()` of segment style overrides. Default: a pastel background
      with a contrasting foreground, chosen from `:text`.
    * `:padding` - cells of inset. Default `2`.
    * `:align` - `:center` (default), `:left`, or `:right`.
    * `:border` - `boolean()`, default `false`.

  ## Examples

      iex> Drafter.placeholder("Panel 1")
      {Drafter.Widget.Placeholder, %{text: "Panel 1"}}

  """
  @spec placeholder(String.t(), keyword()) :: {Placeholder, map()}
  def placeholder(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Placeholder, props}
  end

  @doc """
  A divider line. Returns `{Drafter.Widget.Rule, Map.new(opts)}`.

  ## Options

    * `:orientation` - `:horizontal` (default) or `:vertical`.
    * `:title` - text drawn into the line. Default `nil`, an unbroken line.
    * `:title_align` - `:center` (default), `:left`, or `:right`.
    * `:line_style` - `:solid` (default) or another line style
      `Drafter.Widget.Rule` draws.
    * `:style` - `map()` of segment style overrides. Default `%{}`.

  ## Examples

      iex> Drafter.rule()
      {Drafter.Widget.Rule, %{}}

      iex> Drafter.rule(title: "Settings")
      {Drafter.Widget.Rule, %{title: "Settings"}}

  """
  @spec rule(keyword()) :: {Rule, map()}
  def rule(opts \\ []) do
    {Rule, Map.new(opts)}
  end

  @doc """
  Rendered Markdown. Returns `{Drafter.Widget.Markdown, props}`.

  `content` is the Markdown source, placed under `:content` unless `opts` already
  carries a `:content` key. Note the key: this widget reads `:content`, not `:text`,
  and `get_widget_value/1` therefore returns `nil` for it.

  ## Options

    * `:content` - the Markdown source. Default: the `content` argument.
    * `:style` - `map()` of segment style overrides. Default `%{}`.
    * `:padding` - cells of inset. Default `1`.

  ## Examples

      iex> Drafter.markdown("# Title")
      {Drafter.Widget.Markdown, %{content: "# Title"}}

  """
  @spec markdown(String.t(), keyword()) :: {Markdown, map()}
  def markdown(content, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:content, content)
    {Markdown, props}
  end

  @doc """
  A footer bar. Returns `{Drafter.Widget.Footer, props}`.

  `text` is placed under `:text`, which `Drafter.Widget.Footer` does not read, so the
  argument only ever changes the props map: the bar shows the key hints from
  `:bindings`, or from the active module's `keybindings/0` when `:bindings` is absent.

  ## Options

    * `:bindings` - list of `{key_label, description}` string pairs. Default `nil`,
      which falls back to the app module's `keybindings/0`.
    * `:separator` - string drawn between hints. Default `" "`.
    * `:style` - `map()` of segment style overrides for the descriptions. Default
      `nil`, meaning the theme's footer style.
    * `:key_style` - `map()` of segment style overrides for the key labels. Default
      `nil`, meaning the theme's footer key style.

  ## Examples

      iex> Drafter.footer()
      {Drafter.Widget.Footer, %{text: "Press 'q' to quit"}}

      iex> Drafter.footer("", bindings: [{"Ctrl+Q", "quit"}])
      {Drafter.Widget.Footer, %{bindings: [{"Ctrl+Q", "quit"}], text: ""}}

  """
  @spec footer(String.t(), keyword()) :: {Footer, map()}
  def footer(text \\ "Press 'q' to quit", opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Footer, props}
  end

  @doc """
  Starts a repeating timer that calls the app's `on_timer/2` with `timer_id`.

  `value` is a period in milliseconds for every `timer_id` except `:fps`, where it is
  a frame rate and the period becomes `round(1000 / value)`. `timer_id` defaults to
  `:tick`. Returns `:ok`.

  Must be called from the application process — inside `on_ready/1`, `handle_event`,
  `on_timer/2`, or `on_message/2`. A timer started in `on_ready/1` is registered
  before the loop begins receiving; one started later is registered on the loop's
  next pass. The timer runs until the app stops. There is no cancel: a second call
  with the same `timer_id` starts a second timer, and both keep firing `on_timer/2`
  with that id.

  ## Examples

      iex> Drafter.set_interval(500, :poll)
      :ok

      iex> Drafter.set_interval(24, :fps)
      :ok

      iex> Drafter.set_interval(1000)
      :ok

  """
  @spec set_interval(number(), atom()) :: :ok
  def set_interval(value, timer_id \\ :tick)

  def set_interval(value, :fps) do
    do_set_interval(round(1000 / value), :fps)
  end

  def set_interval(value, timer_id) do
    do_set_interval(value, timer_id)
  end

  defp do_set_interval(interval_ms, timer_id) do
    case Process.get(:pending_intervals) do
      nil -> send(self(), {:set_interval, interval_ms, timer_id})
      pending -> Process.put(:pending_intervals, [{interval_ms, timer_id} | pending])
    end

    :ok
  end

  @doc """
  Schedules a single call to the app's `on_timer/2` with `timer_id`.

  `timeout_ms` is the delay in milliseconds; `timer_id` is the atom `on_timer/2`
  matches on. Both arguments are required. Returns `:ok`.

  Must be called from the application process: this sends a message to `self()`, so
  from any other process it does nothing but leave that message in the caller's own
  mailbox. Unlike `set_interval/2` this fires once and needs no cancellation.

  ## Examples

      iex> Drafter.set_timeout(2000, :hide_toast)
      :ok

  """
  @spec set_timeout(pos_integer(), atom()) :: :ok
  def set_timeout(timeout_ms, timer_id) do
    send(self(), {:set_timeout, timeout_ms, timer_id})
    :ok
  end

  @doc """
  Moves keyboard focus to the widget with `widget_id`.

  Returns `:ok` without waiting; focus is applied on the loop's next pass, which also
  re-renders. An id that is not in the current hierarchy leaves focus where it was.

  Must be called from the application process: this sends a message to `self()`, so
  from any other process it does nothing but leave that message in the caller's own
  mailbox.

  ## Examples

      iex> Drafter.focus(:search_box)
      :ok

  """
  @spec focus(widget_id()) :: :ok
  def focus(widget_id) do
    send(self(), {:focus_widget, widget_id})
    :ok
  end

  @doc """
  The current primary value of the widget with `widget_id`.

  The value is not a per-widget-type lookup: it is read out of whatever state the
  widget keeps, by the shapes `Drafter.WidgetValue.extract/1` documents — `:text`,
  `:checked`, an `:on`/`:off` `:state`, a selection alongside `:options`, `:expanded`,
  `:active_tab`, `:selected_rows`, `:selected_nodes`, and a `:value` alongside `:min`,
  `:max` and `:step`.

  Anything else returns `nil`, and so does an id no widget has. Built-in widgets that
  fall through and read as `nil` include `masked_input` and `meter` and `gauge`
  (their value lives under `:value`), `markdown` (`:content`), `header` (`:title`),
  `footer`, `rule`, and `data_table`, whose `:selected_indices` is not accompanied by
  an `:options` field.

  An `option_list` that has never had a selection keeps `:selected_index` at `nil`,
  which this raises `FunctionClauseError` on; read `get_widget_state/1` and its
  `:highlighted_index` instead when a selection is not guaranteed.

  Called from outside the application process this round-trips to the loop and
  returns `nil` if that takes longer than 100 ms, so a timeout is indistinguishable
  from an unknown id.
  """
  @spec get_widget_value(widget_id()) :: term() | nil
  def get_widget_value(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> get_widget_value_via_loop(widget_id)
      pid -> WidgetValue.extract(Drafter.WidgetServer.get_state(pid))
    end
  end

  defp get_widget_value_via_loop(widget_id) do
    case loop_local_hierarchy() do
      :not_in_loop ->
        ask_loop({:get_widget_value, widget_id, self()}, {:widget_value, widget_id}, nil)

      nil ->
        nil

      hierarchy ->
        hierarchy |> WidgetHierarchy.get_widget_state(widget_id) |> WidgetValue.extract()
    end
  end

  @doc """
  Sets the primary value of the widget with `widget_id`. The partial counterpart to
  `get_widget_value/1`.

  It writes only the three shapes `Drafter.WidgetValue.update_props/2` maps, and picks
  by the widget's state, not its type:

    * state with a `:text` field and a `String.t()` — replaces the text; the widget
      reclamps its cursor and selection. `text_input`, `text_area`, and equally
      `label`, `button` and `link`.
    * state with a `:checked` field and a `boolean()` — sets checked. `checkbox`.
    * state with `:value`, `:min`, `:max` and `:step` and a `number()` — sets the
      value, clamped into the range and snapped to the step. `slider`.

  Nothing else is writable here. A `switch`, `radio_set`, `option_list`,
  `selection_list`, `collapsible`, `tabbed_content` or `tree` is left alone, and so is
  `masked_input`, whose text lives under `:value`.

  Always returns `:ok`. An unknown id, a widget with no matching field, and a value
  whose type does not match the field are all silently ignored, so the return value is
  no confirmation that anything changed.

      Drafter.set_widget_value(:query_editor, "select * from quotes")
  """
  @spec set_widget_value(widget_id(), term()) :: :ok
  def set_widget_value(widget_id, value) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil ->
        :ok

      pid ->
        case WidgetValue.update_props(safe_widget_state(pid), value) do
          nil -> :ok
          props -> Drafter.WidgetServer.update_props(pid, props)
        end
    end

    :ok
  end

  defp safe_widget_state(nil), do: nil

  defp safe_widget_state(pid) do
    if Process.alive?(pid), do: Drafter.WidgetServer.get_state(pid)
  catch
    :exit, _ -> nil
  end

  @doc """
  The full state of the widget with `widget_id`.

  Returns everything the widget keeps, not just the primary value
  `get_widget_value/1` extracts. Most widgets hold a struct of their own module;
  those that declare no struct — `digits`, `placeholder`, `markdown`, `grid` — hold a
  plain map, so match on field names rather than on a struct type.

  Returns `nil` when no widget has that id. Called from outside the application
  process this round-trips to the loop and returns `nil` if that takes longer than
  100 ms.
  """
  @spec get_widget_state(widget_id()) :: map() | nil
  def get_widget_state(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> get_widget_state_via_loop(widget_id)
      pid -> safe_widget_state(pid) || get_widget_state_via_loop(widget_id)
    end
  end

  defp get_widget_state_via_loop(widget_id) do
    case loop_local_hierarchy() do
      :not_in_loop ->
        ask_loop({:get_widget_state, widget_id, self()}, {:widget_state, widget_id}, nil)

      nil ->
        nil

      hierarchy ->
        WidgetHierarchy.get_widget_state(hierarchy, widget_id)
    end
  end

  @doc """
  Appends one item to the data channel of the widget with `widget_id`.

  `data` is any term the widget's `apply_data_buffer/3` accepts. Items land in the
  widget's ring buffer and cause a render only when its throttle window opens.

  The element must have been declared with a `:buffer` option, which is what creates
  the ring buffer:

    * `:buffer` - `:auto` for a 128-item buffer, or a positive integer size. No
      default: without it the widget has no data channel and every push is dropped.
    * `:refresh` - the channel's throttle. Default `:on_demand`, which asks for a
      render as soon as the push is handled; a millisecond integer coalesces pushes
      and renders at most once per that many milliseconds.

  Only the tag-tuple elements carry those options. An element written in the
  `{WidgetModule, props}` form is created without a data channel, so pushes to it are
  dropped.

  Always returns `:ok` — when no widget has that id, and when the widget has no
  channel.

      Drafter.push_data(:cpu_sparkline, 42.5)
      Drafter.push_data(:event_log, "Connection established")
  """
  @spec push_data(widget_id(), term()) :: :ok
  def push_data(widget_id, data) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.push_data(pid, data)
    end

    :ok
  end

  @doc """
  Appends every item in `items` to the data channel of the widget with `widget_id`.

  `items` is any enumerable. Same `:buffer` requirement and same `:ok` return as
  `push_data/2`, but one render notification for the whole batch rather than one per
  item.

      Drafter.push_data_many(:cpu_sparkline, [42.5, 43.1, 41.8])
  """
  @spec push_data_many(widget_id(), Enumerable.t()) :: :ok
  def push_data_many(widget_id, items) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.push_data_many(pid, items)
    end

    :ok
  end

  @doc """
  Stops the widget with `widget_id` from rendering its data channel.

  Pushes still accumulate in the ring buffer, and still overwrite its oldest entries
  once it is full; no render is triggered until `resume_widget_data/1`. Always returns
  `:ok`, including when no widget has that id and when it has no data channel.
  """
  @spec pause_widget_data(widget_id()) :: :ok
  def pause_widget_data(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.pause_data(pid)
    end

    :ok
  end

  @doc """
  Resumes the data channel of the widget with `widget_id` after
  `pause_widget_data/1`.

  Anything pushed while paused is rendered on the next throttle window. Always
  returns `:ok`, including when no widget has that id, when it has no data channel,
  and when it was not paused.
  """
  @spec resume_widget_data(widget_id()) :: :ok
  def resume_widget_data(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.resume_data(pid)
    end

    :ok
  end

  @doc """
  Switches the active rendering skin.

  The skin decides which characters `Drafter.CharacterSet` returns for every widget
  render. Built-in skins are `:graphical` (default), `:wireframe`, and `:ascii`.
  Returns `:ok`.

  Must be called from the application process — inside `handle_event`, `on_timer/2`,
  or another callback. This sends a message to `self()`, so from any other process it
  does nothing but leave that message in the caller's own mailbox. The change takes
  effect on the next frame.
  """
  @spec set_skin(atom()) :: :ok
  def set_skin(skin) when is_atom(skin) do
    send(self(), {:skin_change, skin})
    :ok
  end

  @doc """
  Switches the active theme.

  `theme_name` is a `String.t()` naming a theme `Drafter.Theme` knows; a non-binary
  raises `FunctionClauseError`, and a name no theme answers to is ignored. The app the
  theme manager has most recently had registered re-renders with the new theme.

  Asynchronous, and always returns `:ok`, so neither an unknown name nor a failed
  re-render is reported. Raises when the calling process belongs to no session and no
  theme manager is running.
  """
  @spec set_theme(String.t()) :: :ok
  def set_theme(theme_name) when is_binary(theme_name) do
    Drafter.ThemeManager.set_theme(theme_name)
  end

  @doc """
  The active skin: `:graphical`, `:wireframe`, `:ascii`, or a registered skin's atom.

  Reads the calling process's own skin first, then its session's skin manager.
  Answers `:graphical` when the caller has neither, so this never raises and never
  blocks outside a session.

      iex> Drafter.current_skin()
      :graphical

  """
  @spec current_skin() :: atom()
  def current_skin, do: Drafter.SkinManager.get_current_skin()

  @doc """
  The id of the first widget in the hierarchy matching a CSS-like selector.

  `selector` is a `String.t()` combining any of:

    * a type — the widget module's last segment, in either CamelCase or snake_case:
      `"Button"`, `"TextInput"`, `"text_input"`
    * `#id` — the widget's `:id`: `"#submit"`
    * `.class` — one of the widget's `:class` atoms: `".primary"`

  Combine them without spaces to require all of them, e.g. `"Button.primary"` or
  `"TextInput#name"`. A space separates alternatives rather than nesting them:
  `"Button Label"` matches any button or any label.

  A `:pseudo-class` or `::part` is parsed and then ignored, so `"Button:hover"`
  matches every button whether hovered or not. Those two carry weight in stylesheets,
  not here.

  `.class` matches against the widget's own `:classes` state field, which an element
  fills from its `:class` option and an `{WidgetModule, props}` element fills from a
  `:classes` prop.

  Returns the widget id, or `nil` when nothing matches. Ordering follows the
  hierarchy's internal widget map, so "first" is only meaningful for a selector that
  matches one widget.

  Called from outside the application process this round-trips to the loop and
  returns `nil` if that takes longer than 100 ms, so a timeout is indistinguishable
  from no match.
  """
  @spec query_one(String.t()) :: widget_id() | nil
  def query_one(selector) do
    case loop_local_hierarchy() do
      :not_in_loop -> ask_loop({:query_one, selector, self()}, {:query_result, :one}, nil)
      nil -> nil
      hierarchy -> WidgetHierarchy.query_one(hierarchy, selector)
    end
  end

  defp loop_local_hierarchy do
    if self() == Drafter.AppRegistry.whereis() do
      Process.get(:drafter_current_hierarchy)
    else
      :not_in_loop
    end
  end

  defp ask_loop(request, {tag, subtag}, default) do
    Drafter.AppRegistry.send_to_loop(request)

    receive do
      {^tag, ^subtag, result} -> result
    after
      100 -> default
    end
  end

  @doc """
  The ids of every widget matching a CSS-like selector.

  `selector` takes the same forms as `query_one/1`, with the same handling of types,
  ids, classes, and ignored pseudo-classes and parts. Returns a list of widget ids,
  empty when nothing matches. Called from outside the application process this
  round-trips to the loop and returns `[]` if that takes longer than 100 ms, so a
  timeout is indistinguishable from no match.
  """
  @spec query_all(String.t()) :: [widget_id()]
  def query_all(selector) do
    case loop_local_hierarchy() do
      :not_in_loop -> ask_loop({:query_all, selector, self()}, {:query_result, :all}, [])
      nil -> []
      hierarchy -> WidgetHierarchy.query_all(hierarchy, selector)
    end
  end

  @doc """
  Runs the validators of the widget with `widget_id`.

  Sends the widget a `:validate` event and reads back its `:error` field. Returns
  `:ok` when the widget has no error, when it has no validators, when its state has no
  `:error` field at all, and when no widget has that id; returns `{:error, message}`
  with the widget's error string otherwise.

  The updated hierarchy is discarded, so this reports the error without leaving the
  widget marked as validated.

  Called from outside the application process this round-trips to the loop and
  returns `:ok` if that takes longer than 100 ms, so a timeout is indistinguishable
  from a pass.
  """
  @spec validate_widget(widget_id()) :: :ok | {:error, String.t()}
  def validate_widget(widget_id) do
    case loop_local_hierarchy() do
      :not_in_loop ->
        ask_loop({:validate_widget, widget_id, self()}, {:validation_result, widget_id}, :ok)

      nil ->
        :ok

      hierarchy ->
        {new_hierarchy, _} = WidgetHierarchy.send_event_to_widget(hierarchy, widget_id, :validate)
        validation_result(WidgetHierarchy.get_widget_state(new_hierarchy, widget_id))
    end
  end

  defp validation_result(nil), do: :ok

  defp validation_result(state) do
    case Map.get(state, :error) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  @doc """
  Presses the widget with `widget_id` as though the user had activated it.

  The widget runs its activation path, so a button fires its `:on_click` callback and
  the app re-renders. An id no widget has is a no-op, and so is a call made before the
  loop has built its first hierarchy.

  Asynchronous: returns `:ok` once the request is queued, or `{:error, :no_loop}`
  when no application loop could be resolved for the caller. The return says nothing
  about whether the widget was found or activated.
  """
  @spec activate_widget(widget_id()) :: :ok | {:error, :no_loop}
  def activate_widget(widget_id) do
    Drafter.AppRegistry.send_to_loop({:activate_widget, widget_id})
  end

  @doc """
  Delivers `event` and `data` to the running app's `handle_event/3`.

  `event` is the atom the app matches on and `data` its payload. This is how a modal
  or sub-screen hands a result back to the app beneath it, and how a process outside
  the loop drives the app.

  Asynchronous: returns `:ok` once the message is queued, or `{:error, :no_loop}`
  when no application loop could be resolved for the caller. A caller outside any
  session resolves the loop only when exactly one is running; see
  `Drafter.AppRegistry`.
  """
  @spec send_app_event(atom(), term()) :: :ok | {:error, :no_loop}
  def send_app_event(event, data) do
    Drafter.AppRegistry.send_to_loop({:app_event, event, data})
  end

  @doc """
  Animates one property of the widget with `widget_id` towards `end_value`.

  Returns the `reference()` identifying the animation, for `stop_animation/1`. The
  animation is started asynchronously, so the reference comes back before anything is
  known about whether the widget exists. The starting value is the widget's current
  value for the property, or the default listed below when it has none. Starting a
  second animation for the same widget and property leaves the first running.

  ## Properties

  The value in parentheses is what the animation starts from when the widget has no
  value of its own for the property.

    * `:opacity` - a float from `0.0` to `1.0` (`1.0`)
    * `:background` - an `{r, g, b}` tuple (`{0, 0, 0}`)
    * `:color` - an `{r, g, b}` tuple, the foreground (`{255, 255, 255}`)
    * `:offset_x` - horizontal offset in cells, an integer (`0`)
    * `:offset_y` - vertical offset in cells, an integer (`0`)

  Any other property atom animates from `nil`. Numbers are interpolated numerically,
  `{r, g, b}` tuples channel by channel, and any other value switches at the end of
  the duration.

  ## Options

    * `:duration` - milliseconds the animation runs. Default `300`.
    * `:easing` - one of the easing atoms below. Default `:ease_out`.
    * `:on_complete` - a zero-arity function run once the animation finishes.
      Default `nil`. Not run when the animation is stopped early.

  ## Easing functions

  `:linear`, `:ease`, `:ease_in`, `:ease_out`, `:ease_in_out`,
  `:ease_in_quad`, `:ease_out_quad`, `:ease_in_out_quad`,
  `:ease_in_cubic`, `:ease_out_cubic`, `:ease_in_out_cubic`,
  `:ease_in_elastic`, `:ease_out_elastic`,
  `:ease_in_bounce`, `:ease_out_bounce`, `:ease_in_out_bounce`,
  `:ease_in_back`, `:ease_out_back`

  `:ease` is `:ease_in_out`. Any other atom is accepted and behaves as `:linear`.

  ## Examples

      Drafter.animate(:my_button, :opacity, 0.5, duration: 500)
      Drafter.animate(:my_label, :background, {255, 0, 0}, duration: 1000, easing: :ease_out)
  """
  @spec animate(widget_id(), atom(), any(), keyword()) :: reference()
  def animate(widget_id, property, end_value, opts \\ []) do
    Drafter.Animation.animate(widget_id, property, end_value, opts)
  end

  @doc """
  Stops the animation that `animate/4` returned `animation_ref` for.

  The property keeps whatever value it had reached and the animation's
  `:on_complete` is not run. An unknown reference is ignored. Asynchronous; returns
  `:ok`.
  """
  @spec stop_animation(reference()) :: :ok
  def stop_animation(animation_ref) do
    Drafter.Animation.stop(animation_ref)
  end

  @doc """
  Stops every animation running for `widget_id`, as `stop_animation/1` does for one.
  Asynchronous; returns `:ok` whether or not that widget had any.
  """
  @spec stop_all_animations(widget_id()) :: :ok
  def stop_all_animations(widget_id) do
    Drafter.Animation.stop_all(widget_id)
  end

  @doc """
  Runs `app_module` against already-started session services, and blocks until it
  exits.

  This is the entry point the ssh and telnet transports use once they have built a
  session for a connected client. `run/2` is the entry point for a local terminal.

  `session_ctx` is a map that must carry all five of `:event_manager`,
  `:compositor`, `:screen_manager`, `:theme_manager`, and `:event_handler` as pids;
  a missing key raises `KeyError`. The calling process becomes the application loop
  and adopts those pids, so this must be a process dedicated to the session.

  `session_ctx` may also carry `:terminal_env`, a map of the connected client's
  environment as `System.get_env/0` returns. Graphics protocol detection reads it,
  so a client on a terminal that draws images gets them whatever the host's own
  terminal is. Omitting it detects from the host's environment instead.

  ## Options

    * `:props` - `map()` handed to the app's `mount/1`. Default `%{}`. A keyword list
      is accepted and converted to a map. The other keys here are not passed on as
      props.
    * `:mode` - `:isolated` (default) gives this session its own state;
      `:shared` runs it against a state server every client in the session shares,
      so input from any client re-renders all of them. Anything other than `:shared`
      is treated as `:isolated`. This is not `run/2`'s `:mode`, which selects a chart
      renderer.
    * `:shared_state` - the pid of the `Drafter.Session.SharedState` server. Default
      `nil`. Required when `:mode` is `:shared` and ignored otherwise; a `:shared`
      session without it raises.
    * `:scroll_optimization` - `boolean()`, default `true`. As in `run/2`.
    * `:refresh_rate` - frame pacing, as in `run/2`. Default: the app's
      `refresh_rate/0`, and `"30fps"` when that returns `nil`. Only `:isolated` reads
      it; a `:shared` session always runs at the app's own rate.

  `:log` and `:level` are not read here. A session always silences the console
  handler, so logs cannot corrupt a connected client's display, and writes no file.

  Returns `:ok` when the app stopped normally, `{:error, reason}` otherwise.
  """
  @spec run_session(module(), map(), keyword()) :: :ok | {:error, term()}
  def run_session(app_module, session_ctx, opts \\ []) do
    Process.put(:drafter_event_manager, session_ctx.event_manager)
    Process.put(:drafter_compositor, session_ctx.compositor)
    Process.put(:drafter_screen_manager, session_ctx.screen_manager)
    Process.put(:drafter_theme_manager, session_ctx.theme_manager)
    Process.put(:drafter_event_handler, session_ctx.event_handler)

    case Map.get(session_ctx, :terminal_env) do
      nil -> :ok
      env -> Context.put_terminal_env(env)
    end

    if Map.has_key?(session_ctx, :terminal_protocol) do
      Context.put_terminal_protocol(session_ctx.terminal_protocol)
    end

    Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)
    Drafter.ThemeManager.register_app(self())
    Drafter.ScreenManager.register_app(self())

    {mode, opts} = Keyword.pop(opts, :mode, :isolated)
    {shared_state, opts} = Keyword.pop(opts, :shared_state)
    {scroll_opt, opts} = Keyword.pop(opts, :scroll_optimization, true)
    {refresh_rate, opts} = Keyword.pop(opts, :refresh_rate)
    Process.put(:scroll_optimization, scroll_opt)

    mount_props = Runtime.mount_props(opts)
    loop_opts = if refresh_rate, do: [refresh_rate: refresh_rate], else: []

    case mode do
      :shared -> run_shared_session(app_module, mount_props, shared_state)
      _ -> run_isolated_session(app_module, mount_props, loop_opts)
    end
  end

  defp run_isolated_session(app_module, mount_props, opts) do
    _ = Drafter.Logging.setup()

    {width, height} = Compositor.get_screen_size()

    AppLoop.start(
      app_module,
      make_screen_rect(width, height),
      Keyword.put(opts, :props, mount_props)
    )
  end

  defp run_shared_session(app_module, mount_props, shared_state_pid) do
    _ = Drafter.Logging.setup()

    SharedState.subscribe(shared_state_pid)
    AppLoop.share_state_with(shared_state_pid, mount_props)

    app_state = shared_state_pid |> SharedState.get_state() |> Map.merge(mount_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)
    ready_app_state = Runtime.for_app(app_module).ready(app_module, app_state)
    {_, hierarchy} = Renderer.render_app(app_module, ready_app_state, screen_rect, hierarchy)

    AppLoop.enter_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy, [])
  end

  defp register_widget_libraries(opts) do
    Keyword.get(opts, :widget_libraries, [])
    |> Enum.each(&Drafter.Widget.Registry.register/1)

    :ok
  end

  alias Drafter.Syntax.TreeSitter

  defp maybe_start_tree_sitter(opts) do
    if Keyword.get(opts, :syntax_highlighting, false) do
      case TreeSitter.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp start_system(opts) do
    Drafter.WidgetStripCache.create()
    Drafter.Widget.Registry.scan_and_register()

    mouse_opts = [hover: Keyword.get(opts, :mouse_hover, true)]

    with {:ok, em_pid} <- ensure_started(Event.Manager.start_link()),
         {:ok, _} <- ensure_started(Terminal.Driver.start_link()),
         {:ok, comp_pid} <- ensure_started(Compositor.start_link()),
         {:ok, tm_pid} <- ensure_started(ThemeManager.start_link()),
         {:ok, eh_pid} <- ensure_started(Drafter.EventHandler.start_link()),
         {:ok, sm_pid} <- ensure_started(Drafter.ScreenManager.start_link(event_handler: eh_pid)),
         {:ok, skin_pid} <- ensure_started(SkinManager.start_link()) do
      Process.put(:drafter_event_manager, em_pid)
      Process.put(:drafter_compositor, comp_pid)
      Process.put(:drafter_theme_manager, tm_pid)
      Process.put(:drafter_screen_manager, sm_pid)
      Process.put(:drafter_event_handler, eh_pid)
      Process.put(:drafter_skin_manager, skin_pid)
      Process.put(:drafter_mouse_opts, mouse_opts)
      Terminal.Driver.setup(mouse_opts)
    end
  end

  defp app_mouse_hover(app_module) do
    Code.ensure_loaded(app_module)

    if function_exported?(app_module, :__mouse_hover__, 0) do
      app_module.__mouse_hover__()
    else
      true
    end
  end

  defp ensure_started({:ok, pid}), do: {:ok, pid}
  defp ensure_started({:error, {:already_started, pid}}), do: {:ok, pid}
  defp ensure_started(error), do: error

  defp propagate_session_pdict(session_pdict), do: Context.adopt(session_pdict)

  defp run_app(app_module, opts) do
    scroll_opt = Keyword.get(opts, :scroll_optimization, true)
    action_handlers = Drafter.ActionRegistry.collect()

    session_pdict = %{
      drafter_event_manager: Process.get(:drafter_event_manager),
      drafter_compositor: Process.get(:drafter_compositor),
      drafter_theme_manager: Process.get(:drafter_theme_manager),
      drafter_screen_manager: Process.get(:drafter_screen_manager),
      drafter_event_handler: Process.get(:drafter_event_handler),
      drafter_skin_manager: Process.get(:drafter_skin_manager)
    }

    app_pid =
      spawn_link(fn ->
        Process.put(:scroll_optimization, scroll_opt)
        propagate_session_pdict(session_pdict)
        Drafter.ActionRegistry.init(action_handlers)
        AppLoop.run(app_module, opts)
      end)

    ref = Process.monitor(app_pid)

    receive do
      {:DOWN, ^ref, :process, ^app_pid, reason} ->
        Drafter.Trace.log_sync(["Q down ", Drafter.Trace.ts(), "\n"])
        Event.Manager.drain_queue()
        Drafter.Trace.log_sync(["Q drained ", Drafter.Trace.ts(), "\n"])
        Terminal.Driver.cleanup()
        Drafter.Trace.log_sync(["Q cleanup_done ", Drafter.Trace.ts(), "\n"])
        Event.Manager.drain_queue()
        Drafter.Trace.log_sync(["Q run_returns ", Drafter.Trace.ts(), "\n"])
        if reason == :normal, do: :ok, else: {:error, reason}
    end
  end

  @doc """
  Sets the global chart rendering mode.

  `mode` must be one of `Drafter.Widget.Chart.Pixel.modes/0` — `:auto`, `:pixel`,
  `:kitty`, `:iterm2`, `:sixel`, `:braille`, `:text`. An unknown atom is ignored.
  Always returns `:ok`, so the return value does not confirm the mode was accepted.

  This is the lowest-precedence setting: a chart's own `:renderer` option overrides
  it, and the `DRAFTER_MODE` environment variable overrides both. With none of the
  three set, charts render as `:text`. `run/2`'s `:mode` option calls this before the
  app starts.

  The setting is application environment, so it is global to the VM and outlives the
  run that set it.

      iex> Drafter.render_mode(:not_a_mode)
      :ok

  """
  @spec render_mode(atom()) :: :ok
  def render_mode(mode) do
    if mode in Pixel.modes() do
      Application.put_env(:drafter, :render_mode, mode)
    end

    :ok
  end

  defp apply_clipboard_setting(opts) do
    case Keyword.fetch(opts, :clipboard) do
      {:ok, value} -> Application.put_env(:drafter, :clipboard, value)
      :error -> :ok
    end

    :ok
  end

  defp apply_render_mode(opts) do
    case Keyword.get(opts, :mode) do
      nil -> :ok
      mode -> render_mode(mode)
    end
  end

  defp maybe_halt(result, opts) do
    if Keyword.get(opts, :halt_on_exit, true) do
      Drafter.Trace.log_sync(["Q before_halt ", Drafter.Trace.ts(), "\n"])
      Drafter.Trace.stamp("halt")
      System.halt(exit_code(result))
    end

    result
  end

  defp exit_code(:ok), do: 0
  defp exit_code(_), do: 1

  defp make_screen_rect(width, height), do: %{x: 0, y: 0, width: width, height: height}
end
