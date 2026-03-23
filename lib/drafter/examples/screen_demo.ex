defmodule Drafter.Examples.ScreenDemo do
  @moduledoc false
  use Drafter.App

  def mount(_props) do
    %{
      counter: 0,
      last_modal_result: nil
    }
  end

  def handle_event(:show_modal_on_start, _data, _state) do
    {:show_modal, Drafter.Examples.ScreenDemo.InfoModal, %{title: "Auto-Opened Modal"}, [title: "Info Modal", width: 50, height: 15]}
  end

  def handle_event(:increment, _data, state) do
    {:ok, %{state | counter: state.counter + 1}}
  end

  def handle_event(:show_modal, _data, _state) do
    {:show_modal, Drafter.Examples.ScreenDemo.InfoModal, %{title: "Information"},
     [title: "Info Modal", width: 50, height: 15]}
  end

  def handle_event(:show_confirm, _data, _state) do
    {:show_modal, Drafter.Examples.ScreenDemo.ConfirmModal,
     %{message: "Are you sure you want to proceed?"}, [title: "Confirm", width: 45, height: 10]}
  end

  def handle_event(:show_toast, _data, _state) do
    {:show_toast, "This is an info toast message!", [variant: :info]}
  end

  def handle_event(:toast_success, _data, _state) do
    {:show_toast, "Operation completed successfully!", [variant: :success]}
  end

  def handle_event(:toast_error, _data, _state) do
    {:show_toast, "An error occurred!", [variant: :error]}
  end

  def handle_event(:toast_warning, _data, _state) do
    {:show_toast, "Warning: Check your settings", [variant: :warning]}
  end

  def handle_event(:modal_result, result, state) do
    {:ok, %{state | last_modal_result: result}}
  end

  def handle_event(_event, _data, state) do
    {:noreply, state}
  end

  def render(state) do
    content = [
      label("Counter: #{state.counter}"),
      label(""),
      label("Last modal result: #{inspect(state.last_modal_result)}"),
      label(""),
      horizontal(
        [
          button("Show Modal", on_click: :show_modal),
          button("Show Confirm", on_click: :show_confirm),
          button("Show Toast", on_click: :show_toast)
        ],
        gap: 2
      ),
      label(""),
      horizontal(
        [
          button("Success Toast", on_click: :toast_success),
          button("Error Toast", on_click: :toast_error),
          button("Warning Toast", on_click: :toast_warning)
        ],
        gap: 2
      ),
      label(""),
      button("Increment Counter", on_click: :increment)
    ]

    vertical([
      header("Screen System Demo"),
      scrollable(content, flex: 1),
      footer(
        bindings: [
          {"q", "Quit"},
          {"m", "Modal"},
          {"t", "Toast"}
        ]
      )
    ])
  end

  def handle_event(:show_modal_on_start, _state) do
    {:show_modal, Drafter.Examples.ScreenDemo.InfoModal, %{title: "Auto-Opened Modal"}, [title: "Info Modal", width: 50, height: 15]}
  end

  def handle_event({:key, ?m}, state), do: handle_event({:key, :m}, state)
  def handle_event({:key, :m}, _state) do
    {:show_modal, Drafter.Examples.ScreenDemo.InfoModal, %{}, [title: "Quick Modal"]}
  end

  def handle_event({:key, ?t}, state), do: handle_event({:key, :t}, state)
  def handle_event({:key, :t}, _state) do
    {:show_toast, "Keyboard shortcut toast!", []}
  end

  def handle_event({:key, ?q}, state), do: handle_event({:key, :q}, state)
  def handle_event({:key, :q}, _state) do
    {:stop, :normal}
  end

  def handle_event({:key, :q, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

defmodule Drafter.Examples.ScreenDemo.InfoModal do
  @moduledoc false
  use Drafter.Screen

  def mount(props) do
    %{
      title: Map.get(props, :title, "Information"),
      content:
        Map.get(
          props,
          :content,
          "This is a modal dialog.\n\nYou can put any content here.\n\nPress ESC or click Close to dismiss."
        )
    }
  end

  def render(state) do
    vertical(
      [
        label(state.content),
        label(""),
        horizontal(
          [
            button("Close", on_click: :close)
          ],
          align: :center
        )
      ],
      padding: 1
    )
  end

  def handle_event(:close, _state) do
    {:pop, :closed}
  end

  def handle_event({:key, :escape}, _state) do
    {:pop, :dismissed}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

defmodule Drafter.Examples.ScreenDemo.ConfirmModal do
  @moduledoc false
  use Drafter.Screen

  def mount(props) do
    %{
      message: Map.get(props, :message, "Are you sure?"),
      selected: :no
    }
  end

  def render(state) do
    vertical(
      [
        label(state.message),
        label(""),
        horizontal(
          [
            button("Yes",
              on_click: :confirm,
              variant: if(state.selected == :yes, do: :primary, else: :default)
            ),
            button("No",
              on_click: :cancel,
              variant: if(state.selected == :no, do: :primary, else: :default)
            )
          ], gap: 2, align: :center)
      ],
      padding: 1
    )
  end

  def handle_event(:confirm, _state) do
    {:pop, {:confirmed, true}}
  end

  def handle_event(:cancel, _state) do
    {:pop, {:confirmed, false}}
  end

  def handle_event({:key, :escape}, _state) do
    {:pop, {:confirmed, false}}
  end

  def handle_event({:key, :escape, _mods}, _state) do
    {:pop, {:confirmed, false}}
  end

  def handle_event({:key, :left}, state) do
    {:ok, %{state | selected: :yes}}
  end

  def handle_event({:key, :left, _mods}, state) do
    {:ok, %{state | selected: :yes}}
  end

  def handle_event({:key, :right}, state) do
    {:ok, %{state | selected: :no}}
  end

  def handle_event({:key, :right, _mods}, state) do
    {:ok, %{state | selected: :no}}
  end

  def handle_event({:key, :enter}, state) do
    if state.selected == :yes do
      {:pop, {:confirmed, true}}
    else
      {:pop, {:confirmed, false}}
    end
  end

  def handle_event({:key, :enter, _mods}, state) do
    if state.selected == :yes do
      {:pop, {:confirmed, true}}
    else
      {:pop, {:confirmed, false}}
    end
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
