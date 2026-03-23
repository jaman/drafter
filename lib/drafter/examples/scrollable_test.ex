defmodule Drafter.Examples.ScrollableTest do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{}
  end

  def render(_state) do
    vertical([
      header("Scrollable Container Test"),
      rule(),
      scrollable(
        [
          label("Item 1 - This is the first item"),
          button("Button 1", type: :primary, on_click: :btn1),
          label("Item 2 - This is the second item"),
          button("Button 2", type: :success, on_click: :btn2),
          label("Item 3 - This is the third item"),
          button("Button 3", type: :warning, on_click: :btn3),
          label("Item 4 - This is the fourth item"),
          button("Button 4", type: :error, on_click: :btn4),
          label("Item 5 - This is the fifth item"),
          button("Button 5", type: :primary, on_click: :btn5),
          label("Item 6 - This is the sixth item"),
          button("Button 6", type: :success, on_click: :btn6),
          label("Item 7 - This is the seventh item"),
          button("Button 7", type: :warning, on_click: :btn7),
          label("Item 8 - This is the eighth item"),
          button("Button 8", type: :error, on_click: :btn8),
          label("Item 9 - This is the ninth item"),
          button("Button 9", type: :primary, on_click: :btn9),
          label("Item 10 - This is the tenth item"),
          button("Button 10", type: :success, on_click: :btn10)
        ],
        height: 15
      ),
      rule(),
      footer(bindings: [{"Scroll", "Mouse/Keys"}, {"Tab", "Focus"}, {"Ctrl+Q", "Quit"}])
    ])
  end

  def handle_event(event_name, _data, state) when is_atom(event_name) do
    {:noreply, state}
  end

  def handle_event({:key, :q, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event({:key, :d, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end
