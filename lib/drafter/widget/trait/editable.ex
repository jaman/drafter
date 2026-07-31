defmodule Drafter.Widget.Trait.Editable do
  @moduledoc """
  Trait that adds text editing capability.

  Manages text content, cursor position, and text selection.
  Handles character input, deletion, cursor movement, and clipboard operations.
  """

  @behaviour Drafter.Widget.Trait

  defstruct __spark_metadata__: nil

  @impl true
  def name, do: :editable

  @impl true
  def default_state do
    %{
      _text: "",
      _cursor_position: 0,
      _selection_start: nil,
      _selection_end: nil
    }
  end

  @impl true
  def dependencies, do: [:focusable]

  @impl true
  def handles, do: [:keyboard, :char]

  @impl true
  def render_affecting_fields, do: [:_text, :_cursor_position, :_selection_start, :_selection_end]

  @impl true
  def layout_static?, do: true

  @impl true
  def handle_event({:char, ch}, trait_state, _widget_state) do
    {before, after_cursor} = String.split_at(trait_state._text, trait_state._cursor_position)
    new_text = before <> <<ch::utf8>> <> after_cursor
    {:ok, %{trait_state | _text: new_text, _cursor_position: trait_state._cursor_position + 1}}
  end

  def handle_event({:key, :backspace}, trait_state, _widget_state) do
    if trait_state._cursor_position > 0 do
      {before, after_cursor} = String.split_at(trait_state._text, trait_state._cursor_position)
      new_before = String.slice(before, 0..(String.length(before) - 2)//1)
      new_text = new_before <> after_cursor
      {:ok, %{trait_state | _text: new_text, _cursor_position: trait_state._cursor_position - 1}}
    else
      {:pass, trait_state}
    end
  end

  def handle_event({:key, :delete}, trait_state, _widget_state) do
    if trait_state._cursor_position < String.length(trait_state._text) do
      {before, after_cursor} = String.split_at(trait_state._text, trait_state._cursor_position)
      new_after = String.slice(after_cursor, 1..-1//1)
      {:ok, %{trait_state | _text: before <> new_after}}
    else
      {:pass, trait_state}
    end
  end

  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:left, :ArrowLeft] do
    new_pos = max(0, trait_state._cursor_position - 1)
    {:ok, %{trait_state | _cursor_position: new_pos, _selection_start: nil, _selection_end: nil}}
  end

  def handle_event({:key, key}, trait_state, _widget_state)
      when key in [:right, :ArrowRight] do
    max_pos = String.length(trait_state._text)
    new_pos = min(max_pos, trait_state._cursor_position + 1)
    {:ok, %{trait_state | _cursor_position: new_pos, _selection_start: nil, _selection_end: nil}}
  end

  def handle_event({:key, :home}, trait_state, _widget_state) do
    {:ok, %{trait_state | _cursor_position: 0, _selection_start: nil, _selection_end: nil}}
  end

  def handle_event({:key, :end}, trait_state, _widget_state) do
    max_pos = String.length(trait_state._text)
    {:ok, %{trait_state | _cursor_position: max_pos, _selection_start: nil, _selection_end: nil}}
  end

  def handle_event(_event, trait_state, _widget_state) do
    {:pass, trait_state}
  end
end
