defmodule Drafter.Runtime.AlwaysPacedTest do
  use ExUnit.Case, async: false

  alias Drafter.Test.HeadlessDriver

  defmodule EveryEvent do
    @moduledoc false
    use Drafter.App

    def refresh_rate, do: 200

    def mount(_props), do: %{count: 0}
    def render(state), do: vertical([label("count=#{state.count}")])
    def handle_event({:key, _}, state), do: {:ok, %{state | count: state.count + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Always do
    @moduledoc false
    use Drafter.App, frame_pacing: :always

    def refresh_rate, do: 200

    def mount(_props), do: %{count: 0}
    def render(state), do: vertical([label("count=#{state.count}")])
    def handle_event({:key, _}, state), do: {:ok, %{state | count: state.count + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule Ticking do
    @moduledoc false
    use Drafter.App, frame_pacing: :always

    def refresh_rate, do: 200

    def mount(_props), do: %{ticks: 0}
    def on_ready(state), do: tap(state, fn _ -> Drafter.set_interval(5, :tick) end)
    def render(state), do: vertical([label("ticks=#{state.ticks}")])
    def on_timer(:tick, state), do: %{state | ticks: state.ticks + 1}
  end

  defp renders_during(fun) do
    before = HeadlessDriver.get_render_count()
    fun.()
    HeadlessDriver.get_render_count() - before
  end

  test "by default events draw frames as they come" do
    ctx = Drafter.Test.start_headless(EveryEvent, %{}, size: {20, 4})

    renders = renders_during(fn -> for _ <- 1..5, do: Drafter.Test.send_key(ctx, :x) end)

    assert renders > 2
    Drafter.Test.stop(ctx)
  end

  test "with frame_pacing: :always a burst of events becomes at most two frames" do
    ctx = Drafter.Test.start_headless(Always, %{}, size: {20, 4})
    Process.sleep(250)

    renders = renders_during(fn -> for _ <- 1..5, do: Drafter.Test.send_key(ctx, :x) end)

    assert renders <= 2
    assert Drafter.Test.get_state(ctx).count == 5
    Drafter.Test.stop(ctx)
  end

  test "the deferred frame shows the latest state" do
    ctx = Drafter.Test.start_headless(Always, %{}, size: {20, 4})
    Process.sleep(250)

    for _ <- 1..5, do: Drafter.Test.send_key(ctx, :x)
    Process.sleep(300)
    Drafter.Test.sync(ctx)

    assert Drafter.Test.screen_text(ctx) =~ "count=5"
    Drafter.Test.stop(ctx)
  end

  test "timer ticks are paced too" do
    ctx = Drafter.Test.start_headless(Ticking, %{}, size: {20, 4})

    renders = renders_during(fn -> Process.sleep(400) end)

    assert renders <= 4
    assert Drafter.Test.get_state(ctx).ticks > 20
    Drafter.Test.stop(ctx)
  end

  defmodule TwoScreens do
    @moduledoc false
    use Drafter.App, frame_pacing: :always

    def refresh_rate, do: 200

    def mount(_props), do: %{screen: :form, tabs: 0}

    def render(%{screen: :form}),
      do:
        vertical([
          scrollable([label("a"), label("b"), label("c")], id: :list, height: 2),
          text_input(id: :name)
        ])

    def render(%{screen: :bare} = state), do: vertical([label("bare tabs=#{state.tabs}")])

    def handle_event({:key, :f3}, state), do: {:ok, %{state | tabs: state.tabs}}
    def handle_event({:key, :f2}, state), do: {:ok, %{state | screen: :bare}}

    def handle_event({:key, :tab}, %{screen: :bare} = state),
      do: {:ok, %{state | tabs: state.tabs + 1}}

    def handle_event(_event, state), do: {:noreply, state}
  end

  test "an event right after a screen change is routed against the new screen, not the deferred one" do
    ctx = Drafter.Test.start_headless(TwoScreens, %{}, size: {20, 4})
    Process.sleep(250)
    Drafter.Test.sync(ctx)
    assert Drafter.Test.get_widget_hierarchy(ctx).focused_widget == :list

    Drafter.Test.send_key(ctx, :f3)
    Drafter.Test.send_key(ctx, :f2)
    Drafter.Test.send_key(ctx, :tab)

    assert Drafter.Test.get_state(ctx).tabs == 1
    Drafter.Test.stop(ctx)
  end

  defmodule Retimed do
    @moduledoc false
    use Drafter.App, frame_pacing: :always

    def refresh_rate, do: "5fps"

    def mount(_props), do: %{count: 0}
    def render(state), do: vertical([label("count=#{state.count}")])

    def handle_event({:key, :f}, state),
      do: {:noreply, tap(state, fn _ -> Drafter.set_refresh_rate("100fps") end)}

    def handle_event({:key, _}, state), do: {:ok, %{state | count: state.count + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "set_refresh_rate/1 changes the pacing of a running app" do
    ctx = Drafter.Test.start_headless(Retimed, %{}, size: {20, 4})
    Process.sleep(250)

    slow = renders_during(fn -> for _ <- 1..5, do: Drafter.Test.send_key(ctx, :x) end)
    assert slow <= 2

    Drafter.Test.send_key(ctx, :f)
    Process.sleep(250)
    Drafter.Test.sync(ctx)
    assert Drafter.AppRegistry.get_frame_interval() == 10

    fast =
      renders_during(fn ->
        for _ <- 1..5 do
          Drafter.Test.send_key(ctx, :x)
          Process.sleep(15)
        end
      end)

    assert fast >= 4
    Drafter.Test.stop(ctx)
  end
end
