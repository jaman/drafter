Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule DataTableDemo do
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      selected_user: nil,
      sort_column: :name,
      sort_direction: :asc,
      user_data: generate_sample_data()
    }
  end

  def keybindings, do: [{"q", "quit"}, {"tab", "focus"}, {"↑↓", "select"}]

  def render(state) do
    vertical([
      header("DataTable Demo"),
      horizontal(
        [
          theme_selector(),
          vertical(
            [
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
                sort_by: {state.sort_column, state.sort_direction},
                on_select: :user_selected,
                on_sort: :data_sorted
              ),
              label(
                if state.selected_user do
                  "Selected: #{state.selected_user.name} (#{state.selected_user.email})"
                else
                  "No user selected"
                end
              )
            ],
            flex: 1
          )
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:user_selected, selected_users, state) do
    {:ok, %{state | selected_user: List.first(selected_users)}}
  end

  def handle_event(:data_sorted, {column, direction}, state) do
    {:ok, %{state | sort_column: column, sort_direction: direction}}
  end

  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp generate_sample_data do
    :rand.seed(:exsss, {1, 2, 3})
    departments = ["Engineering", "Sales", "Marketing", "HR", "Finance", "Operations"]
    statuses = ["Active", "Inactive", "Pending", "On Leave"]

    first_names =
      ~w(Alice Bob Charlie Diana Eve Frank Grace Henry Iris Jack Kate Liam Mia Noah Olivia Paul Quinn Ruby Sam Tina)

    last_names =
      ~w(Smith Johnson Brown Davis Wilson Miller Taylor Anderson Thomas Jackson White Harris Martin Thompson Garcia Martinez Robinson Clark Rodriguez Lewis)

    data =
      1..100
      |> Enum.map(fn id ->
        first = Enum.random(first_names)
        last = Enum.random(last_names)

        %{
          id: id,
          name: "#{first} #{last}",
          email: "#{String.downcase(first)}.#{String.downcase(last)}@company.com",
          age: Enum.random(22..65),
          department: Enum.random(departments),
          status: Enum.random(statuses)
        }
      end)
      |> Enum.sort_by(& &1.name)

    :rand.seed(:exsss)
    data
  end
end

Drafter.run(DataTableDemo)
