defmodule Drafter.Regression.ChartRendererSwitchTest do
  @moduledoc """
  Switching a chart off a pixel renderer must withdraw the graphic it already sent.

  In pixel mode a chart draws blank cells and its image is drawn over them; in braille
  or text mode it draws real glyphs and has no image. If the image is not withdrawn on
  the way out, the old graphic stays on screen underneath the new glyphs and the two
  appear to alternate as rows are repainted.
  """

  use ExUnit.Case, async: false

  alias Drafter.Widget.Chart
  alias Drafter.WidgetServer

  @rect %{x: 0, y: 0, width: 40, height: 6}
  @window %{x: 0, y: 0, width: 40, height: 6}
  @data Enum.map(0..79, fn i -> :math.sin(i * 0.15) * 30 + 50 end)

  setup do
    theme =
      case Drafter.ThemeManager.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Process.put(:drafter_theme_manager, theme)
    Drafter.WidgetStripCache.create()

    {:ok, server} =
      WidgetServer.start_link(
        module: Chart,
        id: :chart_switch,
        rect: @rect,
        props: %{data: @data, chart_type: :line, renderer: :text},
        session_ctx: %{drafter_theme_manager: theme}
      )

    %{server: server}
  end

  defp switch(server, renderer) do
    WidgetServer.update_props(server, %{data: @data, chart_type: :line, renderer: renderer})
  end

  defp frame(server), do: WidgetServer.frame_image(server, @window, {9, 18}, 5_000)

  test "a pixel chart has an image for its frame and keeps it while nothing changes",
       %{server: server} do
    switch(server, :kitty)
    assert {:put, _paint, _clear, _region} = frame(server)
    assert frame(server) == :current
  end

  test "switching to braille withdraws the image", %{server: server} do
    switch(server, :kitty)
    assert {:put, _paint, _clear, _region} = frame(server)

    switch(server, :braille)
    assert frame(server) == :none
  end

  test "switching to braille and back draws the image again", %{server: server} do
    switch(server, :kitty)
    assert {:put, _paint, _clear, _region} = frame(server)

    switch(server, :braille)
    assert frame(server) == :none

    switch(server, :kitty)
    assert {:put, _paint, _clear, _region} = frame(server)
  end
end
