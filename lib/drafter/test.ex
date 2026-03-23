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

  alias Drafter.Test.{Harness, HeadlessDriver}

  def start_headless(app_module, props \\ %{}, opts \\ []) do
    case Harness.start_app(app_module, props, opts) do
      {:ok, ctx} ->
        Process.sleep(50)
        ctx

      {:error, reason} ->
        raise "Failed to start headless app: #{inspect(reason)}"
    end
  end

  def stop(ctx) do
    Harness.stop_app(ctx)
  end

  def send_key(_ctx, key, modifiers \\ []) do
    event =
      if modifiers == [] do
        {:key, key}
      else
        {:key, key, modifiers}
      end

    HeadlessDriver.inject_event(event)
    Process.sleep(10)
    :ok
  end

  def send_char(ctx, char) when is_binary(char) do
    send_char(ctx, :binary.first(char))
  end

  def send_char(_ctx, char) when is_integer(char) do
    event = {:char, char}
    HeadlessDriver.inject_event(event)
    Process.sleep(10)
    :ok
  end

  def send_click(_ctx, x, y) when is_integer(x) and is_integer(y) do
    event = {:mouse, %{type: :mouse_up, x: x, y: y, button: :left}}
    HeadlessDriver.inject_event(event)
    Process.sleep(10)
    :ok
  end

  def send_click(_ctx, widget_id) when is_atom(widget_id) do
    Drafter.AppRegistry.send_to_loop({:widget_click, widget_id})
    Process.sleep(10)
    :ok
  end

  def send_mouse(_ctx, event) do
    HeadlessDriver.inject_event({:mouse, event})
    Process.sleep(10)
    :ok
  end

  def get_state(_ctx) do
    Drafter.AppRegistry.send_to_loop({:get_state, self()})

    receive do
      {:state, state} -> state
    after
      1000 -> raise "Timeout waiting for app state"
    end
  end

  def get_widget_value(_ctx, widget_id) do
    Drafter.AppRegistry.send_to_loop({:get_widget_value, widget_id, self()})

    receive do
      {:widget_value, ^widget_id, value} -> value
    after
      1000 -> nil
    end
  end

  def get_widget_state(_ctx, widget_id) do
    Drafter.AppRegistry.send_to_loop({:get_widget_state, widget_id, self()})

    receive do
      {:widget_state, ^widget_id, state} -> state
    after
      1000 -> nil
    end
  end

  def query_one(_ctx, selector) do
    Drafter.AppRegistry.send_to_loop({:query_one, selector, self()})

    receive do
      {:query_result, :one, result} -> result
    after
      1000 -> nil
    end
  end

  def query_all(_ctx, selector) do
    Drafter.AppRegistry.send_to_loop({:query_all, selector, self()})

    receive do
      {:query_result, :all, result} -> result
    after
      1000 -> []
    end
  end

  def get_rendered_output(_ctx) do
    HeadlessDriver.get_buffer()
  end

  def get_widget_hierarchy(_ctx) do
    Drafter.AppRegistry.send_to_loop({:get_hierarchy, self()})

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
end
