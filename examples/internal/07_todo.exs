Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule TodoApp do
  use Drafter.App

  @statuses [:todo, :in_progress, :done]

  @status_icons %{
    todo: "[ ]",
    in_progress: "[~]",
    done: "[x]"
  }

  def mount(_props) do
    %{
      todos: [
        %{id: id(), text: "Learn Drafter", status: :todo},
        %{id: id(), text: "Build awesome CLI apps", status: :todo}
      ],
      new_todo: ""
    }
  end

  def render(state) do
    options =
      Enum.map(state.todos, fn todo ->
        icon = @status_icons[todo.status]
        {icon <> " " <> todo.text, todo.id}
      end)

    vertical([
      header("Todo"),
      vertical(
        [
          option_list(options,
            id: :todo_list,
            on_select: :cycle_status,
            expand_height: :fill
          )
        ],
        flex: 1
      ),
      text_input(
        id: :todo_input,
        placeholder: "New todo...",
        bind: :new_todo,
        on_submit: :add_todo,
        keep_focus: true
      ),
      footer(
        bindings: [
          {"Enter", "Add / Cycle"},
          {"Tab", "Switch"},
          {"Del", "Remove"},
          {"q", "Quit"}
        ]
      )
    ])
  end

  def handle_event(:add_todo, _data, state) do
    case String.trim(state.new_todo) do
      "" ->
        {:noreply, state}

      text ->
        todo = %{id: id(), text: text, status: :todo}
        {:ok, %{state | todos: state.todos ++ [todo], new_todo: ""}}
    end
  end

  def handle_event(:cycle_status, todo_id, state) do
    todos = Enum.map(state.todos, &maybe_cycle(&1, todo_id))
    {:ok, %{state | todos: todos}}
  end

  def handle_event({:key, :delete}, state) do
    remove_highlighted(state)
  end

  def handle_event({:key, :backspace}, state) do
    remove_highlighted(state)
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}

  defp maybe_cycle(%{id: id} = todo, id) do
    current_idx = Enum.find_index(@statuses, &(&1 == todo.status))
    next_idx = rem(current_idx + 1, length(@statuses))
    %{todo | status: Enum.at(@statuses, next_idx)}
  end

  defp maybe_cycle(todo, _id), do: todo

  defp remove_highlighted(state) do
    case Drafter.get_widget_state(:todo_list) do
      %{highlighted_index: idx} when is_integer(idx) and idx < length(state.todos) ->
        {:ok, %{state | todos: List.delete_at(state.todos, idx)}}

      _ ->
        {:noreply, state}
    end
  end

  defp id, do: System.unique_integer([:positive]) |> to_string()
end

Drafter.run(TodoApp)
