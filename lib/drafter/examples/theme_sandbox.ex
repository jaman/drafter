defmodule Drafter.Examples.ThemeSandbox do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  alias Drafter.{Theme, ThemeManager}

  def mount(_props) do
    theme_names = Map.keys(Theme.available_themes())
    current_theme = Theme.dark_theme()

    ThemeManager.register_app(self())

    %{
      current_theme: current_theme,
      theme_names: theme_names,
      progress: 65.0,
      sparkline_data: generate_sparkline_data(),
      current_time: format_time(),
      table_data: sample_table_data(),
      tree_data: sample_tree_data()
    }
  end

  def on_ready(state) do
    send(self(), {:set_interval, 500, :tick})
    state
  end

  def on_timer(:tick, state) do
    new_sparkline = update_sparkline(state.sparkline_data)
    %{state | sparkline_data: new_sparkline, current_time: format_time()}
  end

  def on_timer(_timer_id, state), do: state

  defp generate_sparkline_data do
    Enum.map(1..20, fn _ -> :rand.uniform(10) end)
  end

  defp update_sparkline(data) do
    [_ | rest] = data
    rest ++ [:rand.uniform(10)]
  end

  defp format_time do
    {{_y, _m, _d}, {h, m, s}} = :calendar.local_time()
    h_str = String.pad_leading(Integer.to_string(h), 2, "0")
    m_str = String.pad_leading(Integer.to_string(m), 2, "0")
    s_str = String.pad_leading(Integer.to_string(s), 2, "0")
    "#{h_str}:#{m_str}:#{s_str}"
  end

  defp sample_table_data do
    [
      %{name: "Alice", age: 28, city: "New York", status: "Active"},
      %{name: "Bob", age: 34, city: "Los Angeles", status: "Pending"},
      %{name: "Carol", age: 22, city: "Chicago", status: "Active"},
      %{name: "Dave", age: 45, city: "Houston", status: "Inactive"},
      %{name: "Eve", age: 31, city: "Phoenix", status: "Active"},
      %{name: "Frank", age: 29, city: "Seattle", status: "Pending"}
    ]
  end

  defp sample_tree_data do
    [
      %{
        id: :root1,
        label: "Documents",
        icon: "📁",
        expanded: true,
        children: [
          %{id: :doc1, label: "report.pdf", icon: "📄", children: []},
          %{id: :doc2, label: "notes.txt", icon: "📝", children: []},
          %{
            id: :folder1,
            label: "Projects",
            icon: "📁",
            children: [
              %{id: :proj1, label: "project_a", icon: "📁", children: []},
              %{id: :proj2, label: "project_b", icon: "📁", children: []}
            ]
          }
        ]
      },
      %{
        id: :root2,
        label: "Downloads",
        icon: "📁",
        children: [
          %{id: :dl1, label: "image.png", icon: "🖼️", children: []},
          %{id: :dl2, label: "video.mp4", icon: "🎬", children: []}
        ]
      }
    ]
  end

  def render(state) do
    theme_options =
      Enum.map(state.theme_names, fn name ->
        {to_string(name), name}
      end)

    theme_list =
      option_list(theme_options,
        on_select: :theme_selected,
        on_highlight: :theme_highlighted,
        selected: state.current_theme.name
      )

    radio_options = [
      {"Amanda", "option1"},
      {"Connor MacLeod", "option2"},
      {"Duncan MacLeod", "option3"},
      {"Heather MacLeod", "option4"}
    ]

    selection_options = [
      {"Falken's Maze", "item1"},
      {"Black Jack", "item2"},
      {"Gin Rummy", "item3"},
      {"Hearts", "item4"}
    ]

    menu_tabs = [
      %{
        id: "foods",
        label: "Foods",
        content:
          option_list(
            [{"Pizza", "pizza"}, {"Pasta", "pasta"}, {"Salad", "salad"}, {"Soup", "soup"}],
            on_select: :food_selected
          )
      },
      %{
        id: "drinks",
        label: "Drinks",
        content:
          option_list(
            [{"Water", "water"}, {"Coffee", "coffee"}, {"Tea", "tea"}, {"Juice", "juice"}],
            on_select: :drink_selected
          )
      },
      %{
        id: "desserts",
        label: "Desserts",
        content:
          option_list([{"Cake", "cake"}, {"Ice Cream", "ice_cream"}, {"Pie", "pie"}],
            on_select: :dessert_selected
          )
      },
      %{
        id: "extras",
        label: "Extras",
        content:
          option_list([{"Bread", "bread"}, {"Butter", "butter"}, {"Sauce", "sauce"}],
            on_select: :extra_selected
          )
      }
    ]

    table_columns = [
      %{key: :name, label: "Name", sortable: true},
      %{key: :age, label: "Age", sortable: true, align: :right},
      %{key: :city, label: "City", sortable: true},
      %{key: :status, label: "Status", sortable: true}
    ]

    footer_bindings = [
      {"Tab", "Next"},
      {"Shift+Tab", "Prev"},
      {"Enter", "Select"},
      {"Ctrl+Q", "Quit"}
    ]

    scrollable_content = [
      label("Buttons:"),
      horizontal([
        button("Primary", type: :primary, on_click: :primary_clicked),
        button("Success", type: :success, on_click: :success_clicked),
        button("Warning", type: :warning, on_click: :warning_clicked),
        button("Error", type: :error, on_click: :error_clicked)
      ]),
      label(""),
      horizontal([
        vertical([
          label("Switch:"),
          switch(enabled: false)
        ]),
        vertical([
          checkbox("Option A", checked: false),
          checkbox("Option B", checked: true)
        ])
      ]),
      label(""),
      horizontal([
        vertical([
          label("SelectionList:"),
          selection_list(selection_options, selected: ["item2"], height: 4)
        ]),
        vertical([
          label("RadioSet:"),
          radio_set(radio_options, selected: "option1", height: 4)
        ])
      ]),
      label(""),
      tabbed_content(menu_tabs, title: "Menu", height: 8, width: 40),
      label(""),
      collapsible(
        "An interesting story.",
        "This is the content that appears when expanded. It can contain multiple lines of text and will wrap appropriately.",
        wrap: :word,
        expanded: false
      ),
      label(""),
      label("Text Input:"),
      text_input(placeholder: "Hello, world!"),
      label(""),
      label("Progress:"),
      progress_bar(progress: state.progress, show_percentage: true),
      label(""),
      horizontal([
        vertical(
          [
            label("Tree:"),
            tree(data: state.tree_data, height: 6)
          ],
          width: 30
        ),
        vertical(
          [
            label("DataTable:"),
            data_table(columns: table_columns, data: state.table_data, height: 6)
          ],
          width: 40
        )
      ]),
      label(""),
      label("Sparkline (live):"),
      sparkline(state.sparkline_data),
      label(""),
      label("Loading Indicators:"),
      horizontal(
        [
          loading_indicator(spinner_type: :default),
          loading_indicator(spinner_type: :dots),
          loading_indicator(spinner_type: :line),
          loading_indicator(spinner_type: :arrow)
        ],
        gap: 1
      ),
      label(""),
      label("Links:"),
      horizontal(
        [
          link("Elixir Lang", url: "https://elixir-lang.org"),
          link("GitHub", url: "https://github.com")
        ],
        gap: 1
      ),
      label(""),
      horizontal(
        [
          vertical(
            [
              label("Masked Input:"),
              masked_input(mask: "(###) ###-####", placeholder: "Phone")
            ],
            width: 20
          ),
          vertical([
            label("Pretty:"),
            pretty(%{app: :drafter, version: "1.0.0", features: [:widgets, :themes, :css]})
          ])
        ],
        gap: 1
      ),
      label(""),
      label("Clock:"),
      digits(state.current_time)
    ]

    vertical([
      header("Theme Sandbox", show_clock: true),
      rule(),
      horizontal(
        [
          vertical([theme_list], width: 20),
          scrollable(scrollable_content, flex: 1)
        ],
        flex: 1
      ),
      footer(bindings: footer_bindings)
    ])
  end

  def handle_event(:theme_selected, theme_name, state) do
    ThemeManager.set_theme(theme_name)
    {:noreply, state}
  end

  def handle_event(:theme_highlighted, theme_name, state) do
    ThemeManager.set_theme(theme_name)
    {:noreply, state}
  end

  def handle_event(:food_selected, food_id, _state) do
    {:show_toast, "Selected: #{String.upcase(food_id)}", []}
  end

  def handle_event(:drink_selected, drink_id, _state) do
    {:show_toast, "Selected: #{String.upcase(drink_id)}", []}
  end

  def handle_event(:dessert_selected, dessert_id, _state) do
    {:show_toast, "Selected: #{String.upcase(dessert_id)}", []}
  end

  def handle_event(:extra_selected, extra_id, _state) do
    {:show_toast, "Selected: #{String.upcase(extra_id)}", []}
  end

  def handle_event(_event_name, _data, state) do
    {:noreply, state}
  end

  def handle_event(event, state) do
    case event do
      {:theme_updated, new_theme} ->
        {:ok, %{state | current_theme: new_theme}}

      {:key, :d, [:ctrl]} ->
        {:stop, :normal}

      {:key, :q, [:ctrl]} ->
        {:stop, :normal}

      _ ->
        {:noreply, state}
    end
  end
end
