Mix.install([{:drafter, path: Path.join(__DIR__, "..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule BrailleAreaDemo do
  use Drafter.App
  import Drafter.App

  @max_points 120

  def mount(_props) do
    %{
      disk_read: generate_initial(:read),
      disk_write: generate_initial(:write),
      disk_seek: generate_initial(:seek),
      tick: 0
    }
  end

  def keybindings, do: [{"q", "quit"}]

  def on_ready(state) do
    Drafter.set_interval(200, :tick)
    state
  end

  def on_timer(:tick, state) do
    t = state.tick

    %{
      state
      | disk_read: append_capped(state.disk_read, next_value(t, :read)),
        disk_write: append_capped(state.disk_write, next_value(t, :write)),
        disk_seek: append_capped(state.disk_seek, next_value(t, :seek)),
        tick: t + 1
    }
  end

  def render(state) do
    vertical([
      label("Disk I/O — Braille Stacked Area", style: %{bold: true, color: {180, 180, 220}}),
      rule(),
      chart(
        [state.disk_read, state.disk_write, state.disk_seek],
        chart_type: :braille_area,
        colors: [{80, 200, 80}, {200, 180, 40}, {220, 60, 60}],
        show_baseline: true,
        height: 10
      ),
      horizontal([
        label("■ Read ", style: %{color: {80, 200, 80}}),
        label("■ Write ", style: %{color: {200, 180, 40}}),
        label("■ Seek ", style: %{color: {220, 60, 60}}),
        label("  (stacked)", style: %{color: {100, 100, 100}})
      ]),
      rule(),
      label("Net Cash Flow — Symmetric (default)", style: %{bold: true, color: {180, 180, 220}}),
      rule(),
      chart(
        [state.disk_read |> Enum.map(&(&1 - 55)), state.disk_write |> Enum.map(&(&1 * -1))],
        chart_type: :braille_area,
        colors: [{80, 180, 220}, {220, 100, 80}],
        show_baseline: true,
        show_axes: true,
        height: 8
      ),
      horizontal([
        label("■ Revenue ", style: %{color: {80, 180, 220}}),
        label("■ Expenses ", style: %{color: {220, 100, 80}}),
        label("  (symmetric ±scale)", style: %{color: {100, 100, 100}})
      ]),
      rule(),
      label("Net Cash Flow — Independent Scale", style: %{bold: true, color: {180, 180, 220}}),
      rule(),
      chart(
        [state.disk_read |> Enum.map(&(&1 - 55)), state.disk_write |> Enum.map(&(&1 * -1))],
        chart_type: :braille_area,
        colors: [{80, 180, 220}, {220, 100, 80}],
        show_baseline: true,
        show_axes: true,
        zero_center: :independent,
        height: 8
      ),
      horizontal([
        label("■ Revenue ", style: %{color: {80, 180, 220}}),
        label("■ Expenses ", style: %{color: {220, 100, 80}}),
        label("  (independent ±scale)", style: %{color: {100, 100, 100}})
      ])
    ])
  end

  defp generate_initial(kind) do
    for i <- 0..(@max_points - 1), do: next_value(i, kind)
  end

  defp next_value(tick, :read) do
    base = 50 + 30 * :math.sin(tick * 0.07)
    dip = if rem(tick, 40) in 18..24, do: -35.0, else: 0.0
    max(0, base + dip + :rand.uniform() * 20)
  end

  defp next_value(tick, :write) do
    base = 18 + 10 * :math.sin(tick * 0.11 + 1.5)
    max(0, base + :rand.uniform() * 8)
  end

  defp next_value(tick, :seek) do
    spike = if :rand.uniform() < 0.12, do: 30 + :rand.uniform() * 40, else: 0.0
    base = 3 + 2 * :math.sin(tick * 0.15)
    max(0, base + spike + :rand.uniform() * 2)
  end

  defp append_capped(list, val) do
    list = list ++ [val]
    if length(list) > @max_points, do: tl(list), else: list
  end
end

Drafter.run(BrailleAreaDemo)
