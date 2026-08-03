defmodule Drafter.SustainedRepaintTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT
  alias Drafter.Test.HeadlessDriver

  defmodule Streaming do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{lines: [], tick: 0}

    def render(state) do
      vertical([
        label("tick #{state.tick}"),
        log(lines: state.lines, max_lines: 200, height: 10)
      ])
    end

    def handle_event(:emit, n, state) do
      {:noreply, %{state | tick: n, lines: Enum.take(state.lines ++ ["line #{n}"], -200)}}
    end

    def handle_event(_event, _data, state), do: {:noreply, state}
  end

  setup do
    ctx = DT.start_headless(Streaming, %{}, size: {60, 20})
    on_exit(fn -> DT.stop(ctx) end)
    DT.wait_for(ctx, fn c -> DT.screen_text(c) =~ "tick 0" end, timeout: 2000)
    {:ok, ctx: ctx}
  end

  defp emit(n) do
    Drafter.send_app_event(:emit, n)
  end

  defp settle do
    Process.sleep(60)
  end

  test "sustained output keeps repainting the terminal", %{ctx: ctx} do
    for n <- 1..40 do
      emit(n)
      Process.sleep(5)
    end

    settle()

    assert DT.screen_text(ctx) =~ "line 40"
    assert DT.screen_text(ctx) =~ "tick 40"
  end

  test "a burst leaves the final frame on screen", %{ctx: ctx} do
    for n <- 1..2000, do: emit(n)
    settle()

    assert DT.screen_text(ctx) =~ "tick 2000",
           "screen stalled at:\n#{DT.screen_text(ctx)}"
  end

  test "repeated bursts each land their final frame", %{ctx: ctx} do
    for round <- 1..5 do
      for n <- 1..200, do: emit(round * 1000 + n)
      settle()

      assert DT.screen_text(ctx) =~ "tick #{round * 1000 + 200}",
             "round #{round} stalled at:\n#{DT.screen_text(ctx)}"
    end
  end

  test "an uninterrupted flood keeps repainting rather than stalling", %{ctx: ctx} do
    before = HeadlessDriver.get_render_count()
    started = System.monotonic_time(:millisecond)

    Enum.each(1..20_000, &emit/1)
    settle()

    elapsed = System.monotonic_time(:millisecond) - started
    writes = HeadlessDriver.get_render_count() - before

    assert writes * 1000 / elapsed >= 30,
           "only #{writes} writes across #{elapsed}ms of flood"

    assert DT.screen_text(ctx) =~ "tick 20000"
  end

  test "the terminal is written to repeatedly, not once", %{ctx: _ctx} do
    before = HeadlessDriver.get_render_count()

    for n <- 1..30 do
      emit(n)
      Process.sleep(20)
    end

    settle()

    writes = HeadlessDriver.get_render_count() - before

    assert writes >= 10, "only #{writes} terminal writes for 30 paced updates"
  end
end
