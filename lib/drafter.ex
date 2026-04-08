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
  alias Drafter.Runtime.{AppLoop, Renderer}
  alias Drafter.Session.SharedState
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

  @scroll_debounce_ms 150

  @doc """
  Start a TUI application.

  Options:
    * `:scroll_optimization` - `true` (default) uses a fast render path during
      scroll gestures (`render_hierarchy` from ETS) and defers a full `render_app`
      until 150 ms after the last scroll event. Set to `false` to disable and
      trigger a full `render_app` on every scroll tick — maximum freshness at the
      cost of higher CPU during scroll.
    * `:syntax_highlighting` - `true` to enable tree-sitter syntax highlighting.
  """
  @spec run(module(), keyword()) :: :ok
  def run(app_module, opts \\ []) when is_atom(app_module) do
    case Drafter.AppRegistry.whereis() do
      nil ->
        _ = Drafter.Logging.setup()

        mouse_hover = app_mouse_hover(app_module)

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

  The first argument specifies the rate — accepts:
    * integer milliseconds: `set_interval(500)` or `set_interval(500, :my_timer)`
    * fps string: `set_interval("24fps")` or `set_interval("24fps", :my_timer)`
    * fps atom shorthand: `set_interval(24, :fps)` (legacy, equivalent to `"24fps"`)

  The optional second argument is the timer ID used in `on_timer/2`.
  Defaults to `:tick` when omitted or when a unit atom (`:fps`, `:ms`) is given.

      set_interval("30fps")
      set_interval(500, :poll)
      set_interval("10fps", :animation)
  """
  @spec set_interval(pos_integer() | String.t(), atom()) :: :ok
  def set_interval(rate, timer_id \\ :tick)

  def set_interval(rate, timer_id) when is_binary(rate) do
    do_set_interval(parse_rate(rate), timer_id)
  end

  def set_interval(value, :fps) do
    do_set_interval(round(1000 / value), :tick)
  end

  def set_interval(value, :ms) do
    do_set_interval(value, :tick)
  end

  def set_interval(value, timer_id) when is_integer(value) do
    do_set_interval(value, timer_id)
  end

  defp do_set_interval(interval_ms, timer_id) do
    case Process.get(:pending_intervals) do
      nil -> send(self(), {:set_interval, interval_ms, timer_id})
      pending -> Process.put(:pending_intervals, [{interval_ms, timer_id} | pending])
    end

    :ok
  end

  defp parse_rate(s) when is_binary(s) do
    cond do
      Regex.match?(~r/^\d+(\.\d+)?\s*fps$/i, s) ->
        [fps_str] = Regex.run(~r/[\d.]+/, s)

        fps =
          if String.contains?(fps_str, "."),
            do: String.to_float(fps_str),
            else: String.to_integer(fps_str)

        round(1000 / fps)

      Regex.match?(~r/^\d+(\.\d+)?\s*ms$/i, s) ->
        [ms_str] = Regex.run(~r/[\d.]+/, s)

        if String.contains?(ms_str, "."),
          do: round(String.to_float(ms_str)),
          else: String.to_integer(ms_str)

      true ->
        raise ArgumentError, "invalid interval rate: #{inspect(s)}. Use integer ms, \"24fps\", or \"500ms\""
    end
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
    Drafter.AppRegistry.send_to_loop({:get_widget_value, widget_id, self()})

    receive do
      {:widget_value, ^widget_id, value} -> value
    after
      100 -> nil
    end
  end

  @doc """
  Get the full state of a widget by its ID.

  Returns the complete widget state struct, useful for accessing
  multiple fields or widget-specific data.

  Returns `nil` if widget not found.
  """
  @spec get_widget_state(atom()) :: struct() | nil
  def get_widget_state(widget_id) do
    Drafter.AppRegistry.send_to_loop({:get_widget_state, widget_id, self()})

    receive do
      {:widget_state, ^widget_id, state} -> state
    after
      100 -> nil
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
    Drafter.AppRegistry.send_to_loop({:query_one, selector, self()})

    receive do
      {:query_result, :one, result} -> result
    after
      100 -> nil
    end
  end

  @doc """
  Query all widgets matching CSS-like selector.

  Returns list of widget_ids.
  """
  @spec query_all(String.t()) :: [atom()]
  def query_all(selector) do
    Drafter.AppRegistry.send_to_loop({:query_all, selector, self()})

    receive do
      {:query_result, :all, result} -> result
    after
      100 -> []
    end
  end

  @doc """
  Validate a widget's value.
  Sends :validate event to widget, triggering its validators.
  """
  @spec validate_widget(atom()) :: :ok | {:error, String.t()}
  def validate_widget(widget_id) do
    Drafter.AppRegistry.send_to_loop({:validate_widget, widget_id, self()})

    receive do
      {:validation_result, ^widget_id, result} -> result
    after
      100 -> :ok
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

    mount_props = Map.new(opts)
    loop_opts = if refresh_rate, do: [refresh_rate: refresh_rate], else: []

    case mode do
      :shared -> run_shared_session(app_module, mount_props, shared_state)
      _ -> run_isolated_session(app_module, mount_props, loop_opts)
    end
  end

  defp run_isolated_session(app_module, mount_props, opts) do
    _ = Drafter.Logging.setup()

    app_state = app_module.mount(mount_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)

    ready_app_state = app_module.on_ready(app_state)
    {_, hierarchy} = Renderer.render_app(app_module, ready_app_state, screen_rect, hierarchy)

    AppLoop.enter_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy, opts)
  end

  defp run_shared_session(app_module, mount_props, shared_state_pid) do
    _ = Drafter.Logging.setup()

    SharedState.subscribe(shared_state_pid)

    app_state = SharedState.get_state(shared_state_pid)
    app_state = Map.merge(app_state, mount_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)

    ready_app_state =
      if function_exported?(app_module, :on_ready, 1) do
        app_module.on_ready(app_state)
      else
        app_state
      end

    shared_session_loop(
      app_module,
      ready_app_state,
      screen_rect,
      %{},
      hierarchy,
      shared_state_pid,
      mount_props,
      %{}
    )
  end

  defp shared_session_loop(
         app_module,
         app_state,
         screen_rect,
         timers,
         widget_hierarchy,
         shared_state_pid,
         mount_props,
         local_bindings
       ) do
    receive do
      {:tui_event, {:resize, {width, height}}} ->
        new_screen_rect = make_screen_rect(width, height)
        {_, new_hierarchy} = Renderer.render_app(app_module, app_state, new_screen_rect, widget_hierarchy)

        shared_session_loop(
          app_module,
          app_state,
          new_screen_rect,
          timers,
          new_hierarchy,
          shared_state_pid,
          mount_props,
          local_bindings
        )

      {:tui_event, event} ->
        case check_global_quit(event) do
          :quit ->
            cleanup_timers(timers)
            WidgetHierarchy.stop_all_servers(widget_hierarchy)
            :ok

          :continue ->
            ctx = %{
              app_module: app_module,
              screen_rect: screen_rect,
              timers: timers,
              shared_state_pid: shared_state_pid,
              mount_props: mount_props
            }

            handle_shared_tui_event(ctx, event, app_state, widget_hierarchy, local_bindings)
        end

      {:bound_state_update, key, value} ->
        new_bindings = Map.put(local_bindings, key, value)
        new_app_state = Map.put(app_state, key, value)
        {_, new_hierarchy} = Renderer.render_app(app_module, new_app_state, screen_rect, widget_hierarchy)

        shared_session_loop(
          app_module,
          new_app_state,
          screen_rect,
          timers,
          new_hierarchy,
          shared_state_pid,
          mount_props,
          new_bindings
        )

      {:app_event, callback, data} ->
        {new_state, new_hier} =
          dispatch_shared_callback(
            app_module,
            callback,
            data,
            app_state,
            shared_state_pid,
            widget_hierarchy,
            screen_rect
          )

        {_, final_hier} = Renderer.render_app(app_module, new_state, screen_rect, new_hier)

        shared_session_loop(
          app_module,
          new_state,
          screen_rect,
          timers,
          final_hier,
          shared_state_pid,
          mount_props,
          local_bindings
        )

      {:shared_state_updated, new_state} ->
        merged_state = Map.merge(new_state, mount_props)
        {_, new_hierarchy} = Renderer.render_app(app_module, merged_state, screen_rect, widget_hierarchy)

        shared_session_loop(
          app_module,
          merged_state,
          screen_rect,
          timers,
          new_hierarchy,
          shared_state_pid,
          mount_props,
          %{}
        )

      {:focus_widget, widget_id} ->
        new_hierarchy =
          if widget_hierarchy do
            WidgetHierarchy.focus_widget(widget_hierarchy, widget_id)
          else
            widget_hierarchy
          end

        {_, updated_hierarchy} = Renderer.render_app(app_module, app_state, screen_rect, new_hierarchy)

        shared_session_loop(
          app_module,
          app_state,
          screen_rect,
          timers,
          updated_hierarchy,
          shared_state_pid,
          mount_props,
          local_bindings
        )

      {:set_interval, interval_ms, timer_id} ->
        timer_ref = :timer.send_interval(interval_ms, {:timer, timer_id})
        new_timers = Map.put(timers, timer_id, timer_ref)

        shared_session_loop(
          app_module,
          app_state,
          screen_rect,
          new_timers,
          widget_hierarchy,
          shared_state_pid,
          mount_props,
          local_bindings
        )

      {:set_timeout, timeout_ms, timer_id} ->
        Process.send_after(self(), {:timer, timer_id}, timeout_ms)

        shared_session_loop(
          app_module,
          app_state,
          screen_rect,
          timers,
          widget_hierarchy,
          shared_state_pid,
          mount_props,
          local_bindings
        )

      {:timer, timer_id} ->
        new_app_state =
          if function_exported?(app_module, :on_timer, 2) do
            app_module.on_timer(timer_id, app_state)
          else
            app_state
          end

        if new_app_state === app_state do
          shared_session_loop(
            app_module,
            app_state,
            screen_rect,
            timers,
            widget_hierarchy,
            shared_state_pid,
            mount_props,
            local_bindings
          )
        else
          {_, new_hierarchy} =
            Renderer.render_app(app_module, new_app_state, screen_rect, widget_hierarchy)

          shared_session_loop(
            app_module,
            new_app_state,
            screen_rect,
            timers,
            new_hierarchy,
            shared_state_pid,
            mount_props,
            local_bindings
          )
        end

      :scroll_debounce_render ->
        drain_scroll_debounce_renders()
        Process.delete(:scroll_debounce_ref)
        idle_app_state = maybe_scroll_idle(app_module, app_state)

        if widget_hierarchy do
          {_, updated_hierarchy} =
            Renderer.render_app(app_module, idle_app_state, screen_rect, widget_hierarchy)

          shared_session_loop(
            app_module,
            idle_app_state,
            screen_rect,
            timers,
            updated_hierarchy,
            shared_state_pid,
            mount_props,
            local_bindings
          )
        else
          shared_session_loop(
            app_module,
            idle_app_state,
            screen_rect,
            timers,
            widget_hierarchy,
            shared_state_pid,
            mount_props,
            local_bindings
          )
        end

      other ->
        new_app_state = maybe_on_message(app_module, other, app_state)

        shared_session_loop(
          app_module,
          new_app_state,
          screen_rect,
          timers,
          widget_hierarchy,
          shared_state_pid,
          mount_props,
          local_bindings
        )
    end
  end

  defp handle_shared_tui_event(ctx, event, app_state, widget_hierarchy, local_bindings) do
    {new_hierarchy, actions, widget_consumed} = dispatch_widget_event(widget_hierarchy, event)

    updated_hierarchy = maybe_update_sizes(new_hierarchy, actions)
    {flushed_state, flushed_bindings} = drain_bound_updates(app_state, local_bindings)

    {new_app_state, new_bindings, final_hierarchy} =
      process_shared_actions(
        ctx,
        actions,
        flushed_state,
        flushed_bindings,
        updated_hierarchy
      )

    if widget_consumed do
      handle_widget_consumed(
        ctx,
        event,
        actions,
        new_app_state,
        final_hierarchy,
        new_bindings
      )
    else
      handle_widget_not_consumed(ctx, event, new_app_state, updated_hierarchy, new_bindings)
    end
  end

  defp dispatch_widget_event(widget_hierarchy, event) do
    if widget_hierarchy && widget_hierarchy.focused_widget do
      WidgetHierarchy.handle_event_consumed(widget_hierarchy, event)
    else
      {widget_hierarchy, [], false}
    end
  end

  defp maybe_update_sizes(hierarchy, actions) do
    {needs_layout, _direction} = Drafter.RenderCache.extract_layout_impact(actions)

    if needs_layout do
      Renderer.update_hierarchy_preferred_sizes(hierarchy)
    else
      hierarchy
    end
  end

  defp process_shared_actions(ctx, actions, app_state, bindings, hierarchy) do
    Enum.reduce(actions, {app_state, bindings, hierarchy}, fn
      {:app_callback, callback, data}, {acc_state, acc_bindings, acc_hier} ->
        {result_state, result_hier} =
          dispatch_shared_callback(
            ctx.app_module,
            callback,
            data,
            acc_state,
            ctx.shared_state_pid,
            acc_hier,
            ctx.screen_rect
          )

        {result_state, acc_bindings, result_hier}

      _, acc ->
        acc
    end)
  end

  defp handle_widget_consumed(ctx, _event, actions, app_state, hierarchy, bindings) do
    %{app_module: app_module, screen_rect: screen_rect, timers: timers} = ctx
    %{shared_state_pid: shared_state_pid, mount_props: mount_props} = ctx

    if :scroll_fast_render in actions and scroll_optimization_enabled?() do
      scrolled_state = maybe_scroll_active(app_module, app_state)
      Renderer.render_hierarchy(hierarchy, screen_rect)
      reschedule_scroll_debounce()

      shared_session_loop(
        app_module, scrolled_state, screen_rect, timers,
        hierarchy, shared_state_pid, mount_props, bindings
      )
    else
      {_, final_hierarchy} = Renderer.render_app(app_module, app_state, screen_rect, hierarchy)

      shared_session_loop(
        app_module, app_state, screen_rect, timers,
        final_hierarchy, shared_state_pid, mount_props, bindings
      )
    end
  end

  defp handle_widget_not_consumed(ctx, event, app_state, updated_hierarchy, bindings) do
    %{app_module: app_module, screen_rect: screen_rect, timers: timers} = ctx
    %{shared_state_pid: shared_state_pid, mount_props: mount_props} = ctx

    {result_state, should_stop} = handle_shared_event(app_module, event, app_state, shared_state_pid)

    if should_stop do
      cleanup_timers(timers)
      :ok
    else
      {nav_hierarchy, _nav_actions} = WidgetHierarchy.handle_event(updated_hierarchy, event)
      {_, final_hierarchy} = Renderer.render_app(app_module, result_state, screen_rect, nav_hierarchy)

      shared_session_loop(
        app_module, result_state, screen_rect, timers,
        final_hierarchy, shared_state_pid, mount_props, bindings
      )
    end
  end

  defp handle_shared_event(app_module, event, app_state, shared_state_pid) do
    result =
      if function_exported?(app_module, :handle_event, 2) do
        app_module.handle_event(event, app_state)
      else
        {:noreply, app_state}
      end

    case result do
      {:ok, new_state} ->
        SharedState.update_state(shared_state_pid, new_state)
        {new_state, false}

      {:stop, _reason} ->
        {app_state, true}

      _ ->
        {app_state, false}
    end
  end

  defp dispatch_shared_callback(
         app_module,
         callback,
         data,
         app_state,
         shared_state_pid,
         hierarchy,
         _screen_rect
       ) do
    result =
      if function_exported?(app_module, :handle_event, 3) do
        app_module.handle_event(callback, data, app_state)
      else
        {:noreply, app_state}
      end

    case result do
      {:ok, new_state} ->
        SharedState.update_state(shared_state_pid, new_state)
        {new_state, hierarchy}

      _ ->
        {app_state, hierarchy}
    end
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

  defp propagate_session_pdict(session_pdict) do
    Enum.each(session_pdict, fn
      {key, val} when val != nil -> Process.put(key, val)
      _ -> :ok
    end)
  end

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
        Event.Manager.drain_queue()
        Terminal.Driver.cleanup()
        Event.Manager.drain_queue()
        if reason == :normal, do: :ok, else: {:error, reason}
    end
  end

  defp make_screen_rect(width, height), do: %{x: 0, y: 0, width: width, height: height}

  defp check_global_quit(event) do
    case event do
      %{type: :key, key: :q, modifiers: [:ctrl]} -> :quit
      {:key, :q, [:ctrl]} -> :quit
      %{type: :key, key: :c, modifiers: [:ctrl]} -> :quit
      {:key, :c, [:ctrl]} -> :quit
      _ -> :continue
    end
  end

  defp cleanup_timers(timers) do
    Enum.each(timers, fn {_id, timer_ref} -> :timer.cancel(timer_ref) end)
  end

  defp drain_bound_updates(app_state, bindings) do
    receive do
      {:bound_state_update, key, value} ->
        drain_bound_updates(Map.put(app_state, key, value), Map.put(bindings, key, value))
    after
      0 -> {app_state, bindings}
    end
  end

  defp maybe_scroll_active(app_module, app_state) do
    if Process.get(:scroll_gesture_active) do
      app_state
    else
      Process.put(:scroll_gesture_active, true)

      if function_exported?(app_module, :on_scroll_active, 1) do
        app_module.on_scroll_active(app_state)
      else
        app_state
      end
    end
  end

  defp maybe_scroll_idle(app_module, app_state) do
    Process.delete(:scroll_gesture_active)

    if function_exported?(app_module, :on_scroll_idle, 1) do
      app_module.on_scroll_idle(app_state)
    else
      app_state
    end
  end

  defp reschedule_scroll_debounce do
    case Process.get(:scroll_debounce_ref) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    new_ref = Process.send_after(self(), :scroll_debounce_render, @scroll_debounce_ms)
    Process.put(:scroll_debounce_ref, new_ref)
  end

  defp drain_scroll_debounce_renders do
    receive do
      :scroll_debounce_render -> drain_scroll_debounce_renders()
    after
      0 -> :ok
    end
  end

  defp scroll_optimization_enabled?, do: Process.get(:scroll_optimization, true) != false

  defp maybe_on_message(app_module, msg, app_state) do
    if function_exported?(app_module, :on_message, 2) do
      app_module.on_message(msg, app_state)
    else
      app_state
    end
  end
end
