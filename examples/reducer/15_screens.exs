Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule ScreensExample do
  use Drafter, runtime: :reducer

  def mount(_props), do: %{last_result: nil}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :m, "modal" do
    {:show_modal, ScreensExample.InfoModal, %{}, [title: "Information", width: 50, height: 12, border: true]}
  end

  keybinding :t, "toast" do
    {:show_toast, "Toast via keyboard!", [variant: :info]}
  end

  def render(state) do
    vertical([
      header("Screens & Modals Example"),
      scrollable(
        [
          label("Last result: #{inspect(state.last_result)}", style: %{fg: :bright_black}),
          label(""),
          label("Modals", style: %{bold: true, fg: :cyan}),
          horizontal([
            button("Info Modal", on_click: :show_info, variant: :primary),
            button("Confirm Modal", on_click: :show_confirm)
          ], gap: 2),
          label(""),
          label("Toasts", style: %{bold: true, fg: :cyan}),
          horizontal([
            button("Info",    on_click: :toast_info),
            button("Success", on_click: :toast_success, variant: :success),
            button("Warning", on_click: :toast_warning, variant: :warning),
            button("Error",   on_click: :toast_error,   variant: :error)
          ], gap: 1)
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event(:show_info, _data, _state) do
    {:show_modal, ScreensExample.InfoModal, %{}, [title: "Information", width: 50, height: 12, border: true]}
  end

  def handle_event(:show_confirm, _data, _state) do
    {:show_modal, ScreensExample.ConfirmModal, %{}, [title: "Confirm", width: 45, height: 10, border: true]}
  end

  def handle_event(:toast_info,    _data, _state), do: {:show_toast, "Info message",    [variant: :info]}
  def handle_event(:toast_success, _data, _state), do: {:show_toast, "Success!",        [variant: :success]}
  def handle_event(:toast_warning, _data, _state), do: {:show_toast, "Warning!",        [variant: :warning]}
  def handle_event(:toast_error,   _data, _state), do: {:show_toast, "Error!",          [variant: :error]}

  def handle_event(:modal_result, result, state), do: {:ok, %{state | last_result: result}}
  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event(_event, state), do: {:noreply, state}
end

defmodule ScreensExample.InfoModal do
  use Drafter.Screen

  def mount(_props), do: %{}

  def keybindings, do: [{"esc", "close"}, {"enter", "OK"}]

  def render(_state) do
    vertical([
      label("This is an informational modal.", style: %{fg: :cyan}),
      label(""),
      label("Press Escape or click OK to close."),
      label(""),
      horizontal([
        button("OK", on_click: :close, variant: :primary)
      ], align: :center)
    ], padding: 1)
  end

  def handle_event(:close, _data, _state), do: {:pop, :ok}
  def handle_event({:key, :escape}, _data, _state), do: {:pop, :dismissed}
  def handle_event({:key, :enter}, _data, _state), do: {:pop, :ok}
  def handle_event(_event, _data, state), do: {:noreply, state}
end

defmodule ScreensExample.ConfirmModal do
  use Drafter.Screen

  def mount(_props), do: %{selected: :no}

  def keybindings, do: [{"enter", "confirm"}, {"esc", "cancel"}, {"←→", "select"}]

  def render(state) do
    vertical([
      label("Are you sure you want to proceed?"),
      label(""),
      horizontal([
        button("Yes",
          on_click: :confirm,
          variant: if(state.selected == :yes, do: :primary, else: :default)
        ),
        button("No",
          on_click: :cancel,
          variant: if(state.selected == :no, do: :primary, else: :default)
        )
      ], gap: 2, align: :center)
    ], padding: 1)
  end

  def handle_event(:confirm, _data, _state) do
    Drafter.send_app_event(:modal_result, :confirmed)
    {:pop, :confirmed}
  end

  def handle_event(:cancel,          _data, _state), do: {:pop, :cancelled}
  def handle_event({:key, :escape},  _data, _state), do: {:pop, :cancelled}
  def handle_event({:key, :left},    _data, state),  do: {:ok, %{state | selected: :yes}}
  def handle_event({:key, :right},   _data, state),  do: {:ok, %{state | selected: :no}}

  def handle_event({:key, :enter}, _data, state) do
    result = if state.selected == :yes, do: :confirmed, else: :cancelled
    Drafter.send_app_event(:modal_result, result)
    {:pop, result}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}
end

Drafter.run(ScreensExample)
