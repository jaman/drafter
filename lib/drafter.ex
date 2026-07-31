defmodule Drafter do
  @moduledoc ~S"""
  An Elixir Terminal User Interface framework.

  Drafter provides a complete TUI framework with:
  - Widget-based UI components
  - Event-driven architecture  
  - Flexible layout system
  - Self-implemented drawing primitives
  - Minimal dependencies

  defmodule MyApp do
        use Drafter.App
        
        def mount(_props) do
          %{counter: 0}
        end
        
        def render(state) do
          Drafter.container([
            Drafter.label("Counter: \\#{state.counter}"),
            Drafter.button("Click me!", on_click: :increment)
          ])
        end
        
        def handle_event(:increment, state) do
          {:ok, %{state | counter: state.counter + 1}}
        end
      end
      
      Drafter.run(MyApp)
      
  """

  alias Drafter.{Compositor, Event, SkinManager, Terminal, ThemeManager}
  alias Drafter.Runtime
  alias Drafter.Runtime.{AppLoop, Renderer}
  alias Drafter.Session.Context
  alias Drafter.Session.SharedState
  alias Drafter.Widget.Chart.Pixel
  alias Drafter.WidgetHierarchy

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

  @doc """
  Flat client entry point. `use Drafter` is equivalent to `use Drafter.App` plus the
  declarative `state/1` helper, so apps need not navigate the `Drafter.App` namespace.

  Accepts the same options as `Drafter.App`, e.g. `use Drafter, runtime: :reducer`.
  """
  defmacro __using__(opts) do
    quote do
      use Drafter.App, unquote(opts)
      import Drafter, only: [state: 1]
    end
  end

  @doc "Declare the application's initial state — a flat alternative to defining `mount/1`."
  defmacro state(initial) do
    quote do
      def mount(_props), do: unquote(initial)
      defoverridable mount: 1
    end
  end

  @doc """
  Start a TUI application.

  Options:
    * `:props` - the map handed to the app's `mount/1`, `%{}` by default. The same key
      works for a nested session and for `run_session/3` behind the ssh and telnet
      transports, so an app receives the same map however it was started.
    * `:clipboard` - `true` (default) lets `Drafter.Clipboard.copy/1` write to the
      user's clipboard via OSC 52 and the local clipboard tool. `false` makes it a
      no-op returning `{:error, :disabled}`, for apps that should never touch it.
      Pasting is unaffected: that text comes from the user's own paste key.
    * `:scroll_optimization` - `true` (default) uses a fast render path during
      scroll gestures (`render_hierarchy` from ETS) and defers a full `render_app`
      until 150 ms after the last scroll event. Set to `false` to disable and
      trigger a full `render_app` on every scroll tick — maximum freshness at the
      cost of higher CPU during scroll.
    * `:syntax_highlighting` - `true` to enable tree-sitter syntax highlighting.
    * `:mode` - global chart rendering mode (`:auto`, `:pixel`, `:kitty`, `:iterm2`,
      `:sixel`, `:braille`, `:text`). The lowest-precedence layer: a per-widget
      `:renderer` overrides it, and the `DRAFTER_MODE` env var forces over both. See
      `render_mode/1`.
    * `:log` - file logging, off by default. `false` (default) silences the console
      handler so logs can't corrupt the TUI but writes no file; `true` writes to
      `drafter.log` in the current directory; a path string writes there instead.
    * `:halt_on_exit` - `true` (default) calls `System.halt/1` once the app exits,
      giving an immediate quit instead of the BEAM's graceful application shutdown
      (which can take 1-2s under `Mix.install`). Only applies to a standalone run;
      a nested session always returns to its parent. Set to `false` when embedding
      a run inside a longer-lived VM so the caller regains control instead.
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

  @doc "Create a label widget"
  @spec label(String.t(), keyword()) :: {Label, map()}
  def label(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Label, props}
  end

  @doc "Create a button widget"
  @spec button(String.t(), keyword()) :: {Button, map()}
  def button(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Button, props}
  end

  @doc "Create a container widget"
  @spec container([{module(), map()}], keyword()) :: {Container, map()}
  def container(children, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:children, children)
    {Container, props}
  end

  @doc "Create a vertical layout container"
  @spec vertical([{module(), map()}], keyword()) :: {Container, map()}
  def vertical(children, opts \\ []) do
    opts = Keyword.put(opts, :layout, :vertical)
    container(children, opts)
  end

  @doc "Create a horizontal layout container"
  @spec horizontal([{module(), map()}], keyword()) :: {Container, map()}
  def horizontal(children, opts \\ []) do
    opts = Keyword.put(opts, :layout, :horizontal)
    container(children, opts)
  end

  @doc "Create a digits widget for displaying large numbers"
  @spec digits(String.t(), keyword()) :: {Digits, map()}
  def digits(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Digits, props}
  end

  @doc "Create a grid widget for layouts"
  @spec grid([{module(), map()}], keyword()) :: {Grid, map()}
  def grid(children, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:children, children)
    {Grid, props}
  end

  @doc "Create a placeholder widget"
  @spec placeholder(String.t(), keyword()) :: {Placeholder, map()}
  def placeholder(text, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Placeholder, props}
  end

  @doc "Create a rule (divider line) widget"
  @spec rule(keyword()) :: {Rule, map()}
  def rule(opts \\ []) do
    {Rule, Map.new(opts)}
  end

  @doc "Create a markdown widget"
  @spec markdown(String.t(), keyword()) :: {Markdown, map()}
  def markdown(content, opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:content, content)
    {Markdown, props}
  end

  @doc "Create a footer widget"
  @spec footer(String.t(), keyword()) :: {Footer, map()}
  def footer(text \\ "Press 'q' to quit", opts \\ []) do
    props = opts |> Map.new() |> Map.put_new(:text, text)
    {Footer, props}
  end

  @doc """
  Set an interval timer.

  The first argument is the value, the second is the unit or timer ID.

    * `set_interval(500, :my_timer)` — fire every 500ms as `:my_timer`
    * `set_interval(24, :fps)` — fire at 24 frames/sec as `:fps`
    * `set_interval(100, :ms)` — fire every 100ms as `:ms`
    * `set_interval(500)` — fire every 500ms as `:tick`

      set_interval(24, :fps)
      set_interval(500, :poll)
  """
  @spec set_interval(pos_integer(), atom()) :: :ok
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

  @doc "Set a one-time timeout timer"
  @spec set_timeout(pos_integer(), atom()) :: :ok
  def set_timeout(timeout_ms, timer_id) do
    send(self(), {:set_timeout, timeout_ms, timer_id})
    :ok
  end

  @spec focus(term()) :: :ok
  def focus(widget_id) do
    send(self(), {:focus_widget, widget_id})
    :ok
  end

  @doc """
  Get the current value of a widget by its ID.

  Returns the primary "value" of the widget:
  - TextInput/TextArea: the text string
  - Checkbox: boolean (checked?)
  - Switch: boolean (enabled?)
  - RadioSet: the selected option ID
  - SelectionList: list of selected option IDs
  - OptionList: the selected option ID
  - Collapsible: boolean (expanded?)
  - TabbedContent: the active tab index
  - DataTable: list of selected row indices
  - Tree: list of selected node IDs

  Returns `nil` if widget not found.
  """
  @spec get_widget_value(atom()) :: term() | nil
  def get_widget_value(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> get_widget_value_via_loop(widget_id)
      pid -> extract_widget_value(Drafter.WidgetServer.get_state(pid))
    end
  end

  defp get_widget_value_via_loop(widget_id) do
    case loop_local_hierarchy() do
      :not_in_loop ->
        ask_loop({:get_widget_value, widget_id, self()}, {:widget_value, widget_id}, nil)

      nil ->
        nil

      hierarchy ->
        hierarchy |> WidgetHierarchy.get_widget_state(widget_id) |> extract_or_nil()
    end
  end

  defp extract_or_nil(nil), do: nil
  defp extract_or_nil(state), do: extract_widget_value(state)

  defp extract_widget_value(%{text: text}), do: text
  defp extract_widget_value(%{checked: checked}), do: checked
  defp extract_widget_value(%{state: s}) when s in [:on, :off], do: s == :on

  defp extract_widget_value(%{selected_index: idx, options: options}),
    do: option_id_at(options, idx)

  defp extract_widget_value(%{selected_indices: indices, options: options}) do
    indices
    |> MapSet.to_list()
    |> Enum.map(&option_id_at(options, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp extract_widget_value(%{expanded: expanded}), do: expanded
  defp extract_widget_value(%{active_tab: tab}), do: tab
  defp extract_widget_value(%{selected_rows: rows}), do: MapSet.to_list(rows)
  defp extract_widget_value(%{selected_nodes: nodes}), do: MapSet.to_list(nodes)
  defp extract_widget_value(_state), do: nil

  defp option_id_at(options, idx) do
    case Enum.at(options, idx) do
      %{id: id} -> id
      _ -> nil
    end
  end

  @doc """
  Imperatively set a widget's value by its ID.

  The counterpart to `get_widget_value/1`. The widget remains the owner of its own
  state between these calls.

  Supported widgets:

  - Text widgets (`text_area`, `text_input`): pass a string to replace the text;
    the widget reclamps its cursor and selection.
  - `checkbox`: pass a boolean.

  Returns `:ok`.

      Drafter.set_widget_value(:query_editor, "select * from quotes")
  """
  @spec set_widget_value(atom(), term()) :: :ok
  def set_widget_value(widget_id, value) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil ->
        :ok

      pid ->
        case value_to_update_props(safe_widget_state(pid), value) do
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

  defp value_to_update_props(nil, _value), do: nil
  defp value_to_update_props(%{text: _}, value) when is_binary(value), do: %{text: value}
  defp value_to_update_props(%{checked: _}, value) when is_boolean(value), do: %{checked: value}
  defp value_to_update_props(_state, _value), do: nil

  @doc """
  Get the full state of a widget by its ID.

  Returns the complete widget state struct, useful for accessing
  multiple fields or widget-specific data.

  Returns `nil` if widget not found.
  """
  @spec get_widget_state(atom()) :: struct() | nil
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
  Push data into a widget's data channel buffer.

  The widget must have been declared with `buffer:` and `refresh:` options.
  Data accumulates in the widget's RingBuffer and triggers a render only
  when the widget's throttle window opens.

      Drafter.push_data(:cpu_sparkline, 42.5)
      Drafter.push_data(:event_log, "Connection established")
  """
  @spec push_data(atom(), term()) :: :ok
  def push_data(widget_id, data) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.push_data(pid, data)
    end

    :ok
  end

  @doc """
  Push multiple data items into a widget's data channel buffer.

      Drafter.push_data_many(:cpu_sparkline, [42.5, 43.1, 41.8])
  """
  @spec push_data_many(atom(), Enumerable.t()) :: :ok
  def push_data_many(widget_id, items) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.push_data_many(pid, items)
    end

    :ok
  end

  @doc """
  Pause a widget's data channel. Data still buffers but no renders fire.
  """
  @spec pause_widget_data(atom()) :: :ok
  def pause_widget_data(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.pause_data(pid)
    end

    :ok
  end

  @doc """
  Resume a paused widget's data channel.
  """
  @spec resume_widget_data(atom()) :: :ok
  def resume_widget_data(widget_id) do
    case Drafter.WidgetPidRegistry.lookup(widget_id) do
      nil -> :ok
      pid -> Drafter.WidgetServer.resume_data(pid)
    end

    :ok
  end

  @doc """
  Switch the active rendering skin.

  The skin controls which characters `Drafter.CharacterSet` returns for every
  widget render. Built-in skins: `:graphical` (default), `:wireframe`, `:ascii`.

  Can be called from inside `handle_event/2` or `on_timer/2` — takes effect on
  the next frame.
  """
  @spec set_skin(atom()) :: :ok
  def set_skin(skin) when is_atom(skin) do
    send(self(), {:skin_change, skin})
    :ok
  end

  @doc "Switches the active theme by name."
  @spec set_theme(String.t()) :: :ok
  def set_theme(theme_name) when is_binary(theme_name) do
    Drafter.ThemeManager.set_theme(theme_name)
  end

  @doc "Returns the currently active skin atom."
  @spec current_skin() :: atom()
  def current_skin, do: Drafter.SkinManager.get_current_skin()

  @doc """
  Query a single widget by CSS-like selector.

  Selector examples:
  - "Button" - first Button widget
  - "#submit" - widget with id :submit
  - ".primary" - widget with class :primary
  - "Button.primary" - Button with class :primary

  Returns widget_id or nil if not found.
  """
  @spec query_one(String.t()) :: atom() | nil
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
  Query all widgets matching CSS-like selector.

  Returns list of widget_ids.
  """
  @spec query_all(String.t()) :: [atom()]
  def query_all(selector) do
    case loop_local_hierarchy() do
      :not_in_loop -> ask_loop({:query_all, selector, self()}, {:query_result, :all}, [])
      nil -> []
      hierarchy -> WidgetHierarchy.query_all(hierarchy, selector)
    end
  end

  @doc """
  Validate a widget's value.
  Sends :validate event to widget, triggering its validators.
  """
  @spec validate_widget(atom()) :: :ok | {:error, String.t()}
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
  Programmatically activate (press) a widget by its ID.
  """
  @spec activate_widget(atom()) :: term()
  def activate_widget(widget_id) do
    Drafter.AppRegistry.send_to_loop({:activate_widget, widget_id})
  end

  @doc """
  Send an app event to the active app loop.

  Used by modal screens and sub-screens to communicate results back to the
  parent application via `handle_event/3`.
  """
  @spec send_app_event(atom(), term()) :: term()
  def send_app_event(event, data) do
    Drafter.AppRegistry.send_to_loop({:app_event, event, data})
  end

  @doc """
  Animate a widget property.

  ## Properties

  - `:opacity` - Opacity (0.0 to 1.0)
  - `:background` - Background color (RGB tuple)
  - `:color` - Foreground color (RGB tuple)
  - `:offset_x` - X offset in cells
  - `:offset_y` - Y offset in cells

  ## Options

  - `:duration` - Animation duration in ms (default: 300)
  - `:easing` - Easing function (default: :ease_out)
  - `:on_complete` - Callback when animation finishes

  ## Easing Functions

  `:linear`, `:ease`, `:ease_in`, `:ease_out`, `:ease_in_out`,
  `:ease_in_quad`, `:ease_out_quad`, `:ease_in_out_quad`,
  `:ease_in_cubic`, `:ease_out_cubic`, `:ease_in_out_cubic`,
  `:ease_in_elastic`, `:ease_out_elastic`,
  `:ease_in_bounce`, `:ease_out_bounce`, `:ease_in_out_bounce`,
  `:ease_in_back`, `:ease_out_back`

  ## Examples

      Drafter.animate(:my_button, :opacity, 0.5, duration: 500)
      Drafter.animate(:my_label, :background, {255, 0, 0}, duration: 1000, easing: :ease_out)
  """
  @spec animate(atom(), atom(), any(), keyword()) :: reference()
  def animate(widget_id, property, end_value, opts \\ []) do
    Drafter.Animation.animate(widget_id, property, end_value, opts)
  end

  @doc """
  Stop an animation by its reference.
  """
  @spec stop_animation(reference()) :: :ok
  def stop_animation(animation_ref) do
    Drafter.Animation.stop(animation_ref)
  end

  @doc """
  Stop all animations for a widget.
  """
  @spec stop_all_animations(atom()) :: :ok
  def stop_all_animations(widget_id) do
    Drafter.Animation.stop_all(widget_id)
  end

  @doc """
  Run an app module in an isolated or shared session using pre-started session services.

  `session_ctx` must contain: `event_manager`, `compositor`, `screen_manager`,
  `theme_manager`, `event_handler` as pid values.

  Options:
    - `:mode` - `:isolated` (default) or `:shared`
    - `:shared_state` - pid of SharedState server when mode is `:shared`
    - All other opts are passed as mount props to the app module
  """
  @spec run_session(module(), map(), keyword()) :: :ok | {:error, term()}
  def run_session(app_module, session_ctx, opts \\ []) do
    Process.put(:drafter_event_manager, session_ctx.event_manager)
    Process.put(:drafter_compositor, session_ctx.compositor)
    Process.put(:drafter_screen_manager, session_ctx.screen_manager)
    Process.put(:drafter_theme_manager, session_ctx.theme_manager)
    Process.put(:drafter_event_handler, session_ctx.event_handler)

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
  Set the global chart rendering mode at runtime. Accepts any atom in
  `Drafter.Widget.Chart.Pixel.modes/0`; an unknown value is ignored. A per-widget
  `:renderer` and the `DRAFTER_MODE` env var both take precedence over this.
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
