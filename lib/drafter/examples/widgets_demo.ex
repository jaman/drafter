defmodule Drafter.Examples.WidgetsDemo do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  @movies_data [
    %{
      date: "1980-05-21",
      title: "The Empire Strikes Back",
      genre: "Sci-Fi",
      director: "Irvin Kershner",
      box_office: "$538M",
      rating: "PG"
    },
    %{
      date: "1981-03-20",
      title: "Raiders of the Lost Ark",
      genre: "Action",
      director: "Steven Spielberg",
      box_office: "$389M",
      rating: "PG"
    },
    %{
      date: "1982-06-11",
      title: "E.T.",
      genre: "Sci-Fi",
      director: "Steven Spielberg",
      box_office: "$792M",
      rating: "PG"
    },
    %{
      date: "1984-06-08",
      title: "Ghostbusters",
      genre: "Comedy",
      director: "Ivan Reitman",
      box_office: "$295M",
      rating: "PG"
    },
    %{
      date: "1984-10-26",
      title: "The Terminator",
      genre: "Sci-Fi",
      director: "James Cameron",
      box_office: "$78M",
      rating: "R"
    },
    %{
      date: "1985-07-03",
      title: "Back to the Future",
      genre: "Sci-Fi",
      director: "Robert Zemeckis",
      box_office: "$381M",
      rating: "PG"
    },
    %{
      date: "1986-07-18",
      title: "Aliens",
      genre: "Sci-Fi",
      director: "James Cameron",
      box_office: "$131M",
      rating: "R"
    },
    %{
      date: "1988-07-15",
      title: "Die Hard",
      genre: "Action",
      director: "John McTiernan",
      box_office: "$140M",
      rating: "R"
    }
  ]

  @highlander_options [
    {"Amanda", :amanda},
    {"Connor MacLeod", :connor},
    {"Duncan MacLeod", :duncan},
    {"Heather MacLeod", :heather},
    {"Joe Dawson", :joe},
    {"Kurgan, The", :kurgan},
    {"Methos", :methos},
    {"Rachel Ellenstein", :rachel},
    {"Ramirez", :ramirez}
  ]

  @action_heroes [
    {"Arnold Schwarzenegger", :arnold},
    {"Bruce Willis", :bruce},
    {"Sylvester Stallone", :sly},
    {"Harrison Ford", :harrison},
    {"Mel Gibson", :mel},
    {"Sigourney Weaver", :sigourney}
  ]

  @countries [
    {"Chad", :chad},
    {"Cuba", :cuba},
    {"Fiji", :fiji},
    {"Iran", :iran},
    {"Iraq", :iraq},
    {"Laos", :laos},
    {"Mali", :mali},
    {"Oman", :oman}
  ]

  @dune_tabs [
    %{
      id: "paul",
      label: "Paul Atreides",
      content:
        label(
          "Heir to House Atreides who becomes the Fremen messiah Muad'Dib. Born with extraordinary mental abilities due to Bene Gesserit breeding program."
        )
    },
    %{
      id: "jessica",
      label: "Lady Jessica",
      content:
        label(
          "Bene Gesserit concubine to Duke Leto and mother of Paul. Defied her order by bearing a son instead of a daughter."
        )
    },
    %{
      id: "baron",
      label: "Baron Harkonnen",
      content:
        label(
          "Cruel and corpulent leader of House Harkonnen, sworn enemy of House Atreides. Known for his cunning and brutality."
        )
    },
    %{
      id: "leto",
      label: "Leto Atreides",
      content:
        label(
          "Noble Duke and father of Paul, known for his honor and just rule. Accepts governorship of Arrakis despite knowing it's a trap."
        )
    },
    %{
      id: "stilgar",
      label: "Stilgar",
      content:
        label(
          "Leader of the Fremen Sietch Tabr, becomes a loyal supporter of Paul. Skilled warrior who helps train Paul in Fremen ways."
        )
    },
    %{
      id: "chani",
      label: "Chani",
      content:
        label(
          "Fremen warrior and daughter of planetologist Liet-Kynes. Becomes Paul's concubine and true love."
        )
    },
    %{
      id: "thufir",
      label: "Thufir Hawat",
      content:
        label(
          "Mentat and Master of Assassins for House Atreides. Serves three generations of Atreides with superhuman computational skills."
        )
    },
    %{
      id: "duncan",
      label: "Duncan Idaho",
      content:
        label(
          "Swordmaster of the Ginaz, loyal to House Atreides. Known for his exceptional fighting skills and sacrifice."
        )
    },
    %{
      id: "gurney",
      label: "Gurney Halleck",
      content:
        label(
          "Warrior-troubadour of House Atreides, skilled with sword and baliset. Serves as Paul's weapons teacher."
        )
    },
    %{
      id: "yueh",
      label: "Dr. Yueh",
      content:
        label(
          "Suk doctor conditioned against taking human life, but betrays House Atreides after Harkonnens torture his wife."
        )
    }
  ]

  @tree_data [
    %{
      id: :decades,
      label: "decades",
      icon: "{}",
      expanded: true,
      children: [
        %{
          id: :eighties,
          label: "1980s",
          icon: "{}",
          expanded: true,
          children: [
            %{
              id: :genres,
              label: "genres",
              icon: "{}",
              expanded: true,
              children: [
                %{
                  id: :action,
                  label: "action",
                  icon: "{}",
                  expanded: true,
                  children: [
                    %{
                      id: :franchises,
                      label: "franchises",
                      icon: "{}",
                      children: [
                        %{
                          id: :terminator_f,
                          label: "terminator",
                          icon: "{}",
                          children: [
                            %{id: :t_name, label: "name: The Terminator", children: []},
                            %{
                              id: :t_movies,
                              label: "movies",
                              icon: "[]",
                              children: [
                                %{
                                  id: :t1,
                                  label: "The Terminator (1984)",
                                  icon: "{}",
                                  children: [
                                    %{
                                      id: :t1_dir,
                                      label: "director: James Cameron",
                                      children: []
                                    },
                                    %{id: :t1_box, label: "boxOffice: $78M", children: []}
                                  ]
                                }
                              ]
                            }
                          ]
                        },
                        %{
                          id: :rambo_f,
                          label: "rambo",
                          icon: "{}",
                          children: [
                            %{id: :r_name, label: "name: Rambo", children: []},
                            %{
                              id: :r_movies,
                              label: "movies",
                              icon: "[]",
                              children: [
                                %{id: :r1, label: "First Blood (1982)", children: []},
                                %{
                                  id: :r2,
                                  label: "Rambo: First Blood Part II (1985)",
                                  children: []
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    },
                    %{
                      id: :standalone,
                      label: "standalone_classics",
                      icon: "{}",
                      children: [
                        %{
                          id: :die_hard,
                          label: "die_hard",
                          icon: "{}",
                          children: [
                            %{id: :dh_title, label: "title: Die Hard", children: []},
                            %{id: :dh_year, label: "year: 1988", children: []},
                            %{id: :dh_dir, label: "director: John McTiernan", children: []}
                          ]
                        },
                        %{
                          id: :predator,
                          label: "predator",
                          icon: "{}",
                          children: [
                            %{id: :pr_title, label: "title: Predator", children: []},
                            %{id: :pr_year, label: "year: 1987", children: []},
                            %{id: :pr_dir, label: "director: John McTiernan", children: []}
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    },
    %{
      id: :metadata,
      label: "metadata",
      icon: "{}",
      children: [
        %{id: :total_movies, label: "total_movies: 4", children: []},
        %{id: :date_compiled, label: "date_compiled: 2024", children: []},
        %{id: :box_office_total, label: "box_office_total: $467M", children: []},
        %{
          id: :most_frequent_actor,
          label: "most_frequent_actor: Arnold Schwarzenegger",
          children: []
        },
        %{
          id: :most_frequent_director,
          label: "most_frequent_director: John McTiernan",
          children: []
        }
      ]
    }
  ]

  def mount(_props) do
    themes = Drafter.Theme.available_themes() |> Map.keys()

    %{
      sparkline_data: generate_sparkline_data(0),
      sparkline_offset: 0,
      log_count: 0,
      log_lines: ["I am a Log Widget"],
      current_time: format_time(),
      checkbox_checked: true,
      current_theme: "textual-dark",
      theme_switch_group: "textual-dark",
      available_themes: themes,
      text_value: ""
    }
  end

  def on_ready(state) do
    send(self(), {:set_interval, 100, :update_sparkline})
    send(self(), {:set_interval, 250, :update_log})
    send(self(), {:set_interval, 1000, :update_time})
    state
  end

  def on_timer(:update_sparkline, state) do
    new_offset = state.sparkline_offset + 1
    %{state | sparkline_data: generate_sparkline_data(new_offset), sparkline_offset: new_offset}
  end

  def on_timer(:update_log, state) do
    fear_lines = [
      "I must not fear.",
      "Fear is the mind-killer.",
      "Fear is the little-death that brings total obliteration.",
      "I will face my fear.",
      "I will permit it to pass over me and through me.",
      "And when it has gone past, I will turn the inner eye to see its path.",
      "Where the fear has gone there will be nothing. Only I will remain."
    ]

    line_no = rem(state.log_count, length(fear_lines))
    line = Enum.at(fear_lines, line_no)
    new_line = "fear[#{line_no}] = '#{line}'"
    new_lines = (state.log_lines ++ [new_line]) |> Enum.take(-15)
    %{state | log_count: state.log_count + 1, log_lines: new_lines}
  end

  def on_timer(:update_time, state) do
    %{state | current_time: format_time()}
  end

  def on_timer(_id, state), do: state

  defp generate_sparkline_data(offset) do
    Enum.map(0..59, fn i ->
      x = (offset * 40 + i * 20) / 3.14
      abs(:math.sin(x))
    end)
  end

  defp format_time do
    {{_y, _m, _d}, {h, m, s}} = :calendar.local_time()
    "#{pad(h)}:#{pad(m)}:#{pad(s)}"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  def render(state) do
    table_columns = [
      %{key: :date, label: "Date", sortable: true},
      %{key: :title, label: "Title", sortable: true},
      %{key: :genre, label: "Genre", sortable: true},
      %{key: :director, label: "Director", sortable: true},
      %{key: :box_office, label: "Box Office", sortable: true, align: :right},
      %{key: :rating, label: "Rating", sortable: true}
    ]

    vertical([
      header("Widgets", show_clock: true),
      scrollable(
        [
          label("Buttons", style: %{fg: {100, 150, 255}, bold: true}),
          label("A simple button, with a number of semantic styles.",
            style: %{fg: {150, 150, 150}}
          ),
          horizontal([
            button("Default", on_click: :btn_default),
            button("Primary", variant: :primary, on_click: :btn_primary),
            button("Warning", variant: :warning, on_click: :btn_warning),
            button("Error", variant: :error, on_click: :btn_error)
          ]),
          label(""),
          label("Checkboxes, Radio buttons, and Radio sets",
            style: %{fg: {100, 150, 255}, bold: true}
          ),
          label("Checkboxes toggle booleans. Radio buttons for exclusive booleans.",
            style: %{fg: {150, 150, 150}}
          ),
          horizontal([
            vertical(
              [
                checkbox("A Checkbox",
                  checked: state.checkbox_checked,
                  on_change: :checkbox_changed
                )
              ],
              width: 20
            ),
            vertical(
              [
                radio_set(@highlander_options, selected: :connor, height: 9)
              ],
              width: 25
            )
          ]),
          label(""),
          label("DataTables", style: %{fg: {100, 150, 255}, bold: true}),
          label("A fully-featured DataTable, with cell, row, and column cursors.",
            style: %{fg: {150, 150, 150}}
          ),
          data_table(columns: table_columns, data: @movies_data, height: 10),
          label(""),
          label("Inputs and MaskedInputs", style: %{fg: {100, 150, 255}, bold: true}),
          label("Text input fields with placeholder text and validation.",
            style: %{fg: {150, 150, 150}}
          ),
          horizontal([
            vertical(
              [
                label("Free", style: %{fg: {120, 120, 120}}),
                text_input(placeholder: "Type anything here...")
              ],
              width: 30
            ),
            vertical(
              [
                label("Credit card", style: %{fg: {120, 120, 120}}),
                masked_input(mask: "9999-9999-9999-9999", placeholder: "0000-0000-0000-0000")
              ],
              width: 25
            )
          ]),
          label(""),
          label("List Views and Option Lists", style: %{fg: {100, 150, 255}, bold: true}),
          label("A List View turns any widget into a user-navigable and selectable list.",
            style: %{fg: {150, 150, 150}}
          ),
          horizontal([
            vertical(
              [
                digits("$50.00", size: :small),
                digits("£100.00", size: :small),
                digits("€500.00", size: :small),
                digits("¥5,000", size: :small)
              ],
              width: 35
            ),
            vertical(
              [
                option_list(@countries, height: 8)
              ],
              width: 20
            )
          ]),
          label(""),
          label("Logs and Rich Logs", style: %{fg: {100, 150, 255}, bold: true}),
          label("A Log widget to efficiently display a scrolling view of text.",
            style: %{fg: {150, 150, 150}}
          ),
          log(lines: state.log_lines, height: 8, highlight: true),
          label(""),
          label("Selects", style: %{fg: {100, 150, 255}, bold: true}),
          label("Selects present a list of options in a menu.", style: %{fg: {150, 150, 150}}),
          selection_list(@action_heroes, selection_mode: :single, height: 6),
          label(""),
          label("Sparklines", style: %{fg: {100, 150, 255}, bold: true}),
          label("A low-res summary of time-series data.", style: %{fg: {150, 150, 150}}),
          sparkline(state.sparkline_data, min_color: {100, 200, 100}, max_color: {230, 180, 50}),
          sparkline(state.sparkline_data, min_color: {230, 180, 50}, max_color: {220, 80, 80}),
          sparkline(state.sparkline_data, min_color: {100, 150, 255}, max_color: {180, 100, 220}),
          label(""),
          label("Switches", style: %{fg: {100, 150, 255}, bold: true}),
          label("Functionally identical to Checkboxes, but displays more prominently.",
            style: %{fg: {150, 150, 150}}
          ),
          render_theme_switches(state.available_themes, state.current_theme),
          label(""),
          label("Tabs", style: %{fg: {100, 150, 255}, bold: true}),
          label("A navigable list of section headers.", style: %{fg: {150, 150, 150}}),
          tabbed_content(@dune_tabs, height: 4),
          label(""),
          label("TextArea", style: %{fg: {100, 150, 255}, bold: true}),
          label("A powerful text area with syntax highlighting and line numbers.",
            style: %{fg: {150, 150, 150}}
          ),
          text_area(
            text:
              "# Start building!\nfrom textual import App, ComposeResult\n\ndef main():\n    print(\"Hello, World!\")\n    return 42",
            height: 8,
            show_line_numbers: true,
            language: :python
          ),
          label(""),
          label("Tree", style: %{fg: {100, 150, 255}, bold: true}),
          label("The Tree widget displays hierarchical data.", style: %{fg: {150, 150, 150}}),
          tree(data: @tree_data, height: 8),
          label(""),
          label("Progress", style: %{fg: {100, 150, 255}, bold: true}),
          progress_bar(progress: 65, show_percentage: true),
          label(""),
          label("Loading Indicators", style: %{fg: {100, 150, 255}, bold: true}),
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
          label("Clock", style: %{fg: {100, 150, 255}, bold: true}),
          digits(state.current_time, size: :small),
          label("")
        ],
        flex: 1
      ),
      footer(
        bindings: [
          {"q", "Quit"},
          {"Tab", "Next"},
          {"Shift+Tab", "Prev"},
          {"Enter", "Activate"}
        ]
      )
    ])
  end

  def handle_event(:btn_default, _data, _state) do
    {:show_toast, "You pressed Default", [variant: :info]}
  end

  def handle_event(:btn_primary, _data, _state) do
    {:show_toast, "You pressed Primary", [variant: :success]}
  end

  def handle_event(:btn_warning, _data, _state) do
    {:show_toast, "You pressed Warning", [variant: :warning]}
  end

  def handle_event(:btn_error, _data, _state) do
    {:show_toast, "You pressed Error", [variant: :error]}
  end

  def handle_event(:checkbox_changed, checked, state) do
    {:ok, %{state | checkbox_checked: checked}}
  end

  def handle_event({:switch_group_changed, :theme_switch_group, theme_name}, enabled, state) do
    if enabled and state.theme_switch_group != theme_name do
      Drafter.ThemeManager.set_theme(theme_name)
      {:ok, %{state | current_theme: theme_name, theme_switch_group: theme_name}}
    else
      {:noreply, state}
    end
  end

  def handle_event({:theme_changed, theme_name}, _enabled, state) do
    Drafter.ThemeManager.set_theme(theme_name)
    {:ok, %{state | current_theme: theme_name, theme_switch_group: theme_name}}
  end

  def handle_event(:text_changed, text, state) do
    {:ok, %{state | text_value: text}}
  end

  def handle_event(_event, _data, state) do
    {:noreply, state}
  end

  def handle_event({:key, :q}, state) do
    {:stop, state}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_theme_switches(themes, current_theme) do
    switches =
      Enum.map(themes, fn theme_name ->
        [label: theme_name, size: :compact, enabled: current_theme == theme_name]
      end)

    switch_group(:theme_switch_group, switches)
  end
end
