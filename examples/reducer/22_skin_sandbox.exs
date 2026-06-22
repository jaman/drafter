Mix.install([
  {:drafter, path: Path.join(__DIR__, "../..")},
  {:elixir_make, "~> 0.9"},
  {:spark, "~> 2.6"}
])

defmodule SkinSandbox do
  use Drafter, runtime: :reducer

  @skins [
    {:graphical, "Graphical (1)", "1"},
    {:wireframe, "Wireframe (2)", "2"},
    {:ascii, "ASCII     (3)", "3"},
    {:classic, "Classic   (4)", "4"},
    {:retro, "Retro     (5)", "5"}
  ]

  @monthly_sales [
    {"Jan", 42},
    {"Feb", 58},
    {"Mar", 71},
    {"Apr", 33},
    {"May", 89},
    {"Jun", 95},
    {"Jul", 61},
    {"Aug", 78},
    {"Sep", 54},
    {"Oct", 82},
    {"Nov", 67},
    {"Dec", 91}
  ]

  @quarterly [
    {[42, 58, 71], "Q1"},
    {[33, 89, 95], "Q2"},
    {[61, 78, 54], "Q3"},
    {[82, 67, 91], "Q4"}
  ]

  @departments [
    {"Engineering", [84, 61, 72, 91]},
    {"Sales", [55, 78, 63, 88]},
    {"Support", [40, 52, 48, 60]}
  ]

  def mount(_props) do
    %{
      current_skin: Drafter.current_skin(),
      progress: 68.0
    }
  end

  def on_ready(state) do
    Drafter.set_interval(30, :sparkline_tick)
    Enum.each(1..60, fn _ -> Drafter.push_data(:live_sparkline, :rand.uniform(100)) end)
    state
  end

  keybinding :"1", "graphical skin" do
    {:ok, apply_skin(:graphical, state)}
  end

  keybinding :"2", "wireframe skin" do
    {:ok, apply_skin(:wireframe, state)}
  end

  keybinding :"3", "ascii skin" do
    {:ok, apply_skin(:ascii, state)}
  end

  keybinding :"4", "classic skin" do
    {:ok, apply_skin(:classic, state)}
  end

  keybinding :"5", "retro skin" do
    {:ok, apply_skin(:retro, state)}
  end

  keybinding :tab, "focus next" do
    {:noreply, state}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def on_timer(:sparkline_tick, state) do
    Drafter.push_data(:live_sparkline, :rand.uniform(100))
    state
  end

  def render(state) do
    sales_values = Enum.map(@monthly_sales, fn {_, v} -> v end)
    sales_labels = Enum.map(@monthly_sales, fn {l, _} -> l end)

    quarterly_series = Enum.map(@quarterly, fn {vs, _} -> vs end)
    quarterly_labels = Enum.map(@quarterly, fn {_, l} -> l end)

    dept_series = Enum.map(@departments, fn {_, vs} -> vs end)
    dept_labels = Enum.map(@departments, fn {label, _} -> label end)

    skin_options = Enum.map(@skins, fn {id, label, _key} -> {label, id} end)

    vertical([
      header("Skin Sandbox — press 1–5 to switch skins"),
      horizontal(
        [
          vertical(
            [
              label("Skin:", style: %{bold: true}),
              option_list(
                skin_options,
                on_select: :skin_selected,
                selected: state.current_skin
              ),
              label(""),
              label("Active:", style: %{bold: true}),
              label(to_string(state.current_skin),
                style: %{fg: {100, 220, 100}, bold: true}
              ),
              label(""),
              label("Indicators:", style: %{bold: true}),
              checkbox("Option A", checked: true),
              checkbox("Option B", checked: false),
              label(""),
              radio_set(
                [{"Alpha", :a}, {"Beta", :b}, {"Gamma", :c}],
                selected: :a,
                height: 3
              ),
              label(""),
              switch(label: "Toggle", enabled: true),
              label(""),
              collapsible(
                "Collapsible",
                "Skin affects the expand/collapse arrow.",
                expanded: true
              )
            ],
            width: 24
          ),
          scrollable(
            [
              label("Monthly Sales — vertical bars:", style: %{bold: true}),
              chart(
                sales_values,
                chart_type: :clustered_bar,
                height: 6,
                colors: [{100, 200, 255}]
              ),
              label(""),
              label("Monthly Sales — horizontal bars with labels + values:",
                style: %{bold: true}
              ),
              chart(
                sales_values,
                chart_type: :bar,
                orientation: :horizontal,
                bar_labels: sales_labels,
                show_labels: true,
                show_values: true,
                height: 12,
                min_value: 0,
                max_value: 100,
                color: {100, 200, 255}
              ),
              label(""),
              label("Quarterly Clustered — horizontal:", style: %{bold: true}),
              chart(
                quarterly_series,
                chart_type: :clustered_bar,
                orientation: :horizontal,
                bar_labels: quarterly_labels,
                show_labels: true,
                show_values: true,
                height: 12,
                min_value: 0,
                max_value: 100,
                colors: [{100, 200, 255}, {255, 160, 80}, {80, 220, 140}]
              ),
              label(""),
              label("Dept Stacked — horizontal:", style: %{bold: true}),
              chart(
                dept_series,
                chart_type: :stacked_bar,
                orientation: :horizontal,
                bar_labels: dept_labels,
                show_labels: true,
                height: 3,
                min_value: 0,
                max_value: 400,
                colors: [{100, 200, 255}, {255, 160, 80}, {80, 220, 140}, {220, 120, 220}]
              ),
              label(""),
              label("Progress bar:", style: %{bold: true}),
              progress_bar(progress: state.progress, show_percentage: true),
              label(""),
              label("Sparkline (live):", style: %{bold: true}),
              sparkline(
                id: :live_sparkline,
                buffer: :auto,
                #                refresh: 20,
                min_color: {80, 180, 255},
                max_color: {255, 100, 80},
                summary: true
              ),
              label(""),
              label("Loading spinners:", style: %{bold: true}),
              horizontal(
                [
                  loading_indicator(spinner_type: :default, text: "default"),
                  loading_indicator(spinner_type: :dots, text: "dots"),
                  loading_indicator(spinner_type: :line, text: "line"),
                  loading_indicator(spinner_type: :points, text: "points")
                ],
                gap: 2
              )
            ],
            flex: 1
          )
        ],
        flex: 1,
        gap: 1
      ),
      footer()
    ])
  end

  defp apply_skin(skin, state) do
    Drafter.set_skin(skin)
    Drafter.set_theme(Drafter.CharacterSet.preferred_theme(skin))
    %{state | current_skin: skin}
  end

  def handle_event(:skin_selected, skin, state), do: {:ok, apply_skin(skin, state)}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(SkinSandbox)
