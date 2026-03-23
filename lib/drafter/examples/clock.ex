defmodule Drafter.Examples.Clock do
  @moduledoc """
  A clock application showing the current time in large digits.

  Updates every second to display the current time.
  Press 'q' or Escape to quit.
  """

  use Drafter.App

  def mount(_props) do
    %{
      time: format_current_time()
    }
  end

  def render(state, rect) do
    {Drafter.Widget.Digits, %{
      text: state.time,
      align: :center,
      style: %{fg: {100, 200, 255}}
    }}
    |> render_widget(rect)
  end

  def on_ready(state) do
    Drafter.set_interval(1000, :update_clock)
    state
  end

  def on_timer(:update_clock, state) do
    %{state | time: format_current_time()}
  end

  defp format_current_time do
    {_, {hour, minute, second}} = :calendar.local_time()

    hour_str = hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute_str = minute |> Integer.to_string() |> String.pad_leading(2, "0")
    second_str = second |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{hour_str}:#{minute_str}:#{second_str}"
  end

  defp render_widget({module, props}, rect) do
    state = module.mount(props)
    case module.render(state, rect) do
      strips when is_list(strips) -> strips
      {:error, _} -> []
    end
  end
end
