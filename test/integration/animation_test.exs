defmodule Drafter.Integration.AnimationTest do
  use ExUnit.Case, async: false

  alias Drafter.Test, as: TUI

  defmodule Fader do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{started: false}

    def render(_state) do
      vertical([label("FADE ME", id: :target)])
    end

    def handle_event({:key, :g}, state) do
      Drafter.animate(:target, :opacity, 0.0, duration: 400)
      {:ok, %{state | started: true}}
    end
  end

  defmodule Slider do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{}
    def render(_state), do: vertical([label("SLIDE", id: :target)])

    def handle_event({:key, :g}, state) do
      Drafter.animate(:target, :offset_y, 3, duration: 400)
      {:ok, state}
    end
  end

  defp start(app) do
    ctx = TUI.start_headless(app, %{}, size: {30, 8})
    on_exit(fn -> TUI.stop(ctx) end)
    TUI.wait_for(ctx, fn c -> TUI.get_widget_hierarchy(c) != nil end, timeout: 2000)
    ctx
  end

  defp widget_state(ctx) do
    case TUI.get_widget_hierarchy(ctx) do
      %{widgets: %{target: %{state: state}}} -> state
      _ -> %{}
    end
  end

  defp opacity(ctx), do: Map.get(widget_state(ctx), :opacity)

  test "a tween reports intermediate values, not only its final one" do
    ctx = start(Fader)
    TUI.send_key(ctx, :g)

    seen =
      Enum.reduce(1..25, MapSet.new(), fn _, acc ->
        Process.sleep(20)

        case opacity(ctx) do
          nil -> acc
          value -> MapSet.put(acc, Float.round(value * 1.0, 2))
        end
      end)

    intermediates = Enum.reject(seen, &(&1 in [0.0, 1.0]))

    assert intermediates != [],
           "a tween that only delivers its endpoints is not an animation; saw #{inspect(Enum.sort(seen))}"
  end

  test "a tween settles on its target value" do
    ctx = start(Fader)
    TUI.send_key(ctx, :g)
    TUI.wait_for(ctx, fn c -> opacity(c) == 0.0 end, timeout: 2000)

    assert opacity(ctx) == 0.0
  end

  test "an offset tween moves the widget" do
    ctx = start(Slider)
    TUI.send_key(ctx, :g)

    TUI.wait_for(
      ctx,
      fn c ->
        Map.get(widget_state(c), :offset_y, 0) != 0
      end,
      timeout: 2000
    )

    assert Map.get(widget_state(ctx), :offset_y) != 0
  end
end
