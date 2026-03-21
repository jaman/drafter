Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule DigitsShowcase do
  use Drafter.App
  import Drafter.App

  alias Drafter.Format

  @metrics [
    {1_234_567_890, :compact, "compact(1_234_567_890)"},
    {8_388_608, :bytes, "bytes(8_388_608)"},
    {0.9975, :percent_ratio, "percent(0.9975, as_ratio: true)"},
    {72.4, :percent, "percent(72.4, decimals: 1)"},
    {-4_800, :compact, "compact(-4_800)"},
    {1_099_511_627_776, :bytes, "bytes(1_099_511_627_776)"},
    {0.001, :percent_ratio, "percent(0.001, as_ratio: true)"},
    {1_500, :compact, "compact(1_500)"}
  ]

  @stat_panels [
    %{label: "CPU 91% — line high", value: "91.4%", color: {220, 80, 80}, bg_min: 0, bg_max: 100,
      history: [72, 78, 80, 85, 82, 88, 90, 87, 91, 90, 93, 91]},
    %{label: "Memory 8.2GB — mid", value: "8.2GB", color: {80, 140, 220}, bg_min: 0, bg_max: 16,
      history: [6.1, 6.4, 6.8, 7.0, 7.2, 7.5, 7.8, 7.9, 8.0, 8.1, 8.2, 8.2]},
    %{label: "Uptime 16% — line low", value: "16.0%", color: {80, 200, 120}, bg_min: 0, bg_max: 100,
      history: [13, 14, 12, 15, 14, 16, 15, 17, 15, 16, 15, 16]}
  ]

  def mount(_props) do
    formatted = Enum.map(@metrics, fn {value, fmt, _desc} -> format(value, fmt) end)
    options = Enum.map(Enum.with_index(@metrics), fn {{_v, _f, desc}, i} -> {desc, i} end)
    %{selected: 0, formatted: formatted, options: options}
  end

  def keybindings, do: [{"↑↓", "select"}, {"q", "quit"}]

  def render(state) do
    text = Enum.at(state.formatted, state.selected)
    {_value, _fmt, desc} = Enum.at(@metrics, state.selected)

    vertical([
      header("Digits Widget — Large & Small"),
      horizontal(
        [
          vertical(
            [
              label("Large  (7×5)", style: %{bold: true, fg: :cyan}),
              digits(text, size: :large, align: :center, style: %{fg: {100, 220, 160}})
            ],
            flex: 1
          ),
          vertical(
            [
              label("Small  (5×3)", style: %{bold: true, fg: :cyan}),
              digits(text, size: :small, align: :center, style: %{fg: {255, 180, 80}})
            ],
            flex: 1
          )
        ],
        flex: 1,
        gap: 2
      ),
      rule(title: desc, title_align: :left),
      option_list(state.options, on_select: :metric_selected, height: 8),
      rule(title: "bg_data — area chart composite", title_align: :left),
      horizontal(
        Enum.map(@stat_panels, fn %{label: label, value: value, color: color, bg_min: bg_min, bg_max: bg_max, history: history} ->
          vertical(
            [
              label(label, style: %{bold: true}, align: :center),
              digits(value,
                size: :large,
                align: :center,
                bg_data: history,
                color: color,
                bg_min: bg_min,
                bg_max: bg_max
              )
            ],
            flex: 1
          )
        end),
        gap: 1,
        height: 12
      ),
      footer()
    ])
  end

  def handle_event(:metric_selected, i, state) when is_integer(i) do
    {:ok, %{state | selected: i}}
  end

  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp format(value, :compact), do: Format.compact(value)
  defp format(value, :bytes), do: Format.bytes(value)
  defp format(value, :percent_ratio), do: Format.percent(value, as_ratio: true, decimals: 1)
  defp format(value, :percent), do: Format.percent(value, decimals: 1)

end

Drafter.run(DigitsShowcase)
