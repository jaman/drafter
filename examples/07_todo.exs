Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule TodoApp do
  use Drafter.App

  def mount(_props) do
    %{
      todos: ["Learn Drafter", "Build awesome CLI apps"],
      new_todo: ""
    }
  end

  def render(state) do
    todo_items =
      Enum.map(state.todos, fn todo ->
        label("  • #{todo}")
      end)

    vertical([
      header("Todo App"),
      scrollable(todo_items, flex: 1),
      horizontal(
        [
          text_input(
            id: :new_todo_input,
            placeholder: "Add todo...",
            bind: :new_todo,
            on_submit: :add_todo,
            keep_focus: true,
            flex: 1
          ),
          button("Add", on_click: :add_todo)
        ],
        gap: 1
      ),
      footer(bindings: [{"q", "Quit"}, {"Enter", "Add"}])
    ])
  end

  def handle_event(:add_todo, _data, state) do
    if String.trim(state.new_todo) != "" do
      {:ok, %{state | todos: state.todos ++ [state.new_todo], new_todo: ""}}
    else
      {:noreply, state}
    end
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(TodoApp)
