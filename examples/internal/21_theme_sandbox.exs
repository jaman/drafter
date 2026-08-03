Mix.install([
  {:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"},
  {:elixir_make, "~> 0.9"},
  {:spark, "~> 2.6"}
], consolidate_protocols: false)

defmodule InputModal do
  use Drafter.Screen
  import Drafter.App

  def mount(_props), do: %{value: ""}

  def render(_state) do
    vertical([
      label("Enter a value:"),
      text_input(on_change: :value_changed, placeholder: "Type here...", on_submit: :submit),
      label(""),
      horizontal(
        [
          button("Submit", variant: :primary, on_click: :submit),
          button("Cancel", on_click: :cancel)
        ],
        gap: 2
      )
    ])
  end

  def handle_event(:value_changed, {text, _}, state), do: {:ok, %{state | value: text}}

  def handle_event(:submit, _data, state) do
    Drafter.send_app_event(:modal_submitted, state.value)
    {:pop, :submitted}
  end

  def handle_event(:cancel, _data, _state), do: {:pop, :cancelled}
  def handle_event({:key, :escape}, _data, _state), do: {:pop, :cancelled}
  def handle_event(_event, _data, state), do: {:noreply, state}
end

defmodule ThemeSandbox do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    theme_names = Drafter.Theme.available_themes() |> Map.keys() |> Enum.map(&to_string/1)

    %{
      theme_names: theme_names,
      current_theme: "textual-dark",
      progress: 65.0,
      modal_result: nil,
      current_time: current_time(),
      table_data: [
        %{name: "Alice", age: 28, score: 92, status: "Active"},
        %{name: "Bob", age: 34, score: 45, status: "Pending"},
        %{name: "Carol", age: 22, score: 78, status: "Active"},
        %{name: "Dave", age: 45, score: 31, status: "Inactive"},
        %{name: "Eve", age: 31, score: 67, status: "Active"},
        %{name: "Frank", age: 29, score: 55, status: "Pending"},
        %{name: "Grace", age: 38, score: 88, status: "Active"},
        %{name: "Henry", age: 52, score: 23, status: "Inactive"}
      ],
      tree_data: [
        %{
          id: :docs,
          label: "Documents",
          icon: "📁",
          expanded: true,
          children: [
            %{id: :doc1, label: "report.pdf", icon: "📄", children: []},
            %{id: :doc2, label: "notes.txt", icon: "📝", children: []},
            %{
              id: :proj,
              label: "Projects",
              icon: "📁",
              children: [
                %{id: :pa, label: "project_a", icon: "📁", children: []},
                %{id: :pb, label: "project_b", icon: "📁", children: []}
              ]
            }
          ]
        },
        %{
          id: :dl,
          label: "Downloads",
          icon: "📁",
          children: [
            %{id: :img, label: "image.png", icon: "📷", children: []},
            %{id: :vid, label: "video.mp4", icon: "🎬", children: []}
          ]
        }
      ]
    }
  end

  keybinding :tab, "next" do
    {:noreply, state}
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def on_ready(state) do
    Drafter.set_interval(24, :sparkline_tick)
    Enum.each(1..60, fn _ -> Drafter.push_data(:live_sparkline, :rand.uniform(10)) end)
    state
  end

  def on_timer(:sparkline_tick, state) do
    Drafter.push_data(:live_sparkline, :rand.uniform(10))
    %{state | current_time: current_time()}
  end

  def render(state) do
    status_color = fn
      "Active" -> {30, 110, 55}
      "Pending" -> {130, 100, 20}
      "Inactive" -> {110, 35, 35}
      _ -> nil
    end

    score_color = fn score ->
      cond do
        score >= 80 -> {30, 110, 55}
        score >= 50 -> {130, 100, 20}
        true -> {110, 35, 35}
      end
    end

    table_columns = [
      %{key: :name, label: "Name", sortable: true},
      %{key: :age, label: "Age", sortable: true, align: :right},
      %{key: :score, label: "Score", sortable: true, align: :right, color_fn: score_color},
      %{key: :status, label: "Status", sortable: true, color_fn: status_color}
    ]

    menu_tabs = [
      %{
        id: "foods",
        label: "Foods",
        content:
          option_list([{"Pizza", :pizza}, {"Pasta", :pasta}, {"Salad", :salad}],
            on_select: :food_selected
          )
      },
      %{
        id: "drinks",
        label: "Drinks",
        content:
          option_list([{"Water", :water}, {"Coffee", :coffee}, {"Tea", :tea}],
            on_select: :drink_selected
          )
      },
      %{
        id: "desserts",
        label: "Desserts",
        content:
          option_list([{"Cake", :cake}, {"Ice Cream", :ice_cream}, {"Pie", :pie}],
            on_select: :item_selected
          )
      },
      %{
        id: "extras",
        label: "Extras",
        content:
          option_list([{"Bread", :bread}, {"Butter", :butter}, {"Sauce", :sauce}],
            on_select: :item_selected
          )
      }
    ]

    vertical([
      header("Theme Sandbox", show_clock: true),
      horizontal(
        [
          vertical(
            [
              option_list(
                Enum.map(state.theme_names, fn name -> {name, name} end),
                on_select: :theme_selected,
                on_highlight: :theme_highlighted,
                selected: state.current_theme
              )
            ],
            width: 22
          ),
          scrollable(
            [
              label("Buttons:", style: %{bold: true}),
              horizontal(
                [
                  button("Open Modal", variant: :primary, on_click: :open_modal),
                  button("Success", variant: :success, on_click: :success_clicked),
                  button("Warning", variant: :warning, on_click: :warning_clicked),
                  button("Error", variant: :error, on_click: :error_clicked)
                ],
                gap: 1
              ),
              label(
                if state.modal_result,
                  do: "Modal submitted: #{state.modal_result}",
                  else: "Modal result: (none)"
              ),
              label(""),
              horizontal(
                [
                  vertical([
                    label("Switches:"),
                    switch(enabled: false),
                    switch(enabled: true)
                  ]),
                  vertical([
                    label("Checkboxes:"),
                    checkbox("Option A", checked: false),
                    checkbox("Option B", checked: true)
                  ]),
                  vertical([
                    label("Sliders:"),
                    slider(value: 0.35),
                    slider(value: 0.8, disabled: true)
                  ])
                ],
                gap: 4
              ),
              label(""),
              horizontal(
                [
                  vertical(
                    [
                      label("Radio Set:"),
                      radio_set(
                        [
                          {"Amanda", "option1"},
                          {"Connor MacLeod", "option2"},
                          {"Duncan MacLeod", "option3"},
                          {"Heather", "option4"}
                        ],
                        selected: "option1",
                        height: 4
                      )
                    ],
                    width: 22
                  ),
                  vertical(
                    [
                      label("Selection List:"),
                      selection_list(
                        [
                          {"Falken's Maze", "item1"},
                          {"Black Jack", "item2"},
                          {"Gin Rummy", "item3"},
                          {"かるた", "item4"}
                        ],
                        selected: ["item2"],
                        height: 4
                      )
                    ],
                    width: 22
                  )
                ],
                gap: 2
              ),
              label(""),
              tabbed_content(menu_tabs, title: "Menu", height: 8, width: 44),
              label(""),
              collapsible(
                "Collapsible Section",
                "This content appears when expanded. It can contain multiple lines of text.",
                wrap: :word,
                expanded: false
              ),
              label(""),
              label("Text Input:"),
              text_input(placeholder: "Type something..."),
              label(""),
              label("Progress:"),
              progress_bar(progress: state.progress, show_percentage: true),
              label(""),
              horizontal(
                [
                  vertical(
                    [
                      label("Tree:"),
                      tree(data: state.tree_data, height: 6)
                    ],
                    width: 32
                  ),
                  vertical(
                    [
                      label("DataTable:"),
                      data_table(columns: table_columns, data: state.table_data, height: 9)
                    ],
                    width: 48
                  )
                ],
                gap: 2
              ),
              label(""),
              label("Sparkline (live):"),
              sparkline(id: :live_sparkline, buffer: :auto, summary: true),
              label(""),
              label("Loading Indicators:"),
              horizontal(
                [
                  loading_indicator(spinner_type: :default),
                  loading_indicator(spinner_type: :dots),
                  loading_indicator(spinner_type: :line),
                  loading_indicator(spinner_type: :arrow)
                ],
                gap: 2
              ),
              label(""),
              label("Links:"),
              horizontal(
                [
                  link("Elixir Lang", url: "https://elixir-lang.org"),
                  link("GitHub", url: "https://github.com")
                ],
                gap: 2
              ),
              label(""),
              horizontal(
                [
                  vertical(
                    [
                      label("Masked Input:"),
                      masked_input(mask: "(###) ###-####", placeholder: "Phone")
                    ],
                    width: 22
                  ),
                  vertical([
                    label("Pretty:"),
                    pretty(%{app: :drafter, version: "1.0", features: [:widgets, :themes]})
                  ])
                ],
                gap: 2
              ),
              label(""),
              label("Clock (Digits):"),
              digits(state.current_time),
              label("")
            ],
            flex: 1
          )
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:theme_selected, name, state) do
    Drafter.ThemeManager.set_theme(name)
    {:ok, %{state | current_theme: name}}
  end

  def handle_event(:theme_highlighted, name, state) do
    Drafter.ThemeManager.set_theme(name)
    {:ok, %{state | current_theme: name}}
  end

  def handle_event(:open_modal, _data, _state) do
    {:show_modal, InputModal, %{}, [title: "Input Test", border: true, width: 40, height: 10]}
  end

  def handle_event(:modal_submitted, value, state) do
    {:ok, %{state | modal_result: value}}
  end

  def handle_event(:food_selected, food, _state),
    do: {:show_toast, "Food: #{food}", [variant: :info]}

  def handle_event(:drink_selected, drink, _state),
    do: {:show_toast, "Drink: #{drink}", [variant: :info]}

  def handle_event(:item_selected, item, _state),
    do: {:show_toast, "Item: #{item}", [variant: :info]}

  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event(_event, state), do: {:noreply, state}

  defp current_time do
    {_, {h, m, s}} = :calendar.local_time()
    [h, m, s] |> Enum.map_join(":", &(Integer.to_string(&1) |> String.pad_leading(2, "0")))
  end
end

Drafter.run(ThemeSandbox, scroll_optimization: false)
