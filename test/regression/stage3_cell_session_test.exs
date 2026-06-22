defmodule Drafter.Regression.Stage3CellSessionTest do
  use ExUnit.Case, async: false

  alias Drafter.CellSession

  defmodule CounterApp do
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{count: 0}
    def render(state), do: vertical([label("count: #{state.count}")])
    def handle_event({:char, ?+}, state), do: {:ok, %{state | count: state.count + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp row_text(strip), do: Enum.map_join(strip.segments, "", & &1.text)
  defp text(strips), do: Enum.map_join(strips, "\n", &row_text/1)

  defp wait_until(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met within timeout")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end

  test "renders an app to a cell grid, reacts to input, exposes diffs, resizes" do
    session = CellSession.start(CounterApp, size: {30, 6})

    wait_until(fn -> text(CellSession.take_cells(session)) =~ "count: 0" end)
    assert length(CellSession.take_cells(session)) == 6

    {_first_diff, session} = CellSession.take_cells_diff(session)

    CellSession.feed_input(session, {:char, ?+})
    wait_until(fn -> text(CellSession.take_cells(session)) =~ "count: 1" end)

    {changed, _session} = CellSession.take_cells_diff(session)
    assert Enum.any?(changed, fn {_idx, strip} -> row_text(strip) =~ "count: 1" end)

    CellSession.resize(session, 50, 10)
    wait_until(fn -> length(CellSession.take_cells(session)) == 10 end)

    CellSession.close(session)
  end
end
