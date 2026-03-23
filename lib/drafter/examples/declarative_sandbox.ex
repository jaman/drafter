defmodule Drafter.Examples.DeclarativeSandbox do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      current_theme: "dark",
      button_clicks: %{
        primary: 0,
        success: 0,
        warning: 0
      },
      checkbox1_enabled: false,
      checkbox2_enabled: true,
      text_input_value: "",
      feature_enabled: false,
      selected_user: nil,
      sort_column: nil,
      sort_direction: :asc,
      user_data: generate_sample_data()
    }
  end

  def on_ready(state) do
    # App is ready - initial focus should be set by widget hierarchy
    state
  end

  def render(state) do
    horizontal([
      # Left panel - Theme selector
      vertical([
        label("🐟 Theme Selector"),
        theme_selector()
      ]),

      # Right panel - Widget showcase
      vertical([
        label("TUI Declarative Sandbox"),

        # Button showcase section
        label("Buttons:"),
        horizontal([
          button("Primary (#{state.button_clicks.primary})",
            type: :primary,
            on_click: :primary_clicked
          ),
          button("Success (#{state.button_clicks.success})",
            type: :success,
            on_click: :success_clicked
          ),
          button("Warning (#{state.button_clicks.warning})",
            type: :warning,
            on_click: :warning_clicked
          )
        ]),

        # Form controls section
        label("Form Controls:"),
        horizontal([
          checkbox("Enable Feature",
            checked: state.checkbox1_enabled,
            on_change: :checkbox1_changed
          ),
          checkbox("Default Enabled",
            checked: state.checkbox2_enabled,
            on_change: :checkbox2_changed
          )
        ]),

        # Text input section  
        label("Text Input:"),
        text_input(
          value: state.text_input_value,
          placeholder: "Enter some text...",
          on_change: :text_changed,
          on_submit: :text_submitted
        ),

        # DataTable showcase section
        label("DataTable Demo:"),
        data_table(
          columns: [
            %{key: :id, label: "ID", width: :auto, align: :right, sortable: true},
            %{key: :name, label: "Name", width: :auto, align: :left, sortable: true},
            %{key: :email, label: "Email", width: :auto, align: :left, sortable: true},
            %{key: :age, label: "Age", width: :auto, align: :right, sortable: true},
            %{key: :department, label: "Dept", width: :auto, align: :left, sortable: true},
            %{key: :status, label: "Status", width: :auto, align: :center, sortable: true}
          ],
          data: state.user_data,
          height: :auto,
          selection_mode: :single,
          show_header: true,
          zebra_stripes: true,
          show_scrollbars: true,
          column_fit_mode: :fit,
          focused: true,
          mouse_scroll_moves_selection: true,
          mouse_scroll_selects_item: false,
          sort_by:
            if state.sort_column do
              {state.sort_column, state.sort_direction}
            else
              {:name, :asc}
            end,
          on_select: :user_selected,
          on_sort: :data_sorted
        ),

        # Status display
        label("Status: #{if state.feature_enabled, do: "Enabled", else: "Disabled"}"),
        label(
          if state.selected_user do
            "Selected: #{state.selected_user.name} (#{state.selected_user.email})"
          else
            "No user selected"
          end
        )
      ])
    ])
  end

  def handle_event(:primary_clicked, _, state) do
    new_clicks = %{state.button_clicks | primary: state.button_clicks.primary + 1}
    {:ok, %{state | button_clicks: new_clicks}}
  end

  def handle_event(:success_clicked, _, state) do
    new_clicks = %{state.button_clicks | success: state.button_clicks.success + 1}
    {:ok, %{state | button_clicks: new_clicks}}
  end

  def handle_event(:warning_clicked, _, state) do
    new_clicks = %{state.button_clicks | warning: state.button_clicks.warning + 1}
    {:ok, %{state | button_clicks: new_clicks}}
  end

  def handle_event(:checkbox1_changed, enabled, state) do
    {:ok, %{state | checkbox1_enabled: enabled, feature_enabled: enabled}}
  end

  def handle_event(:checkbox2_changed, enabled, state) do
    {:ok, %{state | checkbox2_enabled: enabled}}
  end

  def handle_event(:text_changed, new_text, state) do
    {:ok, %{state | text_input_value: new_text}}
  end

  def handle_event(:text_submitted, _text, state) do
    {:ok, state}
  end

  def handle_event(:user_selected, selected_users, state) do
    selected_user = List.first(selected_users)
    {:ok, %{state | selected_user: selected_user}}
  end

  def handle_event(:data_sorted, {column, direction}, state) do
    {:ok, %{state | sort_column: column, sort_direction: direction}}
  end

  def handle_event(event, _data, state) when is_atom(event) do
    {:noreply, state}
  end

  def handle_event({:key, :d, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event({:key, :q, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp generate_sample_data do
    # Use deterministic seed to prevent random data changes on re-render
    :rand.seed(:exsss, {1, 2, 3})

    departments = ["Engineering", "Sales", "Marketing", "HR", "Finance", "Operations"]
    statuses = ["Active", "Inactive", "Pending", "On Leave"]

    first_names = [
      "Alice",
      "Bob",
      "Charlie",
      "Diana",
      "Eve",
      "Frank",
      "Grace",
      "Henry",
      "Iris",
      "Jack",
      "Kate",
      "Liam",
      "Mia",
      "Noah",
      "Olivia",
      "Paul",
      "Quinn",
      "Ruby",
      "Sam",
      "Tina"
    ]

    last_names = [
      "Smith",
      "Johnson",
      "Brown",
      "Davis",
      "Wilson",
      "Miller",
      "Taylor",
      "Anderson",
      "Thomas",
      "Jackson",
      "White",
      "Harris",
      "Martin",
      "Thompson",
      "Garcia",
      "Martinez",
      "Robinson",
      "Clark",
      "Rodriguez",
      "Lewis"
    ]

    data =
      1..100
      |> Enum.map(fn id ->
        first_name = Enum.random(first_names)
        last_name = Enum.random(last_names)
        name = "#{first_name} #{last_name}"
        email = "#{String.downcase(first_name)}.#{String.downcase(last_name)}@company.com"

        %{
          id: id,
          name: name,
          email: email,
          age: Enum.random(22..65),
          department: Enum.random(departments),
          status: Enum.random(statuses)
        }
      end)
      |> Enum.sort_by(& &1.name)

    # Reset random seed to system time to not affect other random operations
    :rand.seed(:exsss)

    data
  end
end
