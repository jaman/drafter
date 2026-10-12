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

    def handle_event({:key, :!}, state), do: {:ok, %{state | name: "again"}}
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

    test "trailing blanks are trimmed, so a row is its content", %{session: session} do
      [first | _] = CellSession.take_lines(session)

      assert first == "hello world"
    end
  end

  describe "take_text/1" do
    test "reflects input fed into the session", %{session: session} do
      CellSession.feed_input(session, {:key, :!})

      wait_until(fn -> CellSession.take_text(session) =~ "hello again" end)

      refute CellSession.take_text(session) =~ "hello world"
    end

    test "reflects a resize", %{session: session} do
      CellSession.resize(session, 40, 3)

      wait_until(fn -> length(CellSession.take_lines(session)) == 3 end)

      assert CellSession.take_text(session) =~ "hello world"
    end
  end
end
