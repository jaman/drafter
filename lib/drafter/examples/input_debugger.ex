defmodule Drafter.Examples.InputDebugger do
  use Drafter.App
  import Drafter.App

  @log_file "input_debug.log"

  def mount(_props) do
    File.write!(@log_file, "=== Input Debugger Started #{DateTime.utc_now()} ===\n")

    %{
      events: [],
      max_events: 20
    }
  end

  def render(state) do
    vertical([
      label("Input Debugger - Press Ctrl+Q or Ctrl+D to quit"),
      label("─────────────────────────────────────────────────"),
      label("Events are logged to: #{@log_file}"),
      label("─────────────────────────────────────────────────"),
      label("Recent Events (newest first):"),
      label(""),
      vertical(
        Enum.map(state.events, fn {timestamp, event_str} ->
          label("[#{timestamp}] #{event_str}")
        end)
      )
    ])
  end

  def handle_event({:key, :q, [:ctrl]}, _state) do
    log_event("QUIT: Ctrl+Q (0x11)")
    {:stop, :normal}
  end

  def handle_event({:key, :d, [:ctrl]}, _state) do
    log_event("QUIT: Ctrl+D (0x04)")
    {:stop, :normal}
  end

  def handle_event({:key, :c, [:ctrl]}, _state) do
    log_event("QUIT: Ctrl+C (0x03)")
    {:stop, :normal}
  end

  def handle_event({:key, key, modifiers}, state) do
    event_str = "KEY: #{inspect(key)} modifiers=#{inspect(modifiers)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:key, key}, state) do
    event_str = "KEY: #{inspect(key)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:mouse, %{type: :mouse_up} = data}, state) do
    event_str = "MOUSE CLICK: #{inspect(data)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:mouse, %{type: :mouse_down} = data}, state) do
    event_str = "MOUSE DOWN: #{inspect(data)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:mouse, %{type: :move} = data}, state) do
    event_str = "MOUSE MOVE: x=#{data.x} y=#{data.y}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:mouse, %{type: :drag} = data}, state) do
    event_str = "MOUSE DRAG: #{inspect(data)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:mouse, %{type: :scroll} = data}, state) do
    event_str = "MOUSE SCROLL: #{inspect(data)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:mouse, data}, state) do
    event_str = "MOUSE OTHER: #{inspect(data)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event(:resize, state) do
    event_str = "RESIZE"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event({:resize, {width, height}}, state) do
    event_str = "RESIZE: width=#{width} height=#{height}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  def handle_event(event, state) do
    event_str = "UNKNOWN: #{inspect(event)}"
    log_event(event_str)
    {:ok, add_event(state, event_str)}
  end

  defp add_event(state, event_str) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S.%f") |> String.slice(0..11)
    events = [{timestamp, event_str} | state.events] |> Enum.take(state.max_events)
    %{state | events: events}
  end

  defp log_event(event_str) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    line = "[#{timestamp}] #{event_str}\n"
    File.write!(@log_file, line, [:append])
  end
end
