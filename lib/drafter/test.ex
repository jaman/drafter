defmodule Drafter.Test do
  @moduledoc """
  Headless testing of Drafter applications under ExUnit.

  `start_headless/3` starts an app against an in-memory terminal and returns a
  context map. Every other function in this module takes that context as its first
  argument. `stop/1` shuts the instance down.

  Each function that sends input blocks until the app has finished handling it, so a
  send and the assertion that follows need no sleep between them.

      defmodule CounterTest do
        use ExUnit.Case, async: false
        import Drafter.Test

        setup do
          ctx = start_headless(Counter)
          on_exit(fn -> stop(ctx) end)
          %{ctx: ctx}
        end

        test "increment", %{ctx: ctx} do
          send_click(ctx, query_one(ctx, "Button"))
          assert get_state(ctx).count == 1
          assert screen_text(ctx) =~ "Count: 1"
        end
      end

  Selectors take the forms `Drafter.query_one/1` documents: a widget type as the
  module's last segment in CamelCase or snake_case (`"Button"`, `"TextInput"`,
  `"text_input"`), `"#id"`, and `".class"`.

  ## What has to be running

  The `:drafter` application must be started before `start_headless/3` is called:
  the harness starts its own session services, but the widget supervisor, the
  skin manager, the stylesheet loader and the PubSub the widgets use belong to
  `:drafter`'s own supervision tree. In a Mix project that lists `:drafter` as a
  dependency this is automatic — `mix test` starts the applications of every dep,
  and nothing extra goes in `test_helper.exs`. No terminal, tty, or `TERM` is
  needed; the in-memory driver replaces all of it.

  A single-file test outside a project works the same way once `Mix.install/2` has
  pulled the dependency in and started it. Building it compiles a C NIF and a
  helper binary through `elixir_make`, so `make` and a C compiler must be present.
  `ExUnit.start/1` runs the tests when the script ends, so `elixir the_file.exs`
  is the whole command. The app module — `Counter` below — is defined in the same
  file or loaded by it.

      Mix.install([{:drafter, github: "jaman/drafter"}])

      ExUnit.start()

      defmodule CounterTest do
        use ExUnit.Case, async: false
        import Drafter.Test

        test "starts" do
          ctx = start_headless(Counter)
          assert screen_text(ctx) =~ "Count: 0"
          stop(ctx)
        end
      end
  """

  alias Drafter.Event.Manager, as: EventManager
  alias Drafter.Test.{Harness, HeadlessDriver}

  @doc """
  Starts `app_module` against an in-memory terminal and returns the test context.

  `props` is the map handed to the app's `mount/1`; default `%{}`.

  `opts` is a keyword list:

    * `:size` - the terminal size as a `{columns, rows}` tuple. Default `{80, 24}`.
    * `:test_pid` - the process the headless driver notifies on each render.
      Default `self()`, which is what `await_render/2` waits on.

  No other keys are read; unknown ones are silently ignored.

  Returns a context map carrying `:app_module`, `:app_pid`, `:app_monitor`,
  `:props`, `:test_pid`, and `:session_pids`. Raises `RuntimeError` if the app fails
  to start. The app has completed its first render before this returns.

  The headless driver is a globally registered process, so only one instance can run
  at a time: a test using this must be `async: false`, and `stop/1` must run before
  the next one starts.

      ctx = Drafter.Test.start_headless(MyApp, %{user_id: 7}, size: {120, 40})
  """
  @spec start_headless(module(), map(), keyword()) :: map()
  def start_headless(app_module, props \\ %{}, opts \\ []) do
    case Harness.start_app(app_module, props, opts) do
      {:ok, ctx} ->
        sync(ctx)
        ctx

      {:error, reason} ->
        raise "Failed to start headless app: #{inspect(reason)}"
    end
  end

  @doc """
  Stops the app and every service `start_headless/3` started. Returns `:ok`.

  Safe to call on an app that has already exited. Call it from `on_exit/1` so a
  failing test still frees the globally named services for the next one.
  """
  @spec stop(map()) :: :ok
  def stop(ctx) do
    Harness.stop_app(ctx)
  end

  @doc """
  Injects a key press and returns once the app has handled it.

  `key` is a key atom as `Drafter.Terminal.ANSI` produces them: `:enter`, `:up`,
  `:f1`, or a printable ASCII character as an atom (`:q`, `:" "`). `modifiers` is a
  list drawn from `:ctrl`, `:alt`, and `:shift`; default `[]`.

  Injects `{:key, key}` when `modifiers` is empty and `{:key, key, modifiers}`
  otherwise — the same shapes `handle_event/2` and `keybinding/3` match. Returns `:ok`.

      send_key(ctx, :enter)
      send_key(ctx, :s, [:ctrl])
  """
  @spec send_key(map(), atom(), [atom()]) :: :ok
  def send_key(ctx, key, modifiers \\ []) do
    event =
      if modifiers == [] do
        {:key, key}
      else
        {:key, key, modifiers}
      end

    HeadlessDriver.inject_event(event)
    sync(ctx)
  end

  @doc """
  Injects a `{:char, codepoint}` event and returns once the app has handled it.

  `char` is a codepoint integer, or a binary whose **first byte** is taken as the
  codepoint — so only single-byte ASCII binaries round-trip correctly. Pass a
  codepoint integer for anything above U+007F: `send_char(ctx, "中")` injects the
  first UTF-8 byte, `228`, while `send_char(ctx, ?中)` injects the character.
  Returns `:ok`.

  A real terminal sends printable ASCII as `{:key, key}`, not `{:char, codepoint}`;
  use `send_key/3` to reproduce a plain letter press and this to reproduce a
  non-ASCII one.

      send_char(ctx, ?x)
      send_char(ctx, 0x4E2D)
  """
  @spec send_char(map(), integer() | binary()) :: :ok
  def send_char(ctx, char) when is_binary(char) do
    send_char(ctx, :binary.first(char))
  end

  def send_char(ctx, char) when is_integer(char) do
    event = {:char, char}
    HeadlessDriver.inject_event(event)
    sync(ctx)
  end

  @doc """
  Clicks at a screen cell and returns once the app has handled it.

  `x` and `y` are zero-based column and row. Injects a left-button
  `%{type: :mouse_up, ...}` event, which is what activates a widget. Returns `:ok`.
  """
  @spec send_click(map(), integer(), integer()) :: :ok
  def send_click(ctx, x, y) when is_integer(x) and is_integer(y) do
    event = {:mouse, %{type: :mouse_up, x: x, y: y, button: :left}}
    HeadlessDriver.inject_event(event)
    sync(ctx)
  end

  @doc """
  Clicks a widget by id and returns once the app has handled it.

  `widget_id` is an atom — the `:id` given to an element, or the id `query_one/2`
  returned. A left-button `mouse_up` is injected at the centre of the widget's
  current rect, so the click lands on whatever is drawn on top there. Returns `:ok`;
  an id that is not in the hierarchy is ignored and nothing is clicked.

      send_click(ctx, query_one(ctx, "Button.primary"))
  """
  @spec send_click(map(), atom()) :: :ok
  def send_click(ctx, widget_id) when is_atom(widget_id) do
    ask(ctx, {:widget_click, widget_id})
    sync(ctx)
  end

  @doc """
  Injects a raw mouse event and returns once the app has handled it.

  `event` is the payload map, wrapped as `{:mouse, event}`. Its shapes are those
  `Drafter.Terminal.ANSI` documents: `%{type: :mouse_down | :mouse_up | :drag,
  button: button, x: x, y: y}`, `%{type: :move, x: x, y: y}`, and
  `%{type: :scroll, direction: :up | :down | :left | :right, x: x, y: y}`.
  Returns `:ok`.

      send_mouse(ctx, %{type: :scroll, direction: :down, x: 10, y: 5})
  """
  @spec send_mouse(map(), map()) :: :ok
  def send_mouse(ctx, event) do
    HeadlessDriver.inject_event({:mouse, event})
    sync(ctx)
  end

  @doc """
  The app's current state — whatever its `mount/1` and callbacks have produced.

  Raises `RuntimeError` if the app does not answer within 1000 ms.
  """
  @spec get_state(map()) :: term()
  def get_state(ctx) do
    ask(ctx, {:get_state, self()})

    receive do
      {:state, state} -> state
    after
      1000 -> raise "Timeout waiting for app state"
    end
  end

  @doc """
  The primary value of the widget with `widget_id`.

  The per-widget types are the ones `Drafter.get_widget_value/1` lists. Returns `nil`
  when no widget has that id, and also when the app fails to answer within 1000 ms.
  """
  @spec get_widget_value(map(), term()) :: term() | nil
  def get_widget_value(ctx, widget_id) do
    ask(ctx, {:get_widget_value, widget_id, self()})

    receive do
      {:widget_value, ^widget_id, value} -> value
    after
      1000 -> nil
    end
  end

  @doc """
  The full state struct of the widget with `widget_id`.

  Returns `nil` when no widget has that id, and also when the app fails to answer
  within 1000 ms.
  """
  @spec get_widget_state(map(), term()) :: term() | nil
  def get_widget_state(ctx, widget_id) do
    ask(ctx, {:get_widget_state, widget_id, self()})

    receive do
      {:widget_state, ^widget_id, state} -> state
    after
      1000 -> nil
    end
  end

  @doc """
  The id of the first widget matching `selector`, or `nil`.

  `selector` is a `String.t()` in the forms `Drafter.query_one/1` documents.
  Also returns `nil` when the app fails to answer within 1000 ms.
  """
  @spec query_one(map(), String.t()) :: term() | nil
  def query_one(ctx, selector) do
    ask(ctx, {:query_one, selector, self()})

    receive do
      {:query_result, :one, result} -> result
    after
      1000 -> nil
    end
  end

  @doc """
  The ids of every widget matching `selector`.

  `selector` is a `String.t()` in the forms `Drafter.query_one/1` documents. Returns
  `[]` when nothing matches, and also when the app fails to answer within 1000 ms.
  """
  @spec query_all(map(), String.t()) :: [term()]
  def query_all(ctx, selector) do
    ask(ctx, {:query_all, selector, self()})

    receive do
      {:query_result, :all, result} -> result
    after
      1000 -> []
    end
  end

  @doc """
  Everything the app has written to the terminal since it started, as iodata.

  Raw bytes including ANSI escape sequences and cursor moves. Use `screen_text/1` for
  the rendered characters. The context argument is accepted and unused; the buffer
  belongs to the single headless driver.
  """
  @spec get_rendered_output(map()) :: iodata()
  def get_rendered_output(_ctx) do
    HeadlessDriver.get_buffer()
  end

  @doc """
  What the app currently has on screen, as plain text.

  Replays the terminal writes onto a blank grid and returns the visible
  characters, one screen row per line.

      assert Drafter.Test.screen_text(ctx) =~ "Counter: 3"
  """
  @spec screen_text(map()) :: String.t()
  def screen_text(ctx), do: ctx |> screen_lines() |> Enum.join("\n")

  @doc """
  The visible characters of each screen row, trailing blanks removed.
  """
  @spec screen_lines(map()) :: [String.t()]
  def screen_lines(ctx) do
    {width, height} = HeadlessDriver.get_size()

    ctx
    |> get_rendered_output()
    |> IO.iodata_to_binary()
    |> replay(width, height)
    |> Enum.map(&String.trim_trailing/1)
  end

  @cursor_move ~r/\e\[(\d+);(\d+)H/
  @ansi_escape ~r/\e\[[0-9;?]*[a-zA-Z]/

  defp replay(output, width, height) do
    blank = String.duplicate(" ", width)
    grid = List.duplicate(blank, height)

    @cursor_move
    |> Regex.split(output, include_captures: true, trim: true)
    |> chunk_writes()
    |> Enum.reduce(grid, fn {row, col, text}, acc -> place(acc, row, col, text, width, height) end)
  end

  defp chunk_writes(parts), do: chunk_writes(parts, nil, [])

  defp chunk_writes([], _cursor, acc), do: Enum.reverse(acc)

  defp chunk_writes([part | rest], cursor, acc) do
    case Regex.run(@cursor_move, part) do
      [_, row, col] ->
        chunk_writes(rest, {String.to_integer(row) - 1, String.to_integer(col) - 1}, acc)

      nil when cursor != nil ->
        {row, col} = cursor
        chunk_writes(rest, cursor, [{row, col, strip_ansi(part)} | acc])

      nil ->
        chunk_writes(rest, cursor, acc)
    end
  end

  defp strip_ansi(text), do: String.replace(text, @ansi_escape, "")

  defp place(grid, row, _col, _text, _width, height) when row < 0 or row >= height, do: grid

  defp place(grid, row, col, text, width, _height) do
    List.update_at(grid, row, fn line ->
      line
      |> String.graphemes()
      |> overlay(String.graphemes(text), col)
      |> Enum.take(width)
      |> Enum.join()
    end)
  end

  defp overlay(line, text, col) do
    {before, rest} = Enum.split(line, col)
    before ++ text ++ Enum.drop(rest, length(text))
  end

  @doc """
  The app's current `Drafter.WidgetHierarchy` struct.

  Returns `nil` when the app fails to answer within 1000 ms. The struct's thirteen
  fields:

    * `:root` - the id of the outermost widget, or `nil` before the first render.
      The whole tree is walked from here through `:children`.
    * `:widgets` - id to `%{module:, state:, parent:, children:, order:, pid:}`.
      `:state` is the widget's own state term, `:pid` is set only for a widget
      running in its own `Drafter.WidgetServer`, and `:order` is its position
      among its siblings.
    * `:widget_rects` - id to `%{x:, y:, width:, height:}` in absolute screen
      cells. A widget that was not laid out has no entry.
    * `:focused_widget` - the id holding focus, or `nil`.
    * `:hover_widget` - the id under the pointer, or `nil`.
    * `:widget_counter` - the number of ids generated so far, used to name
      anonymous widgets.
    * `:scroll_containers` - id to `%{viewport_rect:, content_height:,
      content_width:, click_to_scroll:, scroll_exceptions:}` for each scrollable
      container.
    * `:widget_scroll_parents` - id to the id of the scroll container that clips it.
    * `:drag_capture_widget` - the id receiving drag events until the button is
      released, or `nil`.
    * `:preferred_sizes` - id to the height the widget asked for.
    * `:hidden_widgets` - a `MapSet` of ids that are mounted but not drawn.
      Defaults to an empty set.
    * `:event_consumed` - `boolean()`, whether the last event dispatched into the
      hierarchy was claimed by a widget. Defaults to `false`. This is the field to
      assert on when checking that a key or click reached a widget rather than
      falling through to the app.
    * `:widget_overflow` - id to `:ellipsis` for the widgets whose text is
      ellipsised when it does not fit. `:clip` is the default and is not stored,
      so the map holds only the exceptions. Defaults to `%{}`.

      hierarchy = get_widget_hierarchy(ctx)
      assert hierarchy.event_consumed
      assert Map.has_key?(hierarchy.widget_rects, hierarchy.root)
  """
  @spec get_widget_hierarchy(map()) :: Drafter.WidgetHierarchy.t() | nil
  def get_widget_hierarchy(ctx) do
    ask(ctx, {:get_hierarchy, self()})

    receive do
      {:hierarchy, hierarchy} -> hierarchy
    after
      1000 -> nil
    end
  end

  @doc """
  Waits for the app to render.

  `opts`:

    * `:timeout` - milliseconds to wait. Default `1000`.
    * `:min_count` - wait until the driver's total render count reaches this
      integer, polling every 10 ms. Default `nil`, which instead waits for one
      `{:render, count}` message in the calling process's mailbox.

  Returns `:ok`, or `:timeout` if the wait expired. The context argument is accepted
  and unused.

  `:min_count` is the reliable form. The driver sends `{:render, count}` to the
  `:test_pid` on every frame it writes and nothing ever drains that mailbox:
  `send_key/3`, `send_char/2`, `send_click/2`, `send_click/3` and `send_mouse/2`
  synchronise with the app but leave their render messages queued. A bare
  `await_render(ctx)` after any of them therefore takes one of those stale
  messages and returns `:ok` without a new frame having been drawn — a test that
  passes whether or not the thing it waits for happened. Read the count first and
  wait for one more:

      before = Drafter.Test.HeadlessDriver.get_render_count()
      send_key(ctx, :enter)
      :ok = await_render(ctx, min_count: before + 1)

  The mailbox form is only usable in the process `start_headless/3` was given as
  `:test_pid`, since that is the only one notifications reach, and each call
  consumes one message. The input functions already wait for the app to finish, so
  neither form is needed after an input; this is for frames that arrive on their
  own — a timer tick, a pushed data channel.
  """
  @spec await_render(map(), keyword()) :: :ok | :timeout
  def await_render(_ctx, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    min_count = Keyword.get(opts, :min_count, nil)

    if min_count do
      wait_for_render_count(min_count, timeout)
    else
      receive do
        {:render, _count} -> :ok
      after
        timeout -> :timeout
      end
    end
  end

  defp wait_for_render_count(target_count, timeout) do
    poll_until(timeout, 10, fn ->
      HeadlessDriver.get_render_count() >= target_count
    end)
  end

  @doc """
  Polls `condition_fn` until it returns a truthy value.

  `condition_fn` is a one-arity function called with `ctx`.

  `opts`:

    * `:timeout` - milliseconds before giving up. Default `1000`.
    * `:interval` - milliseconds between calls. Default `50`.

  Returns `:ok` once the condition holds, or `:timeout`. The condition is evaluated
  before the first sleep, so a condition that already holds returns immediately.

      wait_for(ctx, fn ctx -> get_state(ctx).loaded end, timeout: 5000)
  """
  @spec wait_for(map(), (map() -> as_boolean(term())), keyword()) :: :ok | :timeout
  def wait_for(ctx, condition_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 50)

    poll_until(timeout, interval, fn -> condition_fn.(ctx) end)
  end

  defp poll_until(timeout, interval, condition_fn) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_poll(deadline, interval, condition_fn)
  end

  defp do_poll(deadline, interval, condition_fn) do
    if condition_fn.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        :timeout
      else
        Process.sleep(interval)
        do_poll(deadline, interval, condition_fn)
      end
    end
  end

  @doc """
  Asserts that a widget matching `selector` is in the hierarchy.

  `ctx` is the context from `start_headless/3`; `selector` is a `String.t()` in the
  forms `Drafter.query_one/1` documents. Returns the matched widget's id, so it can
  be bound and used for a follow-up interaction. Raises `ExUnit.AssertionError` when
  nothing matches.

  A macro: `import Drafter.Test` or `require Drafter.Test` before calling it.

      id = assert_widget_present(ctx, "Button.primary")
      send_click(ctx, id)
  """
  defmacro assert_widget_present(ctx, selector) do
    quote do
      widget_id = Drafter.Test.query_one(unquote(ctx), unquote(selector))

      unless widget_id do
        raise ExUnit.AssertionError,
          message: "Expected widget matching selector #{inspect(unquote(selector))} to be present"
      end

      widget_id
    end
  end

  @doc """
  Asserts that no widget matching `selector` is in the hierarchy.

  Returns `:ok`, or raises `ExUnit.AssertionError` when one matches. A macro, as
  `assert_widget_present/2` is.
  """
  defmacro refute_widget_present(ctx, selector) do
    quote do
      widget_id = Drafter.Test.query_one(unquote(ctx), unquote(selector))

      if widget_id do
        raise ExUnit.AssertionError,
          message:
            "Expected widget matching selector #{inspect(unquote(selector))} to not be present"
      end

      :ok
    end
  end

  @doc """
  Asserts that the first widget matching `selector` has the value `expected`.

  Compares `expected` with `get_widget_value/2` using `==`; the per-widget value
  types are the ones `Drafter.get_widget_value/1` lists. Returns `:ok`. Raises
  `ExUnit.AssertionError` when nothing matches the selector and when the value
  differs. A macro, as `assert_widget_present/2` is.

      assert_widget_value(ctx, "#name", "Ada")
  """
  defmacro assert_widget_value(ctx, selector, expected) do
    quote do
      widget_id = Drafter.Test.query_one(unquote(ctx), unquote(selector))

      unless widget_id do
        raise ExUnit.AssertionError,
          message: "Widget not found: #{inspect(unquote(selector))}"
      end

      actual = Drafter.Test.get_widget_value(unquote(ctx), widget_id)

      unless actual == unquote(expected) do
        raise ExUnit.AssertionError,
          message:
            "Expected widget #{inspect(widget_id)} to have value #{inspect(unquote(expected))}, got #{inspect(actual)}"
      end

      :ok
    end
  end

  @doc """
  Returns once every event injected before this call has been handled by the app.

  An injected event passes from the headless driver to the event manager to the
  app loop. This makes a synchronous round trip to each of those in that order, so
  by the time it returns the event has been forwarded at every hop and processed
  by the loop.

  Call this between injecting an event and asserting on state or screen contents.
  """
  @spec sync(map()) :: :ok
  def sync(ctx) do
    HeadlessDriver.get_render_count()
    sync_event_manager(ctx)
    sync_app(ctx)
    :ok
  end

  defp sync_event_manager(ctx) do
    case event_manager(ctx) do
      nil -> :ok
      manager -> EventManager.sync(manager)
    end
  catch
    :exit, _ -> :ok
  end

  defp event_manager(%{session_pids: %{drafter_event_manager: manager}}) when is_pid(manager) do
    manager
  end

  defp event_manager(%{event_manager: manager}) when is_pid(manager), do: manager
  defp event_manager(_ctx), do: nil

  defp sync_app(%{app_pid: pid}) when is_pid(pid) do
    send(pid, {:get_state, self()})

    receive do
      {:state, _state} -> :ok
    after
      1000 -> :ok
    end
  end

  defp sync_app(_ctx), do: :ok

  defp ask(%{app_pid: pid}, message) when is_pid(pid) do
    send(pid, message)
    :ok
  end

  defp ask(_ctx, message) do
    Drafter.AppRegistry.send_to_loop(message)
    :ok
  end
end
