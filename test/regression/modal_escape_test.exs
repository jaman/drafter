defmodule Drafter.Regression.ModalEscapeTest do
  use ExUnit.Case, async: false

  alias Drafter.CellSession

  defmodule ListModal do
    use Drafter.Screen

    def mount(_props), do: %{}

    def render(_state) do
      vertical([
        label("pick one"),
        option_list([{"first", 0}, {"second", 1}], id: :modal_list, on_select: :picked, height: :auto)
      ])
    end

    def handle_event({:key, :escape}, _data, _state), do: {:pop, :dismissed}
    def handle_event(_event, _data, state), do: {:noreply, state}
  end

  defmodule HostApp do
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{}
    def render(_state), do: vertical([label("host screen")])

    def handle_event({:char, ?m}, _state) do
      {:show_modal, ListModal, %{}, [title: "Modal", width: 30, height: 8]}
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

  test "escape dismisses a modal even when a widget inside it has focus" do
    session = CellSession.start(HostApp, size: {60, 16})
    wait_until(fn -> screen_text(session) =~ "host screen" end)

    CellSession.feed_input(session, {:char, ?m})
    wait_until(fn -> screen_text(session) =~ "pick one" end)

    CellSession.feed_input(session, {:key, :escape})
    wait_until(fn -> not (screen_text(session) =~ "pick one") end)

    CellSession.close(session)
  end
end
