defmodule Drafter.Runtime.UnmountTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT

  defmodule Tidy do
    @moduledoc false
    use Drafter.App

    def mount(%{owner: owner}), do: %{owner: owner, n: 7}
    def render(state), do: vertical([label("n=#{state.n}")])
    def handle_event({:key, :x}, _state), do: {:stop, :normal}
    def handle_event(_event, state), do: {:noreply, state}

    def unmount(state) do
      send(state.owner, {:unmounted, state.n})
      :ok
    end
  end

  test "unmount runs with the last state when the app stops itself" do
    ctx = DT.start_headless(Tidy, %{owner: self()}, size: {20, 4})
    DT.send_key(ctx, :x)
    assert_receive {:unmounted, 7}, 1_000
  end

  test "unmount runs on the global quit key" do
    ctx = DT.start_headless(Tidy, %{owner: self()}, size: {20, 4})
    DT.send_key(ctx, :q, [:ctrl])
    assert_receive {:unmounted, 7}, 1_000
  end

  test "unmount runs when the session is shut down from outside, as a dropped connection does" do
    ctx = DT.start_headless(Tidy, %{owner: self()}, size: {20, 4})
    send(ctx.app_pid, :shutdown)
    assert_receive {:unmounted, 7}, 1_000
  end

  test "unmount runs when a linked process exits" do
    ctx = DT.start_headless(Tidy, %{owner: self()}, size: {20, 4})
    send(ctx.app_pid, {:EXIT, self(), :normal})
    assert_receive {:unmounted, 7}, 1_000
  end
end
