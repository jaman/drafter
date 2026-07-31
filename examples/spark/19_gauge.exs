Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule GaugeDemo do
  use Drafter

  @step 0.004
  @min_distance 0.10
  @min_gauge_height 3
  @max_gauge_height 30

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :+, "grow" do
    {:ok, %{state | gauge_height: min(@max_gauge_height, state.gauge_height + 1)}}
  end

  keybinding :-, "shrink" do
    {:ok, %{state | gauge_height: max(@min_gauge_height, state.gauge_height - 1)}}
  end

  def handle_event(:grow_gauge, _data, state),
    do: {:ok, %{state | gauge_height: min(@max_gauge_height, state.gauge_height + 1)}}

  def handle_event(:shrink_gauge, _data, state),
    do: {:ok, %{state | gauge_height: max(@min_gauge_height, state.gauge_height - 1)}}

  def handle_event(_event, state), do: {:noreply, state}

  def mount(_props) do
    %{
      animated_value: 0.20,
      target: random_target(0.20, :up),
      direction: :up,
      gauge_height: 7
    }
  end

  def on_ready(state) do
    Drafter.set_interval(16, :fps)
    state
  end

  def on_timer(:fps, state) do
    step = if state.direction == :up, do: @step, else: -@step
    new_value = clamp(Float.round(state.animated_value + step, 4))

    reached =
      (state.direction == :up and new_value >= state.target) or
        (state.direction == :down and new_value <= state.target)

    if reached do
      new_dir = if state.direction == :up, do: :down, else: :up
      new_target = random_target(new_value, new_dir)
      %{state | animated_value: new_value, target: new_target, direction: new_dir}
    else
      %{state | animated_value: new_value}
    end
  end

  def on_timer(_id, state), do: state

  def render(state) do
    vertical([
      header("GAUGE DEMO"),
      horizontal(
        [
          gauge(renderer: :pixel, value: 0.27, label: "CPU Busy", flex: 1, height: 6),
          gauge(renderer: :pixel, value: 0.73, label: "RAM Used", flex: 1, height: 6),
          gauge(renderer: :pixel, value: 0.96, label: "Root FS", flex: 1, height: 6),
          gauge(renderer: :pixel, value: state.animated_value, label: "Sys Load", flex: 1, height: 6)
        ],
        gap: 2
      ),
      label(""),
      label("Resize Gauge  (height: #{state.gauge_height})", style: %{bold: true, fg: :cyan}),
      horizontal(
        [
          button("−", on_click: :shrink_gauge),
          button("+", on_click: :grow_gauge)
        ],
        gap: 1
      ),
      gauge(renderer: :pixel, value: 0.95, label: "Resize Me", height: state.gauge_height),
      footer(bindings: [{"q", "Quit"}, {"+/-", "Resize"}])
    ])
  end

  defp clamp(v), do: v |> max(0.0) |> min(1.0)

  defp random_target(current, :up) do
    min_t = min(1.0, current + @min_distance)
    min_t + :rand.uniform() * (1.0 - min_t)
  end

  defp random_target(current, :down) do
    max_t = max(0.0, current - @min_distance)
    :rand.uniform() * max_t
  end
end

Drafter.run(GaugeDemo)
