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

  alias Drafter.{Terminal, Event, Compositor, ThemeManager}
  alias Drafter.Runtime.Renderer

  alias Drafter.Widget.{
    Label,
    Button,
    Container,
    Digits,
    Grid,
    Placeholder,
    Markdown,
    Footer,
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
    Drafter.AppRegistry.send_to_loop( {:get_widget_value, widget_id, self()})

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
    Drafter.AppRegistry.send_to_loop( {:get_widget_state, widget_id, self()})

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
    Drafter.AppRegistry.send_to_loop( {:query_one, selector, self()})

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
    Drafter.AppRegistry.send_to_loop( {:query_all, selector, self()})

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
    Drafter.AppRegistry.send_to_loop( {:validate_widget, widget_id, self()})

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

    {_, hierarchy} = Renderer.render_app(app_module, app_state, screen_rect)

    ready_app_state = app_module.on_ready(app_state)
    {_, hierarchy} = Renderer.render_app(app_module, ready_app_state, screen_rect, hierarchy)

    Drafter.Runtime.AppLoop.enter_loop(app_module, ready_app_state, screen_rect, %{}, hierarchy)
  end

  defp run_shared_session(app_module, mount_props, shared_state_pid) do
    _ = Drafter.Logging.setup()

    topic = Drafter.Session.SharedState.pubsub_topic(shared_state_pid)
    Phoenix.PubSub.subscribe(Drafter.PubSub, topic)

    app_state = Drafter.Session.SharedState.get_state(shared_state_pid)
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
                Renderer.update_hierarchy_preferred_sizes(new_hierarchy)
              else
                new_hierarchy
              end

            {flushed_state, flushed_bindings} = drain_bound_updates(app_state, local_bindings)

            {new_app_state, new_bindings, new_hierarchy_after_callbacks} =
              Enum.reduce(actions, {flushed_state, flushed_bindings, updated_hierarchy}, fn
                {:app_callback, callback, data}, {acc_state, acc_bindings, acc_hier} ->
                  {result_state, result_hier} =
                    dispatch_shared_callback(
                      app_module,
                      callback,
                      data,
                      acc_state,
                      shared_state_pid,
                      acc_hier,
                      screen_rect
                    )

                  {result_state, acc_bindings, result_hier}

                _, acc ->
                  acc
              end)

            if widget_consumed do
              if :scroll_fast_render in actions and scroll_optimization_enabled?() do
                scrolled_app_state = maybe_scroll_active(app_module, new_app_state)
                Renderer.render_hierarchy(new_hierarchy_after_callbacks, screen_rect)
                reschedule_scroll_debounce()

                shared_session_loop(
                  app_module,
                  scrolled_app_state,
                  screen_rect,
                  timers,
                  new_hierarchy_after_callbacks,
                  shared_state_pid,
                  mount_props,
                  new_bindings
                )
              else
                {_, final_hierarchy} =
                  Renderer.render_app(
                    app_module,
                    new_app_state,
                    screen_rect,
                    new_hierarchy_after_callbacks
                  )

                shared_session_loop(
                  app_module,
                  new_app_state,
                  screen_rect,
                  timers,
                  final_hierarchy,
                  shared_state_pid,
                  mount_props,
                  new_bindings
                )
              end
            else
              {result_state, should_stop} =
                handle_shared_event(app_module, event, new_app_state, shared_state_pid)

              if should_stop do
                cleanup_timers(timers)
                :ok
              else
                {nav_hierarchy, _nav_actions} =
                  Drafter.WidgetHierarchy.handle_event(updated_hierarchy, event)

                {_, final_hierarchy} =
                  Renderer.render_app(app_module, result_state, screen_rect, nav_hierarchy)

                shared_session_loop(
                  app_module,
                  result_state,
                  screen_rect,
                  timers,
                  final_hierarchy,
                  shared_state_pid,
                  mount_props,
                  new_bindings
                )
              end
            end
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
            Drafter.WidgetHierarchy.focus_widget(widget_hierarchy, widget_id)
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
    Drafter.Widget.Registry.scan_and_register()

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
        Drafter.Runtime.AppLoop.run(app_module)
      end)

    ref = Process.monitor(app_pid)

    receive do
      {:DOWN, ^ref, :process, ^app_pid, reason} ->
        Drafter.Event.Manager.drain_queue()
        Terminal.Driver.cleanup()
        Drafter.Event.Manager.drain_queue()
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
