defmodule Drafter.Widget.TextAreaClipboardKeysTest do
  @moduledoc """
  TextArea's clipboard keys, driven with the event shape a real keypress produces.

  The events here come from `Drafter.Terminal.ANSI.parse_sequence/1` on the actual
  bytes a terminal sends, not from a shape chosen by hand — a binding written against
  the wrong shape (`?c` rather than `:c`, say) silently stops working, and a test that
  invents its own events would not notice.
  """

  use ExUnit.Case, async: false

  alias Drafter.Terminal.ANSI
  alias Drafter.Widget.TextArea

  @ctrl_c <<3>>
  @ctrl_x <<24>>
  @ctrl_v <<22>>
  @ctrl_a <<1>>

  setup do
    original_keys = Application.get_env(:drafter, :clipboard_keys)
    original_clipboard = Application.get_env(:drafter, :clipboard)

    Application.put_env(:drafter, :clipboard, false)

    on_exit(fn ->
      restore(:clipboard_keys, original_keys)
      restore(:clipboard, original_clipboard)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:drafter, key)
  defp restore(key, value), do: Application.put_env(:drafter, key, value)

  defp press(bytes) do
    {[event], ""} = ANSI.parse_sequence(bytes)
    event
  end

  defp area(text) do
    %{TextArea.mount(%{text: text}) | focused: true}
  end

  defp select_all(state) do
    {:ok, selected} = TextArea.handle_event(press(@ctrl_a), state)
    selected
  end

  test "the bytes a terminal sends for ctrl+c arrive as the bound shape" do
    assert press(@ctrl_c) == {:key, :c, [:ctrl]}
    assert Drafter.Clipboard.key?(:copy, :c, [:ctrl])
  end

  test "select all selects" do
    assert select_all(area("hello")).selection != nil
  end

  test "cut removes the selection" do
    {:ok, cut} = TextArea.handle_event(press(@ctrl_x), select_all(area("hello")))

    assert cut.text == ""
  end

  test "copy leaves the text alone" do
    state = select_all(area("hello"))

    assert {:ok, copied} = TextArea.handle_event(press(@ctrl_c), state)
    assert copied.text == "hello"
  end

  test "a read-only area refuses cut" do
    state = %{select_all(area("hello")) | read_only: true}

    assert {:noreply, ^state} = TextArea.handle_event(press(@ctrl_x), state)
  end

  test "a read-only area refuses paste" do
    state = %{area("hello") | read_only: true}

    assert {:noreply, ^state} = TextArea.handle_event(press(@ctrl_v), state)
  end

  test "paste is inert while the clipboard is disabled, and does not raise" do
    state = area("hello")

    assert {tag, pasted} = TextArea.handle_event(press(@ctrl_v), state)
    assert tag in [:ok, :noreply]
    assert pasted.text == "hello"
  end

  test "undo still works, so the clipboard clause did not shadow it" do
    {:ok, cut} = TextArea.handle_event(press(@ctrl_x), select_all(area("hello")))
    {:ok, undone} = TextArea.handle_event({:key, :z, [:ctrl]}, cut)

    assert undone.text == "hello"
  end

  test "rebinding cut moves it to the new key and frees the old one" do
    Application.put_env(:drafter, :clipboard_keys, cut: {:k, [:ctrl]})

    selected = select_all(area("hello"))

    assert {:noreply, _} = TextArea.handle_event(press(@ctrl_x), selected)
    assert {:ok, cut} = TextArea.handle_event({:key, :k, [:ctrl]}, selected)
    assert cut.text == ""
  end

  test "unbinding an action leaves the key inert" do
    Application.put_env(:drafter, :clipboard_keys, cut: false)

    selected = select_all(area("hello"))

    assert {:noreply, _} = TextArea.handle_event(press(@ctrl_x), selected)
  end
end
