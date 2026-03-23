defmodule Drafter.Examples.Counter do
  @moduledoc """
  A simple counter application demonstrating Drafter basics.

  Shows a counter value with increment/decrement buttons.
  Press 'q' or Escape to quit.
  """

  use Drafter.App

  def mount(_props) do
    %{
      counter: 0,
      message: "Welcome to Drafter!"
    }
  end

  def render(state, rect) do
    {Drafter.Widget.Container, %{
      children: [
        {Drafter.Widget.Label, %{
          text: state.message,
          style: %{bold: true, fg: {0, 255, 0}},
          align: :center
        }},
        {Drafter.Widget.Label, %{
          text: "Counter: #{state.counter}",
          style: %{fg: {255, 255, 255}},
          align: :center
        }},
        {Drafter.Widget.Container, %{
          layout: :horizontal,
          children: [
            {Drafter.Widget.Button, %{
              text: "Decrement (-)",
              style: %{fg: {255, 100, 100}},
              on_click: fn -> send(self(), {:tui_event, :decrement}) end
            }},
            {Drafter.Widget.Button, %{
              text: "Increment (+)",
              style: %{fg: {100, 255, 100}},
              on_click: fn -> send(self(), {:tui_event, :increment}) end
            }}
          ]
        }},
        {Drafter.Widget.Label, %{
          text: "Controls: Space/+/→/↑ = increment, -/←/↓ = decrement, Enter = reset, q/Esc = quit",
          style: %{dim: true},
          align: :center
        }}
      ],
      layout: :vertical,
      padding: 2,
      border_style: :rounded
    }}
    |> render_widget(rect)
  end

  def handle_event(:increment, state) do
    new_state = %{state |
      counter: state.counter + 1,
      message: "Incremented!"
    }
    {:ok, new_state}
  end

  def handle_event(:decrement, state) do
    new_state = %{state |
      counter: state.counter - 1,
      message: "Decremented!"
    }
    {:ok, new_state}
  end

  def handle_event({:key, :space}, state) do
    handle_event(:increment, state)
  end

  def handle_event({:key, :enter}, state) do
    new_state = %{state |
      counter: 0,
      message: "Counter reset!"
    }
    {:ok, new_state}
  end

  def handle_event({:key, :+}, state) do
    handle_event(:increment, state)
  end

  def handle_event({:key, :-}, state) do
    handle_event(:decrement, state)
  end

  def handle_event({:key, :right}, state) do
    handle_event(:increment, state)
  end

  def handle_event({:key, :left}, state) do
    handle_event(:decrement, state)
  end

  def handle_event({:key, :up}, state) do
    handle_event(:increment, state)
  end

  def handle_event({:key, :down}, state) do
    handle_event(:decrement, state)
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_widget({module, props}, rect) do
    state = module.mount(props)
    case module.render(state, rect) do
      strips when is_list(strips) -> strips
      {:error, _} -> []
    end
  end
end
