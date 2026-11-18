defmodule Drafter.Runtime.BlurTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT

  defmodule Form do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{typed: [], name: ""}
    def on_ready(state), do: tap(state, fn _ -> Drafter.focus(:name) end)

    def render(state),
      do: vertical([text_input(id: :name, bind: :name), label(Enum.join(state.typed))])

    def handle_event({:key, :escape}, state) do
      Drafter.blur(:name)
      {:ok, state}
    end

    def handle_event({:key, key}, state), do: {:ok, %{state | typed: state.typed ++ [key]}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "after blur, keys reach the app instead of the input" do
    ctx = DT.start_headless(Form, %{}, size: {40, 6})
    DT.send_key(ctx, :a)
    assert DT.get_state(ctx).name == "a"
    assert DT.get_state(ctx).typed == []

    DT.send_key(ctx, :escape)
    DT.send_key(ctx, :b)
    assert DT.get_state(ctx).name == "a"
    assert DT.get_state(ctx).typed == [:b]
    DT.stop(ctx)
  end
end

defmodule Drafter.Runtime.BlurBeforeMountTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT

  defmodule Lobby do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{screen: :title, keys: []}
    def render(%{screen: :title}), do: vertical([label("title")])

    def render(%{screen: :lobby} = state),
      do: vertical([label("keys=#{inspect(state.keys)}"), text_input(id: :chat, bind: :chat)])

    def render(%{screen: :talk}), do: vertical([label("say"), text_input(id: :talk, bind: :talk)])

    def handle_event({:key, :enter}, %{screen: :title} = state) do
      Drafter.blur(:chat)
      {:ok, %{state | screen: :lobby}}
    end

    def handle_event({:key, :t}, %{screen: :lobby} = state) do
      Drafter.focus(:talk)
      {:ok, %{state | screen: :talk}}
    end

    def handle_event({:key, key}, state), do: {:ok, %{state | keys: state.keys ++ [key]}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "a focus asked for before the widget is drawn lands on it once it appears, blur or no blur" do
    ctx = DT.start_headless(Lobby, %{}, size: {40, 6})
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "keys=" end)
    DT.send_key(ctx, :t)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "say" end)
    DT.send_key(ctx, :h)
    DT.send_key(ctx, :i)
    assert DT.get_state(ctx).talk == "hi"
    assert DT.get_state(ctx).keys == []
    DT.stop(ctx)
  end

  test "a blur asked for before the widget is drawn keeps focus away, so arrows reach the app" do
    ctx = DT.start_headless(Lobby, %{}, size: {40, 6})
    DT.send_key(ctx, :enter)
    assert :ok == DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "keys=" end)

    DT.send_key(ctx, :down)
    DT.send_key(ctx, :up)
    DT.send_key(ctx, :j)
    assert DT.get_state(ctx).keys == [:down, :up, :j]
    DT.stop(ctx)
  end
end

defmodule Drafter.Runtime.BlurAsFocusLeavesTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT

  defmodule Menu do
    @moduledoc false
    use Drafter.App, frame_pacing: :always

    def mount(_props), do: %{screen: :title, keys: [], chat: ""}
    def on_ready(state), do: tap(state, fn _ -> Drafter.focus(:play) end)

    def render(%{screen: :title}), do: vertical([button("play", id: :play, on_click: :play)])

    def render(%{screen: :lobby} = state),
      do: vertical([label("keys=#{inspect(state.keys)}"), text_input(id: :chat, bind: :chat)])

    def handle_event(:play, _data, state) do
      Drafter.blur(:chat)
      {:ok, %{state | screen: :lobby}}
    end

    def handle_event(_name, _data, state), do: {:noreply, state}

    def handle_event({:key, key}, state), do: {:ok, %{state | keys: state.keys ++ [key]}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "a blur asked for while the focused widget is about to leave the screen keeps focus away" do
    ctx = DT.start_headless(Menu, %{}, size: {40, 6})
    DT.send_key(ctx, :enter)
    assert DT.get_state(ctx).screen == :lobby

    DT.send_key(ctx, :enter)
    DT.send_key(ctx, :j)
    assert DT.get_state(ctx).keys == [:enter, :j]
    assert DT.get_state(ctx).chat == ""
    DT.stop(ctx)
  end
end
