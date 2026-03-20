defmodule Drafter do
  @moduledoc ~S"""
  An Elixir Terminal User Interface framework.

  Drafter provides a complete TUI framework with:
  - Widget-based UI components
  - Event-driven architecture  
  - Flexible layout system
  - Self-implemented drawing primitives
  - Zero external dependencies

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

  alias Drafter.{Terminal, Event, Compositor, ComponentRenderer, ThemeManager}
  alias Drafter.Widget.{Label, Button, Container, Digits, Grid, Placeholder, Markdown, Footer, Rule}

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
    # Initialize file logging for debugging
    _ = Drafter.Logging.setup()

    with :ok <- start_system(),
         :ok <- maybe_start_tree_sitter(opts),
         :ok <- run_app(app_module, opts) do
      :ok
    else
      {:error, reason} ->
        IO.puts("Failed to start TUI application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Create a label widget"
  @spec label(String.t(), keyword()) :: {Label, map()}
  def label(text, opts \\ []) do
    props = %{text: text} |> Map.merge(Map.new(opts))
    {Label, props}
  end

  @doc "Create a button widget"
  @spec button(String.t(), keyword()) :: {Button, map()}
  def button(text, opts \\ []) do
    props = %{text: text} |> Map.merge(Map.new(opts))
    {Button, props}
  end

  @doc "Create a container widget"
  @spec container([{module(), map()}], keyword()) :: {Container, map()}
  def container(children, opts \\ []) do
    props = %{children: children} |> Map.merge(Map.new(opts))
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
    props = %{text: text} |> Map.merge(Map.new(opts))
    {Digits, props}
  end

  @doc "Create a grid widget for layouts"
  @spec grid([{module(), map()}], keyword()) :: {Grid, map()}
  def grid(children, opts \\ []) do
    props = %{children: children} |> Map.merge(Map.new(opts))
    {Grid, props}
  end

  @doc "Create a placeholder widget"
  @spec placeholder(String.t(), keyword()) :: {Placeholder, map()}
  def placeholder(text, opts \\ []) do
    props = %{text: text} |> Map.merge(Map.new(opts))
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
    props = %{content: content} |> Map.merge(Map.new(opts))
    {Markdown, props}
  end

  @doc "Create a footer widget"
  @spec footer(String.t(), keyword()) :: {Footer, map()}
  def footer(text \\ "Press 'q' to quit", opts \\ []) do
    props = %{text: text} |> Map.merge(Map.new(opts))
    {Footer, props}
  end

  @doc "Set an interval timer"
  @spec set_interval(pos_integer(), atom()) :: :ok
  def set_interval(interval_ms, timer_id) do
    send(self(), {:set_interval, interval_ms, timer_id})
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
    send(:tui_app_loop, {:get_widget_value, widget_id, self()})

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
    send(:tui_app_loop, {:get_widget_state, widget_id, self()})

    receive do
      {:widget_state, ^widget_id, state} -> state
    after
      100 -> nil
    end
  end

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
    send(:tui_app_loop, {:query_one, selector, self()})

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
    send(:tui_app_loop, {:query_all, selector, self()})

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
    send(:tui_app_loop, {:validate_widget, widget_id, self()})

    receive do
      {:validation_result, ^widget_id, result} -> result
    after
      100 -> :ok
    end
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

    Drafter.Event.Manager.subscribe_to(session_ctx.event_manager, self(), :all)
    Drafter.ThemeManager.register_app(self())
    Drafter.ScreenManager.register_app(self())

    {mode, opts} = Keyword.pop(opts, :mode, :isolated)
    {shared_state, opts} = Keyword.pop(opts, :shared_state)
    {scroll_opt, opts} = Keyword.pop(opts, :scroll_optimization, true)
    Process.put(:scroll_optimization, scroll_opt)

    mount_props = Map.new(opts)

    case mode do
      :shared -> run_shared_session(app_module, mount_props, shared_state)
      _ -> run_isolated_session(app_module, mount_props)
    end
  end

  defp run_isolated_session(app_module, mount_props) do
    _ = Drafter.Logging.setup()

    app_state = app_module.mount(mount_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = render_app(app_module, app_state, screen_rect)

    ready_app_state = app_module.on_ready(app_state)
    {_, hierarchy} = render_app(app_module, ready_app_state, screen_rect, hierarchy)

    app_event_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy)
  end

  defp run_shared_session(app_module, mount_props, shared_state_pid) do
    _ = Drafter.Logging.setup()

    topic = Drafter.Session.SharedState.pubsub_topic(shared_state_pid)
    Phoenix.PubSub.subscribe(Drafter.PubSub, topic)

    app_state = Drafter.Session.SharedState.get_state(shared_state_pid)
    app_state = Map.merge(app_state, mount_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = render_app(app_module, app_state, screen_rect)

    ready_app_state =
      if function_exported?(app_module, :on_ready, 1) do
        app_module.on_ready(app_state)
      else
        app_state
      end

    shared_session_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy, shared_state_pid, mount_props, %{})
  end

  defp shared_session_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, shared_state_pid, mount_props, local_bindings) do
    receive do
      {:tui_event, {:resize, {width, height}}} ->
        new_screen_rect = make_screen_rect(width, height)
        {_, new_hierarchy} = render_app(app_module, app_state, new_screen_rect, widget_hierarchy)
        shared_session_loop(app_module, app_state, new_screen_rect, timers, new_hierarchy, shared_state_pid, mount_props, local_bindings)

      {:tui_event, event} ->
        case check_global_quit(event) do
          :quit ->
            cleanup_timers(timers)
            Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
            :ok

          :continue ->
            {new_hierarchy, actions, widget_consumed} =
              if widget_hierarchy && widget_hierarchy.focused_widget do
                Drafter.WidgetHierarchy.handle_event_consumed(widget_hierarchy, event)
              else
                {widget_hierarchy, [], false}
              end

            updated_hierarchy =
              if Enum.member?(actions, :widget_layout_needed) do
                update_hierarchy_preferred_sizes(new_hierarchy)
              else
                new_hierarchy
              end

            {flushed_state, flushed_bindings} = drain_bound_updates(app_state, local_bindings)

            {new_app_state, new_bindings, new_hierarchy_after_callbacks} =
              Enum.reduce(actions, {flushed_state, flushed_bindings, updated_hierarchy}, fn
                {:app_callback, callback, data}, {acc_state, acc_bindings, acc_hier} ->
                  {result_state, result_hier} =
                    dispatch_shared_callback(app_module, callback, data, acc_state, shared_state_pid, acc_hier, screen_rect)
                  {result_state, acc_bindings, result_hier}

                _, acc ->
                  acc
              end)

            if widget_consumed do
              if :scroll_fast_render in actions and scroll_optimization_enabled?() do
                scrolled_app_state = maybe_scroll_active(app_module, new_app_state)
                render_hierarchy(new_hierarchy_after_callbacks, screen_rect)
                reschedule_scroll_debounce()
                shared_session_loop(app_module, scrolled_app_state, screen_rect, timers, new_hierarchy_after_callbacks, shared_state_pid, mount_props, new_bindings)
              else
                {_, final_hierarchy} = render_app(app_module, new_app_state, screen_rect, new_hierarchy_after_callbacks)
                shared_session_loop(app_module, new_app_state, screen_rect, timers, final_hierarchy, shared_state_pid, mount_props, new_bindings)
              end
            else
              {result_state, should_stop} = handle_shared_event(app_module, event, new_app_state, shared_state_pid)

              if should_stop do
                cleanup_timers(timers)
                :ok
              else
                {nav_hierarchy, _nav_actions} = Drafter.WidgetHierarchy.handle_event(updated_hierarchy, event)
                {_, final_hierarchy} = render_app(app_module, result_state, screen_rect, nav_hierarchy)
                shared_session_loop(app_module, result_state, screen_rect, timers, final_hierarchy, shared_state_pid, mount_props, new_bindings)
              end
            end
        end

      {:bound_state_update, key, value} ->
        new_bindings = Map.put(local_bindings, key, value)
        new_app_state = Map.put(app_state, key, value)
        {_, new_hierarchy} = render_app(app_module, new_app_state, screen_rect, widget_hierarchy)
        shared_session_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy, shared_state_pid, mount_props, new_bindings)

      {:app_event, callback, data} ->
        {new_state, new_hier} =
          dispatch_shared_callback(app_module, callback, data, app_state, shared_state_pid, widget_hierarchy, screen_rect)
        {_, final_hier} = render_app(app_module, new_state, screen_rect, new_hier)
        shared_session_loop(app_module, new_state, screen_rect, timers, final_hier, shared_state_pid, mount_props, local_bindings)

      {:shared_state_updated, new_state} ->
        merged_state = Map.merge(new_state, mount_props)
        {_, new_hierarchy} = render_app(app_module, merged_state, screen_rect, widget_hierarchy)
        shared_session_loop(app_module, merged_state, screen_rect, timers, new_hierarchy, shared_state_pid, mount_props, %{})

      {:focus_widget, widget_id} ->
        new_hierarchy =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.focus_widget(widget_hierarchy, widget_id)
          else
            widget_hierarchy
          end

        {_, updated_hierarchy} = render_app(app_module, app_state, screen_rect, new_hierarchy)
        shared_session_loop(app_module, app_state, screen_rect, timers, updated_hierarchy, shared_state_pid, mount_props, local_bindings)

      {:set_interval, interval_ms, timer_id} ->
        timer_ref = :timer.send_interval(interval_ms, {:timer, timer_id})
        new_timers = Map.put(timers, timer_id, timer_ref)
        shared_session_loop(app_module, app_state, screen_rect, new_timers, widget_hierarchy, shared_state_pid, mount_props, local_bindings)

      {:set_timeout, timeout_ms, timer_id} ->
        Process.send_after(self(), {:timer, timer_id}, timeout_ms)
        shared_session_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, shared_state_pid, mount_props, local_bindings)

      {:timer, timer_id} ->
        new_app_state =
          if function_exported?(app_module, :on_timer, 2) do
            app_module.on_timer(timer_id, app_state)
          else
            app_state
          end

        if new_app_state === app_state do
          shared_session_loop(app_module, app_state, screen_rect, timers, widget_hierarchy, shared_state_pid, mount_props, local_bindings)
        else
          {_, new_hierarchy} = render_app(app_module, new_app_state, screen_rect, widget_hierarchy)
          shared_session_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy, shared_state_pid, mount_props, local_bindings)
        end

      :scroll_debounce_render ->
        drain_scroll_debounce_renders()
        Process.delete(:scroll_debounce_ref)
        idle_app_state = maybe_scroll_idle(app_module, app_state)

        if widget_hierarchy do
          {_, updated_hierarchy} = render_app(app_module, idle_app_state, screen_rect, widget_hierarchy)
          shared_session_loop(app_module, idle_app_state, screen_rect, timers, updated_hierarchy, shared_state_pid, mount_props, local_bindings)
        else
          shared_session_loop(app_module, idle_app_state, screen_rect, timers, widget_hierarchy, shared_state_pid, mount_props, local_bindings)
        end

      other ->
        new_app_state = maybe_on_message(app_module, other, app_state)
        shared_session_loop(app_module, new_app_state, screen_rect, timers, widget_hierarchy, shared_state_pid, mount_props, local_bindings)
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
        Drafter.Session.SharedState.update_state(shared_state_pid, new_state)
        {new_state, false}

      {:stop, _reason} ->
        {app_state, true}

      _ ->
        {app_state, false}
    end
  end

  defp dispatch_shared_callback(app_module, callback, data, app_state, shared_state_pid, hierarchy, _screen_rect) do
    result =
      if function_exported?(app_module, :handle_event, 3) do
        app_module.handle_event(callback, data, app_state)
      else
        {:noreply, app_state}
      end

    case result do
      {:ok, new_state} ->
        Drafter.Session.SharedState.update_state(shared_state_pid, new_state)
        {new_state, hierarchy}

      _ ->
        {app_state, hierarchy}
    end
  end


  defp maybe_start_tree_sitter(opts) do
    if Keyword.get(opts, :syntax_highlighting, false) do
      case Drafter.Syntax.TreeSitterDaemon.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp start_system() do
    Drafter.WidgetStripCache.create()

    with {:ok, _} <- ensure_started(Event.Manager.start_link()),
         {:ok, _} <- ensure_started(Terminal.Driver.start_link()),
         {:ok, _} <- ensure_started(Compositor.start_link()),
         {:ok, _} <- ensure_started(ThemeManager.start_link()),
         :ok <- Terminal.Driver.setup() do
      :ok
    end
  end

  defp ensure_started({:ok, pid}), do: {:ok, pid}
  defp ensure_started({:error, {:already_started, pid}}), do: {:ok, pid}
  defp ensure_started(error), do: error

  defp run_app(app_module, opts) do
    scroll_opt = Keyword.get(opts, :scroll_optimization, true)

    app_pid =
      spawn_link(fn ->
        Process.put(:scroll_optimization, scroll_opt)
        run_app_loop(app_module)
      end)

    Event.Manager.subscribe(app_pid)

    ref = Process.monitor(app_pid)

    receive do
      {:DOWN, ^ref, :process, ^app_pid, reason} ->
        Terminal.Driver.cleanup()
        if reason == :normal, do: :ok, else: {:error, reason}
    end
  end

  defp run_app_loop(app_module) do
    Process.register(self(), :tui_app_loop)

    ThemeManager.register_app(self())
    Drafter.ScreenManager.register_app(self())
    Compositor.clear_screen()
    drain_stale_events()

    initial_props = %{}
    app_state = app_module.mount(initial_props)

    {width, height} = Compositor.get_screen_size()
    screen_rect = make_screen_rect(width, height)

    {_, hierarchy} = render_app(app_module, app_state, screen_rect)

    ready_app_state = app_module.on_ready(app_state)
    {_, hierarchy} = render_app(app_module, ready_app_state, screen_rect, hierarchy)

    app_event_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy)
  end

  defp app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy) do
    receive do
      {:tui_event, {:resize, {width, height}}} ->
        new_screen_rect = make_screen_rect(width, height)
        {_, new_hierarchy} = render_app(app_module, app_state, new_screen_rect, widget_hierarchy)
        app_event_loop(app_module, app_state, new_screen_rect, timers, new_hierarchy)

      {:tui_event, event} ->
        case check_global_quit(event) do
          :quit ->
            cleanup_timers(timers)
            :ok

          :continue ->
            has_screens = length(Drafter.ScreenManager.get_all_screens()) > 0

            if has_screens do
              Drafter.EventHandler.dispatch_event_sync(event)

              if Drafter.ScreenManager.get_all_screens() == [] do
                {_, fresh_hierarchy} = render_app(app_module, app_state, screen_rect, widget_hierarchy)
                app_event_loop(app_module, app_state, screen_rect, timers, fresh_hierarchy)
              else
                render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
              end
            else
              {new_hierarchy, actions, widget_consumed} =
                if widget_hierarchy && widget_hierarchy.focused_widget do
                  Drafter.WidgetHierarchy.handle_event_consumed(widget_hierarchy, event)
                else
                  {widget_hierarchy, [], false}
                end

              if widget_consumed do
                updated_hierarchy =
                  if Enum.member?(actions, :widget_layout_needed) do
                    update_hierarchy_preferred_sizes(new_hierarchy)
                  else
                    new_hierarchy
                  end

                new_app_state =
                  Enum.reduce(actions, app_state, fn
                    {:app_callback, callback, data}, acc_state ->
                      dispatch_app_callback(app_module, callback, data, acc_state)
                    _, acc_state -> acc_state
                  end)

                if :scroll_fast_render in actions and scroll_optimization_enabled?() do
                  scrolled_app_state = maybe_scroll_active(app_module, new_app_state)
                  render_hierarchy(updated_hierarchy, screen_rect)
                  reschedule_scroll_debounce()
                  app_event_loop(app_module, scrolled_app_state, screen_rect, timers, updated_hierarchy)
                else
                  {_, final_hierarchy} =
                    render_app(app_module, new_app_state, screen_rect, updated_hierarchy)

                  app_event_loop(app_module, new_app_state, screen_rect, timers, final_hierarchy)
                end
              else
                case app_module.handle_event(event, app_state) do
                  {:ok, new_app_state} ->
                    {_, updated_hierarchy} =
                      render_app(app_module, new_app_state, screen_rect, widget_hierarchy)

                    app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy)

                  {:stop, reason} ->
                    cleanup_timers(timers)
                    Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
                    if reason == :normal, do: :ok, else: {:error, reason}

                  {:error, _reason} ->
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

                  {:show_modal, screen_module, props, opts} ->
                    Drafter.ScreenManager.show_modal(screen_module, props, opts)
                    render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

                  {:show_toast, message, opts} ->
                    Drafter.ScreenManager.show_toast(message, opts)
                    render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

                  {:push, screen_module, props, opts} ->
                    Drafter.ScreenManager.push(screen_module, props, opts)
                    render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

                  {:replace, screen_module, props, opts} ->
                    Drafter.ScreenManager.replace(screen_module, props, opts)
                    render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

                  {:pop, result} ->
                    Drafter.ScreenManager.pop(result)
                    render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
                    app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

                  {:noreply, app_state} ->
                    {new_hierarchy, widget_handled, needs_rerender, actions} =
                      if widget_hierarchy do
                        case Drafter.WidgetHierarchy.handle_event(widget_hierarchy, event) do
                          {hierarchy, []} ->
                            hierarchy_changed =
                              hierarchy.focused_widget != widget_hierarchy.focused_widget

                            {hierarchy, hierarchy_changed, hierarchy_changed, []}

                          {hierarchy, actions} ->
                            {hierarchy, true, true, actions}
                        end
                      else
                        {widget_hierarchy, false, false, []}
                      end

                    updated_hierarchy =
                      if Enum.member?(actions, :widget_layout_needed) do
                        update_hierarchy_preferred_sizes(new_hierarchy)
                      else
                        new_hierarchy
                      end

                    new_app_state =
                      Enum.reduce(actions, app_state, fn
                        {:app_callback, callback, data}, acc_state ->
                          dispatch_app_callback(app_module, callback, data, acc_state)
                        _, acc_state -> acc_state
                      end)

                    if needs_rerender or widget_handled do
                      {_, final_hierarchy} =
                        render_app(app_module, new_app_state, screen_rect, updated_hierarchy)

                      app_event_loop(app_module, new_app_state, screen_rect, timers, final_hierarchy)
                    else
                      app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy)
                    end
                end
              end
            end
        end

      {:app_event, event_name, data} ->
        result = app_module.handle_event(event_name, data, app_state)

        case result do
          {:stop, reason} ->
            cleanup_timers(timers)
            Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
            if reason == :normal, do: :ok, else: {:error, reason}

          _ ->
            new_app_state = dispatch_app_callback_result(result, app_state)
            {_, new_hierarchy} = render_app(app_module, new_app_state, screen_rect, widget_hierarchy)
            app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy)
        end

      {:bound_state_update, key, value} ->
        new_app_state = Map.put(app_state, key, value)
        {_, new_hierarchy} = render_app(app_module, new_app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy)

      {:theme_change, theme_name} ->
        # Handle automatic theme changes
        ThemeManager.set_theme(theme_name)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:theme_updated, new_theme} ->
        new_app_state =
          case app_module.handle_event({:theme_updated, new_theme}, app_state) do
            {:ok, state} -> state
            {:noreply, state} -> state
            state when is_map(state) -> state
          end

        {_, new_hierarchy} = render_app(app_module, new_app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy)

      {:timer, timer_id} ->
        new_app_state = app_module.on_timer(timer_id, app_state)

        if new_app_state === app_state do
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        else
          {_, new_hierarchy} = render_app(app_module, new_app_state, screen_rect, widget_hierarchy)
          app_event_loop(app_module, new_app_state, screen_rect, timers, new_hierarchy)
        end

      {:set_interval, interval_ms, timer_id} ->
        timer_ref = :timer.send_interval(interval_ms, {:timer, timer_id})
        new_timers = Map.put(timers, timer_id, timer_ref)
        app_event_loop(app_module, app_state, screen_rect, new_timers, widget_hierarchy)

      {:set_timeout, timeout_ms, timer_id} ->
        Process.send_after(self(), {:timer, timer_id}, timeout_ms)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:focus_widget, widget_id} ->
        new_hierarchy =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.focus_widget(widget_hierarchy, widget_id)
          else
            widget_hierarchy
          end

        {_, updated_hierarchy} = render_app(app_module, app_state, screen_rect, new_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy)

      {:widget_event, event} ->
        if widget_hierarchy do
          {new_hierarchy, _actions} =
            Drafter.WidgetHierarchy.broadcast_event(widget_hierarchy, event)

          {_, updated_hierarchy} =
            render_app(app_module, app_state, screen_rect, new_hierarchy)

          app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      {:widget_event, widget_id, event} ->
        if widget_hierarchy do
          {new_hierarchy, _actions} =
            Drafter.WidgetHierarchy.send_event_to_widget(widget_hierarchy, widget_id, event)

          {_, updated_hierarchy} =
            render_app(app_module, app_state, screen_rect, new_hierarchy)

          app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      {:widget_render_needed, _widget_id} ->
        drain_widget_render_notifications()

        if widget_hierarchy do
          render_hierarchy(widget_hierarchy, screen_rect)
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      :scroll_debounce_render ->
        drain_scroll_debounce_renders()
        Process.delete(:scroll_debounce_ref)
        idle_app_state = maybe_scroll_idle(app_module, app_state)

        if widget_hierarchy do
          {_, updated_hierarchy} = render_app(app_module, idle_app_state, screen_rect, widget_hierarchy)
          app_event_loop(app_module, idle_app_state, screen_rect, timers, updated_hierarchy)
        else
          app_event_loop(app_module, idle_app_state, screen_rect, timers, widget_hierarchy)
        end

      {:widget_action, _widget_id, {:theme_change, theme_name}} ->
        ThemeManager.set_theme(theme_name)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:widget_action, _widget_id, {:app_callback, callback, data}} ->
        new_app_state = dispatch_app_callback(app_module, callback, data, app_state)

        {_, updated_hierarchy} =
          render_app(app_module, new_app_state, screen_rect, widget_hierarchy)

        app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy)

      {:widget_action, _widget_id, _action} ->
        if widget_hierarchy do
          {_, updated_hierarchy} =
            render_app(app_module, app_state, screen_rect, widget_hierarchy)

          app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      {:activate_widget, widget_id} ->
        if widget_hierarchy do
          {new_hierarchy, actions} =
            Drafter.WidgetHierarchy.send_event_to_widget(widget_hierarchy, widget_id, :activate)

          new_app_state =
            Enum.reduce(actions, app_state, fn
              {:app_callback, callback, data}, acc_state ->
                dispatch_app_callback(app_module, callback, data, acc_state)
              _, acc_state -> acc_state
            end)

          {_, updated_hierarchy} = render_app(app_module, new_app_state, screen_rect, new_hierarchy)
          app_event_loop(app_module, new_app_state, screen_rect, timers, updated_hierarchy)
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      {:get_widget_value, widget_id, caller} ->
        value =
          if widget_hierarchy do
            case Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id) do
              nil -> nil
              state -> extract_widget_value(state)
            end
          else
            nil
          end

        send(caller, {:widget_value, widget_id, value})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:get_widget_state, widget_id, caller} ->
        state =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id)
          else
            nil
          end

        send(caller, {:widget_state, widget_id, state})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:query_one, selector, caller} ->
        result =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.query_one(widget_hierarchy, selector)
          else
            nil
          end

        send(caller, {:query_result, :one, result})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:query_all, selector, caller} ->
        result =
          if widget_hierarchy do
            Drafter.WidgetHierarchy.query_all(widget_hierarchy, selector)
          else
            []
          end

        send(caller, {:query_result, :all, result})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:validate_widget, widget_id, caller} ->
        result =
          if widget_hierarchy do
            {new_hierarchy, _} =
              Drafter.WidgetHierarchy.send_event_to_widget(
                widget_hierarchy,
                widget_id,
                :validate
              )

            state = Drafter.WidgetHierarchy.get_widget_state(new_hierarchy, widget_id)
            error = if state, do: Map.get(state, :error), else: nil

            case error do
              nil -> :ok
              msg -> {:error, msg}
            end
          else
            :ok
          end

        send(caller, {:validation_result, widget_id, result})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:get_animated_property, widget_id, property, caller} ->
        value =
          if widget_hierarchy do
            case Drafter.WidgetHierarchy.get_widget_state(widget_hierarchy, widget_id) do
              nil -> nil
              state -> get_animated_property_from_state(state, property)
            end
          else
            nil
          end

        send(caller, {:animated_property, widget_id, property, value})
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:apply_animation, widget_id, property, value} ->
        if widget_hierarchy do
          case Drafter.WidgetHierarchy.get_widget_info(widget_hierarchy, widget_id) do
            nil ->
              app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

            widget_info ->
              updated_state = apply_animated_property(widget_info.state, property, value)

              new_hierarchy =
                Drafter.WidgetHierarchy.update_widget_state(
                  widget_hierarchy,
                  widget_id,
                  updated_state
                )

              {_, final_hierarchy} = render_app(app_module, app_state, screen_rect, new_hierarchy)
              app_event_loop(app_module, app_state, screen_rect, timers, final_hierarchy)
          end
        else
          app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)
        end

      :animation_tick ->
        {_, updated_hierarchy} = render_app(app_module, app_state, screen_rect, widget_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, updated_hierarchy)

      :screen_render_needed ->
        render_screens_from_manager(screen_rect, app_module, app_state, widget_hierarchy)
        app_event_loop(app_module, app_state, screen_rect, timers, widget_hierarchy)

      {:__drafter_stop__, reason} ->
        cleanup_timers(timers)
        Drafter.WidgetHierarchy.stop_all_servers(widget_hierarchy)
        if reason == :normal, do: :ok, else: {:error, reason}

      other ->
        new_app_state = maybe_on_message(app_module, other, app_state)
        app_event_loop(app_module, new_app_state, screen_rect, timers, widget_hierarchy)
    end
  end

  defp dispatch_app_callback(app_module, callback, data, acc_state) do
    result = app_module.handle_event(callback, data, acc_state)
    dispatch_app_callback_result(result, acc_state)
  end

  defp dispatch_app_callback_result(result, acc_state) do
    case result do
      {:stop, reason} ->
        send(self(), {:__drafter_stop__, reason})
        acc_state
      _ ->
        Drafter.ActionRegistry.dispatch(result, acc_state)
    end
  end

  defp extract_widget_value(state) do
    cond do
      Map.has_key?(state, :text) ->
        state.text

      Map.has_key?(state, :checked) ->
        state.checked

      Map.has_key?(state, :state) and state.state in [:on, :off] ->
        state.state == :on

      Map.has_key?(state, :selected_index) and Map.has_key?(state, :options) ->
        case Enum.at(state.options, state.selected_index) do
          %{id: id} -> id
          nil -> nil
        end

      Map.has_key?(state, :selected_indices) and Map.has_key?(state, :options) ->
        state.selected_indices
        |> MapSet.to_list()
        |> Enum.map(fn idx ->
          case Enum.at(state.options, idx) do
            %{id: id} -> id
            nil -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      Map.has_key?(state, :expanded) ->
        state.expanded

      Map.has_key?(state, :active_tab) ->
        state.active_tab

      Map.has_key?(state, :selected_rows) ->
        MapSet.to_list(state.selected_rows)

      Map.has_key?(state, :selected_nodes) ->
        MapSet.to_list(state.selected_nodes)

      true ->
        nil
    end
  end

  defp get_animated_property_from_state(state, property) do
    case property do
      :opacity -> Map.get(state, :opacity, 1.0)
      :background -> get_in(state, [:style, :bg]) || Map.get(state, :bg)
      :color -> get_in(state, [:style, :fg]) || Map.get(state, :fg)
      :offset_x -> Map.get(state, :offset_x, 0)
      :offset_y -> Map.get(state, :offset_y, 0)
      _ -> nil
    end
  end

  defp apply_animated_property(state, property, value) do
    case property do
      :opacity ->
        Map.put(state, :opacity, value)

      :background ->
        put_in(state, [:style, :bg], value)

      :color ->
        put_in(state, [:style, :fg], value)

      :offset_x ->
        Map.put(state, :offset_x, value)

      :offset_y ->
        Map.put(state, :offset_y, value)

      _ ->
        state
    end
  end

  defp drain_bound_updates(app_state, bindings) do
    receive do
      {:bound_state_update, key, value} ->
        drain_bound_updates(Map.put(app_state, key, value), Map.put(bindings, key, value))
    after
      0 -> {app_state, bindings}
    end
  end


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
    Enum.each(timers, fn {_id, timer_ref} ->
      :timer.cancel(timer_ref)
    end)
  end


  defp reschedule_scroll_debounce do
    case Process.get(:scroll_debounce_ref) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    new_ref = Process.send_after(self(), :scroll_debounce_render, @scroll_debounce_ms)
    Process.put(:scroll_debounce_ref, new_ref)
  end

  defp drain_stale_events do
    receive do
      {:widget_render_needed, _} -> drain_stale_events()
      {:widget_action, _, _} -> drain_stale_events()
      {:activate_widget, _} -> drain_stale_events()
      {:__drafter_stop__, _} -> drain_stale_events()
    after
      0 -> :ok
    end
  end

  defp drain_widget_render_notifications do
    receive do
      {:widget_render_needed, _} -> drain_widget_render_notifications()
    after
      0 -> :ok
    end
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

  defp make_screen_rect(width, height) do
    %{x: 0, y: 0, width: width, height: height}
  end

  defp render_hierarchy(hierarchy, screen_rect) do
    screens = Drafter.ScreenManager.get_all_screens()
    toasts = Drafter.ScreenManager.get_toasts()
    current_theme = ThemeManager.get_current_theme()
    background_strips = create_app_background(screen_rect, current_theme)
    alias Drafter.LayerCompositor
    viewport = %{width: screen_rect.width, height: screen_rect.height}
    background_layer = LayerCompositor.background_layer(background_strips, screen_rect)
    base_layers = create_widget_layers_from_hierarchy(hierarchy, screen_rect)

    if screens == [] and toasts == [] do
      if base_layers == [] do
        Compositor.render_strips(background_strips, 0, 0)
      else
        final_strips = LayerCompositor.composite([background_layer] ++ base_layers, viewport)
        Compositor.render_strips(final_strips, 0, 0)
      end
    else
      {screen_layers, overlay_layers} =
        Enum.reduce(screens, {[], []}, fn screen, {content_acc, overlay_acc} ->
          screen_local_rect = screen.rect

          if screen_local_rect && screen.widget_hierarchy do
            has_border = screen.type in [:modal, :popover] and Map.get(screen.options, :border, false)

            content_rect =
              if has_border do
                %{
                  x: screen_local_rect.x + 1,
                  y: screen_local_rect.y + 1,
                  width: max(1, screen_local_rect.width - 2),
                  height: max(1, screen_local_rect.height - 2)
                }
              else
                screen_local_rect
              end

            content_layers = create_widget_layers_from_hierarchy(screen.widget_hierarchy, content_rect)

            new_overlay_layers =
              if has_border do
                [create_modal_border_layer(screen_local_rect, current_theme, screen.options) | overlay_acc]
              else
                overlay_acc
              end

            {content_acc ++ content_layers, new_overlay_layers}
          else
            {content_acc, overlay_acc}
          end
        end)

      toast_layers = Enum.map(toasts, &create_toast_layer(&1, screen_rect, current_theme))

      all_layers = [background_layer] ++ base_layers ++ screen_layers ++ overlay_layers ++ toast_layers
      final_strips = LayerCompositor.composite(all_layers, viewport)
      Compositor.render_strips(final_strips, 0, 0)
    end
  end

  defp render_app(app_module, app_state, screen_rect, existing_hierarchy \\ nil, _opts \\ []) do
    screens = Drafter.ScreenManager.get_all_screens()
    toasts = Drafter.ScreenManager.get_toasts()

    if length(screens) > 0 or length(toasts) > 0 do
      render_screens_from_manager(screen_rect, app_module, app_state, existing_hierarchy)
      {:ok, existing_hierarchy}
    else
      current_theme = ThemeManager.get_current_theme()

      render_result =
        case app_module.render(app_state) do
          [] ->
            app_module.render(app_state, screen_rect)

          result ->
            result
        end

      case render_result do
        component_tree when is_tuple(component_tree) ->
          hierarchy =
            ComponentRenderer.render_tree(
              component_tree,
              screen_rect,
              current_theme,
              app_state,
              existing_hierarchy,
              app_module: app_module
            )

          # Create background
          background_strips = create_app_background(screen_rect, current_theme)

          # Create widget layers
          widget_layers = create_widget_layers_from_hierarchy(hierarchy, screen_rect)

          # Composite and render
          if length(widget_layers) == 0 do
            Compositor.render_strips(background_strips, 0, 0)
          else
            alias Drafter.LayerCompositor
            viewport = %{width: screen_rect.width, height: screen_rect.height}
            background_layer = LayerCompositor.background_layer(background_strips, screen_rect)
            layers = [background_layer] ++ widget_layers
            final_strips = LayerCompositor.composite(layers, viewport)
            Compositor.render_strips(final_strips, 0, 0)
          end

          {:ok, hierarchy}

        strips when is_list(strips) ->
          # Old API - render strips directly
          Compositor.render_strips(strips, 0, 0)
          {:ok, nil}

        {:error, _reason} ->
          {:error, nil}
      end
    end
  end

  defp render_screens_from_manager(screen_rect, app_module, app_state, existing_hierarchy) do
    screens = Drafter.ScreenManager.get_all_screens()
    toasts = Drafter.ScreenManager.get_toasts()
    current_theme = ThemeManager.get_current_theme()

    background_strips = create_app_background(screen_rect, current_theme)

    has_covering_screens = screens != []

    base_layers =
      if has_covering_screens && existing_hierarchy do
        create_widget_layers_from_hierarchy(existing_hierarchy, screen_rect)
      else
        if app_module && app_state do
          render_result =
            case app_module.render(app_state) do
              [] ->
                app_module.render(app_state, screen_rect)

              result ->
                result
            end

          case render_result do
            component_tree when is_tuple(component_tree) ->
              hierarchy =
                ComponentRenderer.render_tree(
                  component_tree,
                  screen_rect,
                  current_theme,
                  app_state,
                  existing_hierarchy,
                  app_module: app_module
                )

              create_widget_layers_from_hierarchy(hierarchy, screen_rect)

            _ ->
              []
          end
        else
          []
        end
      end

    {screen_layers, overlay_layers} =
      Enum.reduce(screens, {[], []}, fn screen, {content_acc, overlay_acc} ->
        this_screen_rect =
          if screen.rect, do: screen.rect, else: calculate_screen_rect(screen, screen_rect)

        unless screen.rect do
          Drafter.ScreenManager.update_screen_rect(screen.id, this_screen_rect)
        end

        has_border = screen.type in [:modal, :popover] and Map.get(screen.options, :border, false)

        content_rect =
          if has_border do
            %{
              x: this_screen_rect.x + 1,
              y: this_screen_rect.y + 1,
              width: max(1, this_screen_rect.width - 2),
              height: max(1, this_screen_rect.height - 2)
            }
          else
            this_screen_rect
          end

        hierarchy =
          case screen.module.render(screen.state) do
            component_tree when is_tuple(component_tree) ->
              ComponentRenderer.render_tree(
                component_tree,
                content_rect,
                current_theme,
                screen.state,
                screen.widget_hierarchy,
                app_module: screen.module
              )

            _ ->
              screen.widget_hierarchy
          end

        content_layers =
          if hierarchy do
            Drafter.ScreenManager.update_screen_hierarchy(screen.id, hierarchy)
            create_widget_layers_from_hierarchy(hierarchy, content_rect)
          else
            []
          end

        new_overlay_layers =
          if has_border do
            [create_modal_border_layer(this_screen_rect, current_theme, screen.options) | overlay_acc]
          else
            overlay_acc
          end

        {content_acc ++ content_layers, new_overlay_layers}
      end)

    screen_layers = List.flatten(screen_layers)

    toast_layers =
      Enum.map(toasts, fn toast ->
        create_toast_layer(toast, screen_rect, current_theme)
      end)

    all_layers =
      [background_layer(background_strips, screen_rect)] ++
        base_layers ++ screen_layers ++ overlay_layers ++ toast_layers

    if length(all_layers) == 1 do
      Compositor.render_strips(background_strips, 0, 0)
    else
      alias Drafter.LayerCompositor
      viewport = %{width: screen_rect.width, height: screen_rect.height}
      final_strips = LayerCompositor.composite(all_layers, viewport)
      Compositor.render_strips(final_strips, 0, 0)
    end
  end

  defp create_modal_border_layer(rect, theme, options) do
    alias Drafter.Draw.{Strip, Segment}
    alias Drafter.LayerCompositor

    border_style = %{fg: theme.primary, bg: theme.panel}
    content_bg = %{fg: theme.text_primary, bg: theme.panel}
    inner_width = rect.width - 2
    inner_height = rect.height - 2
    title = Map.get(options, :title)

    top_border =
      if title do
        title_text = " #{title} "
        title_len = String.length(title_text)
        left_dashes = div(inner_width - title_len, 2)
        right_dashes = max(0, inner_width - title_len - left_dashes)

        Strip.new([
          Segment.new("╭", border_style),
          Segment.new(String.duplicate("─", left_dashes), border_style),
          Segment.new(title_text, %{fg: theme.text_primary, bg: theme.panel, bold: true}),
          Segment.new(String.duplicate("─", right_dashes), border_style),
          Segment.new("╮", border_style)
        ])
      else
        Strip.new([Segment.new("╭" <> String.duplicate("─", inner_width) <> "╮", border_style)])
      end

    side_strips =
      for _ <- 1..inner_height do
        Strip.new([
          Segment.new("│", border_style),
          Segment.new(String.duplicate(" ", inner_width), content_bg),
          Segment.new("│", border_style)
        ])
      end

    bottom_border =
      Strip.new([Segment.new("╰" <> String.duplicate("─", inner_width) <> "╯", border_style)])

    strips = [top_border] ++ side_strips ++ [bottom_border]
    LayerCompositor.create_layer(:modal_border, strips, rect, 19)
  end

  defp create_toast_layer(toast, screen_rect, _theme) do
    message = toast.message
    variant = toast.variant

    bg_color =
      case variant do
        :success -> {30, 100, 30}
        :error -> {120, 30, 30}
        :warning -> {120, 100, 30}
        _ -> {40, 40, 60}
      end

    text_color = {255, 255, 255}

    lines = String.split(message, "\n")
    max_width = Enum.max_by(lines, &String.length/1) |> String.length()
    max_width = min(max_width + 4, screen_rect.width - 4)
    max_width = max(max_width, 20)

    content_width = max_width - 2

    wrapped_lines =
      Enum.flat_map(lines, fn line ->
        if String.length(line) <= content_width do
          [line]
        else
          chunk_line(line, content_width)
        end
      end)

    height = length(wrapped_lines) + 2
    height = min(height, div(screen_rect.height, 3))

    stack_offset = toast.stack_index * (height + 1)

    {y, x} =
      case toast.position do
        :top_right ->
          {2 + stack_offset, screen_rect.width - max_width - 2}

        :top_center ->
          {2 + stack_offset, div(screen_rect.width - max_width, 2)}

        :top_left ->
          {2 + stack_offset, 2}

        :middle_right ->
          {div(screen_rect.height - height, 2) - div(stack_offset, 2),
           screen_rect.width - max_width - 2}

        :middle_center ->
          {div(screen_rect.height - height, 2) - div(stack_offset, 2),
           div(screen_rect.width - max_width, 2)}

        :middle_left ->
          {div(screen_rect.height - height, 2) - div(stack_offset, 2), 2}

        :bottom_left ->
          {screen_rect.height - height - 2 - stack_offset, 2}

        :bottom_center ->
          {screen_rect.height - height - 2 - stack_offset, div(screen_rect.width - max_width, 2)}

        _ ->
          {screen_rect.height - height - 2 - stack_offset, screen_rect.width - max_width - 2}
      end

    toast_rect = %{x: x, y: y, width: max_width, height: height}

    border_style = %{fg: text_color, bg: bg_color}
    content_style = %{fg: text_color, bg: bg_color}

    top_border = "┌" <> String.duplicate("─", max_width - 2) <> "┐"
    bottom_border = "└" <> String.duplicate("─", max_width - 2) <> "┘"

    content_strips =
      wrapped_lines
      |> Enum.with_index()
      |> Enum.map(fn {line, _idx} ->
        padding = max_width - String.length(line) - 2
        left_pad = div(padding, 2)
        right_pad = padding - left_pad

        full_line =
          "│" <>
            String.duplicate(" ", left_pad) <> line <> String.duplicate(" ", right_pad) <> "│"

        Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(full_line, content_style)])
      end)

    top_strip = Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(top_border, border_style)])

    bottom_strip =
      Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(bottom_border, border_style)])

    all_strips = [top_strip] ++ content_strips ++ [bottom_strip]

    alias Drafter.LayerCompositor
    LayerCompositor.content_layer(toast.id, all_strips, toast_rect)
  end

  defp chunk_line(line, max_len) do
    if String.length(line) <= max_len do
      [line]
    else
      {chunk, rest} = String.split_at(line, max_len)
      [chunk | chunk_line(rest, max_len)]
    end
  end

  defp background_layer(strips, rect) do
    alias Drafter.LayerCompositor
    LayerCompositor.background_layer(strips, rect)
  end

  defp calculate_screen_rect(screen, base_rect) do
    Drafter.Screen.calculate_rect(screen, base_rect)
  end

  defp create_app_background(rect, theme) do
    # Simple background for now
    empty_style = %{bg: theme.background, fg: theme.text_primary}
    empty_line = String.duplicate(" ", rect.width)

    for _row <- 0..(rect.height - 1) do
      Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(empty_line, empty_style)])
    end
  end

  defp create_widget_layers_from_hierarchy(hierarchy, _rect) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())
    widget_ids = Map.keys(hierarchy.widgets)

    Enum.flat_map(widget_ids, fn widget_id ->
      if MapSet.member?(hidden, widget_id) do
        []
      else
      case Map.get(hierarchy.widgets, widget_id) do
        nil ->
          []

        widget_info ->
          widget_rect = Map.get(hierarchy.widget_rects, widget_id)

          if widget_rect && widget_info do
            {render_rect, widget_strips} =
              case Drafter.WidgetStripCache.get(widget_id) do
                {cached_rect, strips} -> {cached_rect, strips}
                nil ->
                  if widget_info.pid do
                    Drafter.WidgetServer.get_render(widget_info.pid)
                  else
                    cache = Process.get(:widget_render_cache, %{})
                    cache_key = :erlang.phash2({widget_info.state, widget_rect.width, widget_rect.height})

                    strips =
                      case Map.get(cache, widget_id) do
                        {^cache_key, cached} ->
                          cached

                        _ ->
                          result = apply(widget_info.module, :render, [widget_info.state, widget_rect])
                          Process.put(:widget_render_cache, Map.put(cache, widget_id, {cache_key, result}))
                          result
                      end

                    {widget_rect, strips}
                  end
              end

            scroll_parent_id =
              Drafter.WidgetHierarchy.get_widget_scroll_parent(hierarchy, widget_id)

            {final_rect, final_strips} =
              if scroll_parent_id do
                apply_scroll_clipping(hierarchy, scroll_parent_id, render_rect, widget_strips)
              else
                {render_rect, widget_strips}
              end

            if length(final_strips) > 0 do
              layer = Drafter.LayerCompositor.widget_layer(widget_id, final_strips, final_rect)
              [layer]
            else
              []
            end
          else
            []
          end
      end
      end
    end)
  end

  defp apply_scroll_clipping(
         hierarchy,
         scroll_parent_id,
         widget_rect,
         widget_strips,
         widget_id \\ nil
       ) do
    scroll_info = Drafter.WidgetHierarchy.get_scroll_container_info(hierarchy, scroll_parent_id)
    scroll_state = Drafter.WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

    if scroll_info && scroll_state do
      viewport = scroll_info.viewport_rect
      scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)

      virtual_top = widget_rect.y
      virtual_bottom = widget_rect.y + length(widget_strips)

      viewport_top = viewport.y + scroll_y
      viewport_bottom = viewport_top + viewport.height

      cond do
        virtual_bottom <= viewport_top ->
          {widget_rect, []}

        virtual_top >= viewport_bottom ->
          {widget_rect, []}

        true ->
          start_strip_idx = max(0, viewport_top - virtual_top)
          end_strip_idx = min(length(widget_strips), viewport_bottom - virtual_top)

          clipped_strips =
            Enum.slice(widget_strips, start_strip_idx, end_strip_idx - start_strip_idx)

          screen_y = max(viewport.y, widget_rect.y - scroll_y)

          available_width = viewport.x + viewport.width - widget_rect.x
          max_width = max(1, min(widget_rect.width, available_width))
          _overrun = widget_rect.width - max_width

          _is_tree = widget_id != nil and String.starts_with?(Atom.to_string(widget_id), "tree_")

          clipped_strips =
            Enum.map(clipped_strips, fn strip ->
              Drafter.Draw.Strip.crop(strip, max_width)
            end)

          new_rect = %{
            widget_rect
            | y: screen_y,
              height: length(clipped_strips),
              width: min(widget_rect.width, max_width)
          }

          {new_rect, clipped_strips}
      end
    else
      {widget_rect, widget_strips}
    end
  end

  defp update_hierarchy_preferred_sizes(hierarchy) do
    Enum.reduce(hierarchy.widgets, hierarchy, fn {widget_id, widget_info}, acc ->
      case widget_info do
        %{pid: pid, module: module, state: _state} when is_pid(pid) ->
          new_state = Drafter.WidgetServer.get_state(pid)
          updated_widget = %{widget_info | state: new_state}
          new_widgets = Map.put(acc.widgets, widget_id, updated_widget)

          acc
          |> Map.put(:widgets, new_widgets)
          |> update_widget_preferred_size(widget_id, module, new_state)

        _ ->
          acc
      end
    end)
  end

  defp update_widget_preferred_size(hierarchy, widget_id, module, state) do
    case {module, state} do
      {Drafter.Widget.Collapsible, %{expanded: true, content: content, content_height: content_height}} ->
        lines =
          cond do
            is_binary(content) -> length(String.split(content, "\n"))
            is_list(content) -> content_height || 10
            true -> 1
          end
        preferred_size = 1 + lines

        Drafter.WidgetHierarchy.update_preferred_size(hierarchy, widget_id, preferred_size)

      {Drafter.Widget.Collapsible, %{expanded: false}} ->
        Drafter.WidgetHierarchy.update_preferred_size(hierarchy, widget_id, 1)

      _ ->
        hierarchy
    end
  end
end
