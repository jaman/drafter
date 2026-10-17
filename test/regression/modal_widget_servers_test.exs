defmodule Drafter.Regression.ModalWidgetServersTest do
  use ExUnit.Case, async: false

  import Drafter.Test

  defmodule PickScreen do
    use Drafter.Screen

    def render(_state), do: vertical([label("inside", id: :inside)])

    def handle_event({:key, :enter}, _state) do
      Drafter.send_app_event(:reveal, nil)
      {:pop, :done}
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule RevealApp do
    use Drafter

    state(%{reveal: false, ticks: 0})

    keybinding :m, "menu" do
      {:show_modal, PickScreen, %{}, [width: 20, height: 5]}
    end

    keybinding :t, "tick" do
      {:ok, %{state | ticks: state.ticks + 1}}
    end

    def handle_event(:reveal, _data, state), do: {:ok, %{state | reveal: true}}
    def handle_event(_name, _data, state), do: {:noreply, state}

    def render(state) do
      revealed = if state.reveal, do: [label("revealed #{state.ticks}", id: :revealed)], else: []
      vertical([label("base #{state.ticks}") | revealed])
    end
  end

  defp servers_for(id) do
    for pid <- Process.list(),
        {:dictionary, dictionary} <- [Process.info(pid, :dictionary) || {:dictionary, []}],
        match?({Drafter.WidgetServer, _, _}, dictionary[:"$initial_call"]),
        state = :sys.get_state(pid, 1000),
        state.id == id,
        do: pid
  end

  test "a widget mounted as a modal closes runs as one server, and the modal's servers stop" do
    ctx = start_headless(RevealApp, %{}, size: {40, 12})
    on_exit(fn -> stop(ctx) end)

    send_key(ctx, :m)
    get_state(ctx)
    assert length(servers_for(:inside)) == 1

    send_key(ctx, :enter)
    get_state(ctx)
    send_key(ctx, :t)
    send_key(ctx, :t)
    get_state(ctx)

    assert length(servers_for(:revealed)) == 1
    assert servers_for(:inside) == []
  end
end
