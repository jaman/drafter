defmodule Drafter.CellSessionTextTest do
  @moduledoc """
  Reading a cell session's screen as text.

  `take_cells/1` hands back styled strips, which a host renders. A host that only
  wants to know what is on screen — a test, a log, an assertion — should not have
  to flatten segments itself, and the answer must match what `Drafter.Test`
  reports for the same app so the two session types agree.
  """

  use ExUnit.Case, async: false

  alias Drafter.CellSession

  defmodule Greeting do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{name: "world"}

    def render(state) do
      vertical([
        label("hello #{state.name}"),
        label("second line")
      ])
    end

    def handle_event({:char, ?!}, state), do: {:ok, %{state | name: "again"}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp wait_until(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met within timeout")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end

  setup do
    session = CellSession.start(Greeting, size: {30, 6})
    on_exit(fn -> CellSession.close(session) end)
    wait_until(fn -> CellSession.take_text(session) =~ "hello world" end)
    %{session: session}
  end

  describe "take_lines/1" do
    test "gives one string per screen row", %{session: session} do
      lines = CellSession.take_lines(session)

      assert length(lines) == 6
      assert Enum.all?(lines, &is_binary/1)
    end

    test "the rows carry the rendered text in order", %{session: session} do
      assert [first, second | _] = CellSession.take_lines(session)

      assert first =~ "hello world"
      assert second =~ "second line"
    end

    test "trailing blanks are trimmed, so a row is its content", %{session: session} do
      [first | _] = CellSession.take_lines(session)

      assert first == "hello world"
    end

    test "an empty row is an empty string rather than a run of spaces", %{session: session} do
      lines = CellSession.take_lines(session)

      assert Enum.at(lines, 5) == ""
    end
  end

  describe "take_text/1" do
    test "joins the rows with newlines", %{session: session} do
      text = CellSession.take_text(session)

      assert text == Enum.join(CellSession.take_lines(session), "\n")
    end

    test "reflects input fed into the session", %{session: session} do
      CellSession.feed_input(session, {:char, ?!})

      wait_until(fn -> CellSession.take_text(session) =~ "hello again" end)

      refute CellSession.take_text(session) =~ "hello world"
    end

    test "reflects a resize", %{session: session} do
      CellSession.resize(session, 40, 3)

      wait_until(fn -> length(CellSession.take_lines(session)) == 3 end)

      assert CellSession.take_text(session) =~ "hello world"
    end
  end

  test "agrees with the strips take_cells/1 returns", %{session: session} do
    alias Drafter.Draw.Strip

    from_strips =
      session
      |> CellSession.take_cells()
      |> Enum.map_join("\n", &String.trim_trailing(Strip.to_plain_text(&1)))

    assert CellSession.take_text(session) == from_strips
  end
end
