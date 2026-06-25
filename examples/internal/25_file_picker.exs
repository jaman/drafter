Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule FilePickerDemo do
  use Drafter.App
  import Drafter.App

  alias Drafter.Widget.FilePicker

  def mount(_props) do
    %{result: nil}
  end

  keybinding :o, "open file" do
    handle_event(:open_file, nil, state)
  end

  keybinding :d, "open dir" do
    handle_event(:open_dir, nil, state)
  end

  keybinding :e, "elixir files" do
    handle_event(:open_filtered, nil, state)
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding {:c, [:ctrl]}, "quit" do
    {:stop, :normal}
  end

  def render(state) do
    {result_text, result_style} =
      case state.result do
        nil -> {"—", %{fg: {100, 100, 110}}}
        :cancelled -> {"Cancelled", %{fg: {200, 100, 80}}}
        path -> {path, %{fg: {100, 200, 130}}}
      end

    vertical([
      header("File Picker Demo"),
      vertical(
        [
          label(""),
          horizontal([
            label("Result: ", style: %{bold: true}),
            label(result_text, style: result_style)
          ]),
          label(""),
          horizontal([
            button("Open File (o)", on_click: :open_file),
            label("  "),
            button("Directory (d)", on_click: :open_dir),
            label("  "),
            button("Elixir Files (e)", on_click: :open_filtered)
          ]),
          label(""),
          label("Picker keybindings:", style: %{bold: true}),
          label("  h  — toggle hidden files"),
          label("  ↑↓ — navigate"),
          label("  Enter — expand/select"),
          label("  Esc — cancel")
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:open_file, _data, _state) do
    FilePicker.show(on_select: :file_picked, on_cancel: :pick_cancelled)
  end

  def handle_event(:open_dir, _data, _state) do
    FilePicker.show(on_select: :file_picked, on_cancel: :pick_cancelled, allow_dirs: true, title: "Select Directory")
  end

  def handle_event(:open_filtered, _data, _state) do
    FilePicker.show(on_select: :file_picked, on_cancel: :pick_cancelled, filter: [".ex", ".exs"], title: "Open Elixir File")
  end

  def handle_event(:file_picked, path, state), do: {:ok, %{state | result: path}}
  def handle_event(:pick_cancelled, _data, state), do: {:ok, %{state | result: :cancelled}}

  def handle_event(_event, _data, state), do: {:noreply, state}

  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(FilePickerDemo)
