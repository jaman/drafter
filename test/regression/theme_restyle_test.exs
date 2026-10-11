defmodule Drafter.Regression.ThemeRestyleTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip
  alias Drafter.Test, as: TUI

  defmodule Titled do
    @moduledoc false
    use Drafter.App
    import Drafter.App

    def mount(_props), do: %{}

    def render(_state), do: vertical([header("Title"), label("body", flex: 1), footer()])

    def handle_event({:key, :t}, state) do
      Drafter.ThemeManager.set_theme("textual-light")
      {:ok, state}
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  test "a widget whose props did not change takes a new theme at once" do
    ctx = TUI.start_headless(Titled, %{}, size: {60, 10})
    compositor = ctx.session_pids[:drafter_compositor]

    header_row = fn ->
      compositor
      |> Drafter.Compositor.get_buffer()
      |> hd()
      |> Strip.to_ansi()
      |> IO.iodata_to_binary()
    end

    before = header_row.()
    TUI.send_key(ctx, :t)

    assert :ok == TUI.wait_for(ctx, fn _ -> header_row.() != before end, timeout: 1_000)
    TUI.stop(ctx)
  end
end
