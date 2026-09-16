defmodule Drafter.Runtime.KeyReleaseEventsTest do
  use ExUnit.Case, async: false

  alias Drafter.Session.Context
  alias Drafter.Test.HeadlessDriver

  defmodule Held do
    @moduledoc false
    use Drafter.App, key_release: true

    def mount(_props), do: %{held: MapSet.new(), supported: :unknown}

    def render(state) do
      vertical([label("held=#{state.held |> Enum.sort() |> Enum.join(",")}")])
    end

    def handle_event({:key_down, key, _mods}, state),
      do: {:ok, %{state | held: MapSet.put(state.held, key)}}

    def handle_event({:key_up, key, _mods}, state),
      do: {:ok, %{state | held: MapSet.delete(state.held, key)}}

    def handle_event({:key_release_support, true}, state),
      do: {:ok, %{state | supported: Context.key_release?()}}

    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Plain do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{}
    def render(_state), do: vertical([label("plain")])
  end

  setup do
    ctx = Drafter.Test.start_headless(Held, %{}, size: {30, 4})
    on_exit(fn -> Drafter.Test.stop(ctx) end)
    {:ok, ctx: ctx}
  end

  defp inject(ctx, event) do
    HeadlessDriver.inject_event(event)
    Drafter.Test.sync(ctx)
  end

  test "key_down and key_up reach handle_event/2", %{ctx: ctx} do
    inject(ctx, {:key_down, :left, []})
    inject(ctx, {:key_down, :up, []})
    assert Drafter.Test.get_state(ctx).held == MapSet.new([:left, :up])

    inject(ctx, {:key_up, :left, []})
    assert Drafter.Test.get_state(ctx).held == MapSet.new([:up])

    assert :ok ==
             Drafter.Test.wait_for(ctx, fn c -> Drafter.Test.screen_text(c) =~ "held=up\n" end)
  end

  test "the terminal's confirmation is recorded in the session before the app sees it",
       %{ctx: ctx} do
    inject(ctx, {:key_release_support, true})
    assert Drafter.Test.get_state(ctx).supported == true
  end

  test "an app declares whether it wants releases" do
    assert Held.__key_release__()
    refute Plain.__key_release__()
    assert Drafter.terminal_opts(Held) == [mouse_hover: true, key_release: true, cell_size: false]

    assert Drafter.terminal_opts(Plain) == [
             mouse_hover: true,
             key_release: false,
             cell_size: false
           ]
  end
end
