defmodule Drafter.Regression.Stage3SharedSessionTest do
  use ExUnit.Case, async: false

  alias Drafter.CellSession
  alias Drafter.Session.SharedState

  defmodule ChatApp do
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{messages: 0}
    def render(state), do: vertical([label("messages: #{state.messages}")])
    def handle_event({:char, ?m}, state), do: {:ok, %{state | messages: state.messages + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp row_text(strip), do: Enum.map_join(strip.segments, "", & &1.text)
  defp text(session), do: session |> CellSession.take_cells() |> Enum.map_join("\n", &row_text/1)

  defp wait_until(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end

  test "two shared sessions stay in sync: input to one updates the other" do
    shared = SharedState.get_or_start(ChatApp)
    SharedState.update_state(shared, %{messages: 0})

    a = CellSession.start(ChatApp, shared: shared, size: {30, 4})
    b = CellSession.start(ChatApp, shared: shared, size: {30, 4})

    wait_until(fn -> text(a) =~ "messages: 0" and text(b) =~ "messages: 0" end)

    # input to session A mutates the shared state; B must see it via broadcast
    CellSession.feed_input(a, {:char, ?m})

    wait_until(fn -> text(a) =~ "messages: 1" end)
    wait_until(fn -> text(b) =~ "messages: 1" end)

    CellSession.close(a)
    CellSession.close(b)
  end
end
