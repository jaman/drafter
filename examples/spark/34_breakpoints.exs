Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule Breakpoints do
  use Drafter

  @breakpoints [{120, 6}, {80, 4}, {40, 2}, {0, 1}]

  state %{width: 80, height: 24}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def on_ready(state) do
    {width, height} = Drafter.Compositor.get_screen_size()
    %{state | width: width, height: height}
  end

  def handle_event({:resize, {width, height}}, state) do
    {:ok, %{state | width: width, height: height}}
  end

  def render(state) do
    columns = columns_for(state.width)

    vertical([
      header("Breakpoints — resize the terminal"),
      label("#{state.width}x#{state.height} cells → #{columns} column grid", style: %{bold: true}),
      label(breakpoint_table(state.width), style: %{fg: :cyan}),
      rule(),
      {:grid, tiles(columns * 3), [grid_size: columns, padding: 1]},
      footer()
    ])
  end

  defp columns_for(width) do
    {_min, columns} = Enum.find(@breakpoints, {0, 1}, fn {min, _} -> width >= min end)
    columns
  end

  defp breakpoint_table(width) do
    @breakpoints
    |> Enum.reverse()
    |> Enum.map_join("   ", fn {min, columns} ->
      marker = if columns == columns_for(width), do: "▶", else: " "
      "#{marker}#{min}+ → #{columns}"
    end)
  end

  defp tiles(count) do
    for n <- 1..count do
      placeholder(label: "Tile #{n}")
    end
  end
end

Drafter.run(Breakpoints)
