defmodule Drafter.WidgetDataRenderTest do
  @moduledoc """
  What `Drafter.push_data/2` promises: an item pushed to a widget with a data channel is
  on screen, without the widget having to be disturbed by something else first.
  """

  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT

  defmodule Feed do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{}

    def on_ready(state) do
      Drafter.push_data(:feed, "alpha")
      state
    end

    keybinding :a, "push one" do
      Drafter.push_data(:feed, "bravo")
      {:ok, state}
    end

    keybinding :b, "push several" do
      Drafter.push_data_many(:feed, ["charlie", "delta"])
      {:ok, state}
    end

    def render(_state), do: vertical([box([log(id: :feed, buffer: 50)], title: "Feed", flex: 1)])
  end

  defp settled(ctx) do
    DT.sync(ctx)
    Process.sleep(250)
    DT.await_render(ctx)
    DT.sync(ctx)
    DT.screen_text(ctx)
  end

  setup do
    ctx = DT.start_headless(Feed, %{}, size: {44, 12})
    on_exit(fn -> DT.stop(ctx) end)
    {:ok, ctx: ctx}
  end

  test "an item pushed while the app starts is drawn", %{ctx: ctx} do
    assert settled(ctx) =~ "alpha"
  end

  test "an item pushed while the app runs is drawn", %{ctx: ctx} do
    settled(ctx)
    DT.send_key(ctx, :a)

    assert settled(ctx) =~ "bravo"
  end

  test "every item of a batch is drawn", %{ctx: ctx} do
    settled(ctx)
    DT.send_key(ctx, :b)
    text = settled(ctx)

    assert text =~ "charlie"
    assert text =~ "delta"
  end
end
