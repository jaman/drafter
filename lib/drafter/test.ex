defmodule Drafter.Test do
  @moduledoc """
  Primary API for headless testing of TUI applications with ExUnit.

  Start an app without a real terminal using `start_headless/3`, interact with
  it by sending keyboard, character, mouse, or click events, query the widget
  hierarchy, and read app or widget state. Call `stop/1` to cleanly shut down
  the test instance.

  Three assertion macros are provided for use inside ExUnit tests:
  `assert_widget_present/2`, `refute_widget_present/2`, and
  `assert_widget_value/3`. Selectors passed to query functions are matched
  against widget type names as lowercase strings (e.g. `"button"`, `"textinput"`).
  """

  alias Drafter.Event.Manager, as: EventManager
  alias Drafter.Test.{Harness, HeadlessDriver}

  def start_headless(app_module, props \\ %{}, opts \\ []) do
    case Harness.start_app(app_module, props, opts) do
      {:ok, ctx} ->
        sync(ctx)
        ctx

      {:error, reason} ->
        raise "Failed to start headless app: #{inspect(reason)}"
    end
  end

  def stop(ctx) do
    Harness.stop_app(ctx)
  end

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

  def send_char(ctx, char) when is_binary(char) do
    send_char(ctx, :binary.first(char))
  end

  def send_char(ctx, char) when is_integer(char) do
    event = {:char, char}
    HeadlessDriver.inject_event(event)
    sync(ctx)
  end

  def send_click(ctx, x, y) when is_integer(x) and is_integer(y) do
    event = {:mouse, %{type: :mouse_up, x: x, y: y, button: :left}}
    HeadlessDriver.inject_event(event)
    sync(ctx)
  end

  def send_click(ctx, widget_id) when is_atom(widget_id) do
    ask(ctx, {:widget_click, widget_id})
    sync(ctx)
  end

  def send_mouse(ctx, event) do
    HeadlessDriver.inject_event({:mouse, event})
    sync(ctx)
  end

  def get_state(ctx) do
    ask(ctx, {:get_state, self()})

    receive do
      {:state, state} -> state
    after
      1000 -> raise "Timeout waiting for app state"
    end
  end

  def get_widget_value(ctx, widget_id) do
    ask(ctx, {:get_widget_value, widget_id, self()})

    receive do
      {:widget_value, ^widget_id, value} -> value
    after
      1000 -> nil
    end
  end

  def get_widget_state(ctx, widget_id) do
    ask(ctx, {:get_widget_state, widget_id, self()})

    receive do
      {:widget_state, ^widget_id, state} -> state
    after
      1000 -> nil
    end
  end

  def query_one(ctx, selector) do
    ask(ctx, {:query_one, selector, self()})

    receive do
      {:query_result, :one, result} -> result
    after
      1000 -> nil
    end
  end

  def query_all(ctx, selector) do
    ask(ctx, {:query_all, selector, self()})

    receive do
      {:query_result, :all, result} -> result
    after
      1000 -> []
    end
  end

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

  def get_widget_hierarchy(ctx) do
    ask(ctx, {:get_hierarchy, self()})

    receive do
      {:hierarchy, hierarchy} -> hierarchy
    after
      1000 -> nil
    end
  end

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
  Returns once an injected event has been handled by the application.

  Injected events travel driver to event manager to app loop, so a message sent
  straight to the loop can overtake them — mailbox order holds per sender pair,
  not across a chain. This walks the chain in order instead: each hop is a
  synchronous round trip, and each has already forwarded the event by the time it
  answers, so the event sits ahead of the final round trip and is handled before
  it returns.
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
