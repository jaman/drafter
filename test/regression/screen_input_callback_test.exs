defmodule Drafter.Regression.ScreenInputCallbackTest do
  use ExUnit.Case, async: false

  alias Drafter.CellSession

  defmodule InputModal do
    use Drafter.Screen

    def mount(_props), do: %{name: ""}

    def render(state) do
      vertical([
        label("typed <#{state.name}>"),
        text_input(id: :modal_name_input, on_change: :name_changed)
      ])
    end

    def handle_event(:name_changed, {text, _validation}, state), do: {:ok, %{state | name: text}}
    def handle_event({:key, :escape}, _data, _state), do: {:pop, :dismissed}
    def handle_event(_event, _data, state), do: {:noreply, state}
  end

  defmodule HostApp do
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{last_change: nil}

    def render(state) do
      vertical([
        label("host <#{inspect(state.last_change)}>"),
        text_input(id: :host_input, on_change: :host_changed)
      ])
    end

    def handle_event({:key, :f2}, _state) do
      {:show_modal, InputModal, %{}, [title: "Input", width: 90, height: 8]}
    end

    def handle_event(:host_changed, {text, _validation}, state) do
      {:ok, %{state | last_change: text}}
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  defp row_text(strip), do: Enum.map_join(strip.segments, "", & &1.text)
  defp screen_text(session), do: Enum.map_join(CellSession.take_cells(session), "\n", &row_text/1)

  defp wait_until(session, pattern, tries \\ 200) do
    cond do
      screen_text(session) =~ pattern -> :ok
      tries == 0 -> flunk("never saw #{inspect(pattern)}; screen:\n#{screen_text(session)}")
      true -> Process.sleep(10) && wait_until(session, pattern, tries - 1)
    end
  end

  test "typing in a modal text_input delivers on_change to the screen, not the app" do
    session = CellSession.start(HostApp, size: {60, 14})
    wait_until(session, "host <nil>")

    CellSession.feed_input(session, {:key, :f2})
    wait_until(session, "typed <>")

    CellSession.feed_input(session, {:key, :tab})
    CellSession.feed_input(session, {:key, :a})
    CellSession.feed_input(session, {:char, ?b})

    wait_until(session, "typed <ab>")
    assert screen_text(session) =~ "host <nil>"

    CellSession.close(session)
  end

  test "with no screens open on_change still reaches the app" do
    session = CellSession.start(HostApp, size: {60, 14})
    wait_until(session, "host <nil>")

    CellSession.feed_input(session, {:key, :tab})
    CellSession.feed_input(session, {:char, ?z})

    wait_until(session, ~s(host <"z">))
    CellSession.close(session)
  end

  test "typing many characters into a modal input stays responsive" do
    session = CellSession.start(HostApp, size: {100, 14})
    wait_until(session, "host <nil>")

    CellSession.feed_input(session, {:key, :f2})
    wait_until(session, "typed <>")
    CellSession.feed_input(session, {:key, :tab})

    typed = String.duplicate("a", 40)

    started = System.monotonic_time(:millisecond)
    Enum.each(1..40, fn _n -> CellSession.feed_input(session, {:char, ?a}) end)
    wait_until(session, "typed <#{typed}>")
    elapsed = System.monotonic_time(:millisecond) - started

    assert elapsed < 3_000, "40 modal keystrokes took #{elapsed}ms — input path is not keeping up"

    CellSession.close(session)
  end
end
