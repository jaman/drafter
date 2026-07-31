Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule SplitPaneDemo do
  use Drafter, runtime: :reducer

  @lorem """
  Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor
  incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
  exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
  dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
  Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt
  mollit anim id est laborum.
  """

  @items Enum.map(1..20, fn i -> "Item #{i}: #{String.duplicate("▬", rem(i * 7, 24) + 4)}" end)

  def mount(_props) do
    %{log_lines: ["App started", "Split pane demo ready", "Drag the divider to resize"]}
  end

  def on_ready(state) do
    Drafter.set_interval(2000, :tick)
    state
  end

  keybinding :tab, "focus next" do
    {:noreply, state}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def on_timer(:tick, state) do
    ts = DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
    new_line = "Tick at #{ts}"
    lines = (state.log_lines ++ [new_line]) |> Enum.take(-50)
    %{state | log_lines: lines}
  end

  def render(state) do
    vertical([
      header("SplitPane Demo — drag the │ divider or use Alt+Arrows"),
      split_pane(
        [
          split_pane(
            [
              vertical(
                [
                  label("Left pane — option list:", style: %{bold: true}),
                  scrollable(
                    Enum.map(@items, fn item -> label(item) end),
                    flex: 1
                  )
                ],
                flex: 1,
                gap: 0
              ),
              vertical(
                [
                  label("Middle pane — text:", style: %{bold: true}),
                  label(@lorem |> String.trim())
                ],
                flex: 1
              )
            ],
            orientation: :horizontal,
            ratio: 0.4,
            id: :left_split,
            flex: 1
          ),
          vertical(
            [
              label("Right pane — event log:", style: %{bold: true}),
              scrollable(
                Enum.map(state.log_lines, fn line -> label(line) end),
                flex: 1
              )
            ],
            flex: 1
          )
        ],
        orientation: :horizontal,
        ratio: 0.66,
        id: :outer_split,
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(SplitPaneDemo)
