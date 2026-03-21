Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule Clock do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{time: current_time()}
  end

  def keybindings, do: [{"q", "quit"}]

  def render(state) do
    vertical([
      digits(state.time, align: :center, style: %{fg: {100, 200, 255}}),
      footer()
    ])
  end

  def on_ready(state) do
    Drafter.set_interval(1000, :tick)
    state
  end

  def on_timer(:tick, state), do: %{state | time: current_time()}

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp current_time do
    {_, {h, m, s}} = :calendar.local_time()

    [h, m, s]
    |> Enum.map_join(":", &(Integer.to_string(&1) |> String.pad_leading(2, "0")))
  end
end

Drafter.run(Clock)
