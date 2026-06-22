Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule ChartPerf do
  use Drafter.App
  import Drafter.App

  @point_counts [500, 5_000, 50_000]

  def mount(_props) do
    selected = 1
    count = Enum.at(@point_counts, selected)

    %{
      selected_count: selected,
      series_a: generate_series(count, 0),
      series_b: generate_series(count, 100),
      series_c: generate_series(count, 200),
      series_d: generate_series(count, 300),
      last_render_ms: nil,
      tick_count: 0
    }
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :"1", "500 pts" do
    reload(state, 0)
  end

  keybinding :"2", "5k pts" do
    reload(state, 1)
  end

  keybinding :"3", "50k pts" do
    reload(state, 2)
  end

  def on_ready(state) do
    Drafter.set_interval(2, :fps)
    state
  end

  def on_timer(:fps, state) do
    t0 = System.monotonic_time(:millisecond)

    new_a = tl(state.series_a) ++ [walk(List.last(state.series_a))]
    new_b = tl(state.series_b) ++ [walk(List.last(state.series_b))]
    new_c = tl(state.series_c) ++ [walk(List.last(state.series_c))]
    new_d = tl(state.series_d) ++ [walk(List.last(state.series_d))]

    t1 = System.monotonic_time(:millisecond)

    %{
      state
      | series_a: new_a,
        series_b: new_b,
        series_c: new_c,
        series_d: new_d,
        last_render_ms: t1 - t0,
        tick_count: state.tick_count + 1
    }
  end

  def render(state) do
    count = Enum.at(@point_counts, state.selected_count)

    status =
      if state.last_render_ms, do: "data update: #{state.last_render_ms}ms", else: "initialising"

    vertical([
      header("Chart Performance — #{format_count(count)} data points  |  #{status}"),
      scrollable(
        [
          label("Series A (line, #{format_count(count)} pts):"),
          chart(state.series_a,
            chart_type: :line,
            height: 8,
            color: {100, 200, 255},
            show_axes: true
          ),
          label(""),
          label("Series B (area inverted, #{format_count(count)} pts):"),
          chart(state.series_b,
            chart_type: :area,
            height: 8,
            color: {255, 150, 80},
            area_fill: :inverted,
            show_axes: true
          ),
          label(""),
          label("Series C (line, #{format_count(count)} pts):"),
          chart(state.series_c,
            chart_type: :line,
            height: 8,
            color: {150, 255, 150},
            show_axes: true
          ),
          label(""),
          label("Series D (area, #{format_count(count)} pts):"),
          chart(state.series_d,
            chart_type: :area,
            height: 8,
            color: {255, 100, 200},
            show_axes: true
          ),
          label(""),
          label("Multi-series line A+B (#{format_count(count)} pts each):"),
          chart([state.series_a, state.series_b],
            chart_type: :line,
            height: 8,
            colors: [{100, 200, 255}, {255, 150, 80}]
          ),
          label(""),
          label("Multi-series line C+D (#{format_count(count)} pts each):"),
          chart([state.series_c, state.series_d],
            chart_type: :line,
            height: 8,
            colors: [{150, 255, 150}, {255, 100, 200}]
          ),
          label(""),
          label("Multi-series scope-style raw A+B+C+D (#{format_count(count)} pts each):"),
          chart([state.series_a, state.series_b, state.series_c, state.series_d],
            chart_type: :line,
            height: 10,
            raw_data: true,
            line_thickness: 1,
            colors: [{100, 200, 255}, {255, 150, 80}, {150, 255, 150}, {255, 100, 200}]
          ),
          label(""),
          label("Clustered bar A+B (#{format_count(count)} pts):"),
          chart([state.series_a, state.series_b],
            chart_type: :clustered_bar,
            height: 6,
            colors: [{100, 200, 255}, {255, 150, 80}]
          ),
          label(""),
          label("Bar chart A (#{format_count(count)} pts):"),
          chart(state.series_a,
            chart_type: :bar,
            height: 3,
            color: {150, 255, 150}
          )
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp reload(state, idx) do
    count = Enum.at(@point_counts, idx)

    {:ok,
     %{
       state
       | selected_count: idx,
         series_a: generate_series(count, 0),
         series_b: generate_series(count, 100),
         series_c: generate_series(count, 200),
         series_d: generate_series(count, 300)
     }}
  end

  defp walk(prev) do
    delta = (:rand.uniform() - 0.5) * 5
    max(1.0, min(99.0, prev + delta))
  end

  defp generate_series(count, seed_offset) do
    :rand.seed(:exsss, {seed_offset, 0, 0})

    Enum.scan(1..count, 50.0, fn _, prev ->
      delta = (:rand.uniform() - 0.5) * 5
      max(1.0, min(99.0, prev + delta))
    end)
  end

  defp format_count(n) when n >= 1000, do: "#{div(n, 1000)}k"
  defp format_count(n), do: "#{n}"
end

Drafter.run(ChartPerf)
