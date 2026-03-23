defmodule Drafter.Examples.ButtonDebug do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{}
  end

  def render(_state) do
    horizontal([
      button("AAA", type: :primary, on_click: :a),
      button("BBB", type: :success, on_click: :b),
      button("CCC", type: :warning, on_click: :c)
    ])
  end

  def handle_event({:key, :d, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event({:key, :q, [:ctrl]}, _state) do
    {:stop, :normal}
  end

  def handle_event(_, _, state) do
    {:noreply, state}
  end
end
