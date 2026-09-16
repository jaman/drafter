defmodule Drafter.Regression.BoundStateBurstTest do
  @moduledoc """
  A bound value is current by the time the next event is handled, even when the
  keystrokes arrived in one burst ahead of the widget's update messages.
  """

  use ExUnit.Case, async: false

  alias Drafter.Test, as: DT
  alias Drafter.Test.HeadlessDriver

  defmodule Form do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{name: "", submitted: nil}
    def on_ready(state), do: tap(state, fn _ -> Drafter.focus(:name) end)

    def render(state),
      do: vertical([text_input(id: :name, bind: :name), label("submitted=#{state.submitted}")])

    def handle_event({:key, :enter}, state), do: {:ok, %{state | submitted: state.name}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    ctx = DT.start_headless(Form, %{}, size: {40, 6})
    on_exit(fn -> DT.stop(ctx) end)
    {:ok, ctx: ctx}
  end

  test "enter sees the characters typed just before it", %{ctx: ctx} do
    for char <- ~w(a l i c e)a, do: HeadlessDriver.inject_event({:key, char})
    HeadlessDriver.inject_event({:key, :enter})
    DT.sync(ctx)

    assert DT.get_state(ctx).submitted == "alice"
  end
end
