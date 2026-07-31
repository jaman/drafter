defmodule Drafter.Examples.NewWidgetsDemo do
  @moduledoc """
  Demo showcasing the new widgets: LoadingIndicator, Link, Log, RichLog, Pretty, MaskedInput, Sparkline, DirectoryTree.

  Run with:
    mix run -e "Drafter.run(Drafter.Examples.NewWidgetsDemo)"
  """

  use Drafter.App
  import Drafter.App

  def mount(_props) do
    log_lines = read_log_lines("drafter.log", 50)

    rich_log_lines = [
      {"[info] Application initialized", %{color: {100, 255, 100}, bold: true}},
      {"[info] Connecting to database...", %{color: {100, 255, 100}}},
      {"[warn] Database connection slow", %{color: {255, 200, 100}, bold: true}},
      {"[info] Connection successful", %{color: {100, 255, 100}}},
      {"[debug] Loading user data...", %{color: {150, 150, 150}}},
      {"[info] Loaded 150 users", %{color: {100, 255, 100}}},
      {"[error] Failed to load profile images", %{color: {255, 100, 100}, bold: true}},
      {"[warn] Using fallback images", %{color: {255, 200, 100}}},
      {"[info] Application ready", %{color: {100, 255, 100}, bold: true}}
    ]

    %{
      log_lines: log_lines,
      rich_log_lines: rich_log_lines,
      sparkline_data: Enum.map(1..20, fn _ -> :rand.uniform(100) end),
      masked_phone: "",
      masked_date: "",
      masked_ssn: "131665543",
      pretty_data: %{
        name: "John Doe",
        age: 30,
        active: true,
        scores: [85, 92, 78, 95],
        metadata: %{
          level: :expert,
          tags: [:elixir, :tui, :widgets]
        }
      },
      loading_active: true
    }
  end

  def on_ready(state) do
    send(self(), {:set_interval, 100, :update_data})
    state
  end

  def on_timer(:update_data, state) do
    new_sparkline = update_sparkline(state.sparkline_data)
    %{state | sparkline_data: new_sparkline}
  end

  def on_timer(_timer_id, state), do: state

  defp update_sparkline(data) do
    [_ | rest] = data
    rest ++ [:rand.uniform(100)]
  end

  def render(state) do
    vertical([
      header("NEW WIDGETS DEMO - TEST BUILD", show_clock: true),
      rule(),
      label("Loading Indicators (animated):"),
      horizontal(
        [
          loading_indicator(spinner_type: :default, running: true),
          loading_indicator(spinner_type: :dots, running: true),
          loading_indicator(spinner_type: :line, running: true),
          loading_indicator(spinner_type: :arrow, running: true)
        ],
        gap: 1
      ),
      label(""),
      label("Links (Tab to focus, Enter to open):"),
      card(
        [
          horizontal(
            [
              link("Elixir Homepage", url: "https://elixir-lang.org"),
              link("GitHub", url: "https://github.com"),
              link("Textual Docs", url: "https://textual.textualize.io")
            ],
            gap: 1
          )
        ],
        padding: 1
      ),
      label(""),
      label("Logs (Page Up/Down to scroll):"),
      horizontal(
        [
          card(
            [
              vertical(
                [
                  label("Drafter Log:"),
                  log(file_path: "drafter.log", height: 8, max_lines: 1000)
                ],
                gap: 0
              )
            ],
            flex: 1,
            padding: 1
          ),
          card(
            [
              vertical(
                [
                  label("Debug Log:"),
                  log(file_path: "tui_debug.log", height: 8, max_lines: 1000)
                ],
                gap: 0
              )
            ],
            flex: 1,
            padding: 1
          )
        ],
        gap: 1
      ),
      label(""),
      label("Masked Input (Tab between fields):"),
      card(
        [
          horizontal(
            [
              vertical([label("Phone:"), masked_input(mask: "(###) ###-####", id: :phone)],
                gap: 0
              ),
              vertical([label("Date:"), masked_input(mask: "##/##/####", id: :date)], gap: 0),
              vertical([label("SSN:"), masked_input(mask: "###-##-####", id: :ssn)], gap: 0)
            ],
            gap: 2
          )
        ],
        padding: 1
      ),
      label("Mask Patterns: # (any), 9 (digit), a (lowercase), A (letter)"),
      label(""),
      label("Sparkline (animated with summary):"),
      horizontal(
        [
          card(
            [
              vertical(
                [
                  label("Basic:"),
                  sparkline(state.sparkline_data, color: {100, 200, 100})
                ],
                gap: 0
              )
            ],
            flex: 1,
            padding: 1
          ),
          card(
            [
              vertical(
                [
                  label("With Summary:"),
                  sparkline(state.sparkline_data, color: {100, 200, 100}, summary: true)
                ],
                gap: 0
              )
            ],
            flex: 1,
            padding: 1
          )
        ],
        gap: 2
      ),
      label(""),
      label("Pretty (Elixir data structures):"),
      card([pretty(state.pretty_data, expand: true, height: 10)], padding: 1),
      label(""),
      label("Directory Tree (arrow keys + Enter/Space):"),
      card([directory_tree(path: File.cwd!(), show_hidden: false, height: 12)], padding: 1),
      footer([
        {"q", "Quit"}
      ])
    ])
  end

  def handle_event({:key, :q}, state) do
    {:stop, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp read_log_lines(filename, count) do
    path = Path.join(File.cwd!(), filename)

    if File.exists?(path) do
      {result, _} = System.cmd("tail", ["-n", "#{count}", path], stderr_to_stdout: true)

      result
      |> String.split("\n", trim: true)
      |> Enum.take(-count)
    else
      ["Log file not found: #{filename}"]
    end
  end
end
