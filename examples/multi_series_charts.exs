Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule MultiSeriesCharts do
  use Drafter.App
  import Drafter.App

  @palette [
    {100, 200, 255},
    {255, 130, 80},
    {80, 255, 150},
    {255, 100, 180},
    {200, 180, 60},
    {180, 100, 255}
  ]

  def mount(_props) do
    %{timestamp: 0, phase: 0.0}
  end

  def keybindings, do: [{"q", "quit"}]

  def on_ready(state) do
    Drafter.set_interval(80, :tick)
    state
  end

  def on_timer(:tick, state) do
    %{state | timestamp: state.timestamp + 1, phase: state.phase + 0.05}
  end

  def render(state) do
    p = state.phase

    sine = Enum.map(0..79, fn i -> :math.sin(i * 0.15 + p) * 40 + 50 end)
    cosine = Enum.map(0..79, fn i -> :math.cos(i * 0.15 + p) * 40 + 50 end)
    triangle = Enum.map(0..79, fn i -> abs(rem(i, 20) - 10) * 8.0 + 10 + :math.sin(p) * 5 end)
    sawtooth = Enum.map(0..79, fn i -> rem(i, 20) / 20.0 * 70 + 15 end)

    inbound = Enum.map(0..59, fn i -> :math.sin(i * 0.2 + p) * 80 + :math.sin(i * 0.7 + p * 0.5) * 30 end)
    outbound = Enum.map(0..59, fn i -> -(:math.cos(i * 0.18 + p) * 60 + :math.sin(i * 0.5 + p) * 40) end)

    monthly_a = [42, 58, 71, 65, 83, 91, 78, 94, 88, 102, 95, 110]
    monthly_b = [35, 48, 55, 72, 68, 75, 82, 70, 88, 79, 98, 89]
    monthly_c = [20, 31, 44, 38, 52, 49, 61, 58, 67, 72, 78, 85]

    stacked_a = [30, 45, 60, 55, 70, 80]
    stacked_b = [20, 25, 30, 28, 35, 40]
    stacked_c = [10, 15, 18, 22, 20, 25]

    temp_ranges = [
      [-5, 3], [-3, 6], [0, 10], [4, 15], [9, 22], [14, 28],
      [17, 32], [16, 31], [11, 24], [5, 16], [0, 8], [-4, 4]
    ]

    scatter_a = Enum.map(0..29, fn i -> [i * 3, :math.sin(i * 0.4 + p) * 40 + 50] end)
    scatter_b = Enum.map(0..29, fn i -> [i * 3, :math.cos(i * 0.4 + p) * 30 + 60] end)
    scatter_c = Enum.map(0..29, fn i -> [i * 3 + 15, :math.sin(i * 0.6 + p * 1.3) * 35 + 45] end)

    vertical([
      header("Multi-Series & Extended Bar Charts  (scroll, ← → to pan)", show_clock: true),
      scrollable(
        [
          section("Multi-Series Line: Sine + Cosine + Triangle + Sawtooth"),
          chart([sine, cosine, triangle, sawtooth],
            id: :line1,
            chart_type: :line,
            height: 8,
            colors: Enum.take(@palette, 4),
            _render_timestamp: state.timestamp
          ),
          gap(),
          section("Negative Values: Network IO — inbound (+) vs outbound (−)"),
          label("Values span −150 to +150 MB/s; zero-line visible with show_axes: true",
            style: %{fg: {120, 120, 130}}
          ),
          chart([inbound, outbound],
            id: :net,
            chart_type: :line,
            height: 8,
            min_value: -150,
            max_value: 150,
            show_axes: true,
            colors: [{80, 220, 140}, {255, 100, 100}],
            _render_timestamp: state.timestamp
          ),
          gap(),
          section("Clustered Bar: Monthly revenue — bar_gap: 0 (default) vs bar_gap: 1"),
          horizontal(
            [
              chart([monthly_a, monthly_b, monthly_c],
                id: :cbar,
                chart_type: :clustered_bar,
                height: 8,
                colors: [Enum.at(@palette, 0), Enum.at(@palette, 1), Enum.at(@palette, 2)],
                flex: 1
              ),
              chart([monthly_a, monthly_b, monthly_c],
                id: :cbar_gap,
                chart_type: :clustered_bar,
                height: 8,
                bar_gap: 1,
                colors: [Enum.at(@palette, 0), Enum.at(@palette, 1), Enum.at(@palette, 2)],
                flex: 1
              )
            ],
            gap: 2
          ),
          gap(),
          section("Stacked Bar: side by side — no gap (left) vs gap: 1 (right)"),
          horizontal(
            [
              chart([stacked_a, stacked_b, stacked_c],
                id: :sbar,
                chart_type: :stacked_bar,
                height: 8,
                colors: [Enum.at(@palette, 2), Enum.at(@palette, 4), Enum.at(@palette, 5)],
                flex: 1
              ),
              chart([stacked_a, stacked_b, stacked_c],
                id: :sbar_gap,
                chart_type: :stacked_bar,
                height: 8,
                bar_gap: 1,
                colors: [Enum.at(@palette, 2), Enum.at(@palette, 4), Enum.at(@palette, 5)],
                flex: 1
              )
            ],
            gap: 2
          ),
          gap(),
          section("Range Bar: Monthly temperature range °C (low → high)"),
          chart(temp_ranges,
            id: :rbar,
            chart_type: :range_bar,
            height: 8,
            min_value: -10,
            max_value: 40,
            color: {255, 160, 60},
            show_axes: true
          ),
          gap(),
          section("Multi-Series Scatter: Three animated point clouds"),
          chart([scatter_a, scatter_b, scatter_c],
            id: :scatter1,
            chart_type: :scatter,
            height: 8,
            colors: [Enum.at(@palette, 0), Enum.at(@palette, 1), Enum.at(@palette, 2)],
            _render_timestamp: state.timestamp
          ),
          label("")
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp section(title) do
    label(title, style: %{fg: {100, 150, 255}, bold: true})
  end

  defp gap, do: label("")
end

Drafter.run(MultiSeriesCharts)
