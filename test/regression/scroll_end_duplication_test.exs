defmodule Drafter.Regression.ScrollEndDuplicationTest do
  use ExUnit.Case, async: false

  alias Drafter.CellSession

  defmodule CodeApp do
    use Drafter.App
    import Drafter.App

    def mount(_props) do
      %{source: Enum.map_join(1..40, "\n", fn n -> "line #{n} content" end)}
    end

    def render(state) do
      vertical([
        label("codeview demo"),
        code_view(state.source, language: :text, show_line_numbers: true, flex: 1)
      ])
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  defp row_text(strip), do: Enum.map_join(strip.segments, "", & &1.text)
  defp screen_text(session), do: Enum.map_join(CellSession.take_cells(session), "\n", &row_text/1)

  defp wait_until(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met within timeout")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end

  test "scrolling to the end shows the tail window without duplicating the last line" do
    session = CellSession.start(CodeApp, size: {50, 12})
    wait_until(fn -> screen_text(session) =~ "line 1 content" end)

    Enum.each(1..60, fn _step ->
      CellSession.feed_input(session, {:key, :down})
      Process.sleep(5)
    end)

    wait_until(fn -> screen_text(session) =~ "line 40 content" end)
    Process.sleep(300)

    rows =
      screen_text(session)
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 =~ "content"))

    duplicated = rows |> Enum.frequencies() |> Enum.filter(fn {_row, count} -> count > 1 end)

    assert duplicated == []
    assert Enum.any?(rows, &(&1 =~ "line 30 content"))
    assert List.last(rows) =~ "line 40 content"

    CellSession.close(session)
  end
end
