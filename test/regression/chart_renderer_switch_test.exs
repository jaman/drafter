defmodule Drafter.Regression.ChartRendererSwitchTest do
  @moduledoc """
  Switching a chart off a pixel renderer must clear the graphic it already sent.

  In pixel mode a chart draws blank cells and paints a terminal image over them;
  in braille or text mode it draws real glyphs and paints nothing. If the image is
  not cleared on the way out, the old graphic stays on screen underneath the new
  glyphs and the two appear to alternate as rows are repainted.
  """

  use ExUnit.Case, async: false

  alias Drafter.Widget.Chart
  alias Drafter.WidgetServer

  defmodule RecordingCompositor do
    @moduledoc false
    use GenServer

    def start_link(parent), do: GenServer.start_link(__MODULE__, parent)

    @impl true
    def init(parent), do: {:ok, parent}

    @impl true
    def handle_cast(
          {:put_image, id, _paint, _clear, _placement},
          parent
        ) do
      send(parent, {:put_image, id})
      {:noreply, parent}
    end

    @impl true
    def handle_cast({:clear_image, id}, parent) do
      send(parent, {:clear_image, id})
      {:noreply, parent}
    end

    def handle_cast(_other, parent), do: {:noreply, parent}
  end

  @rect %{x: 0, y: 0, width: 40, height: 6}
  @data Enum.map(0..79, fn i -> :math.sin(i * 0.15) * 30 + 50 end)

  setup do
    {:ok, comp} = RecordingCompositor.start_link(self())

    theme =
      case Drafter.ThemeManager.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Process.put(:drafter_compositor, comp)
    Process.put(:drafter_theme_manager, theme)
    Drafter.WidgetStripCache.create()
    Drafter.WidgetStripCache.mark_visible(:chart_switch, true)

    {:ok, server} =
      WidgetServer.start_link(
        module: Chart,
        id: :chart_switch,
        rect: @rect,
        props: %{data: @data, chart_type: :line, renderer: :text},
        image_throttle: {1, :ms},
        session_ctx: %{drafter_compositor: comp, drafter_theme_manager: theme}
      )

    Process.sleep(30)
    drain()

    %{server: server}
  end

  defp switch(server, renderer) do
    WidgetServer.update_props(server, %{
      data: @data,
      chart_type: :line,
      renderer: renderer,
      _render_timestamp: 1
    })
  end

  test "a pixel chart paints an image", %{server: server} do
    switch(server, :kitty)

    assert_receive {:put_image, :chart_switch}, 1000
  end

  for renderer <- [:braille, :text] do
    test "switching to #{renderer} clears the image it had painted", %{server: server} do
      switch(server, :kitty)
      assert_receive {:put_image, :chart_switch}, 1000

      switch(server, unquote(renderer))

      assert_receive {:clear_image, :chart_switch}, 1000
    end

    test "a #{renderer} chart touches the image pipeline not at all", %{server: server} do
      switch(server, unquote(renderer))

      refute_receive {:put_image, :chart_switch}, 300
      refute_receive {:clear_image, :chart_switch}, 300
    end

    test "switching to #{renderer} and back paints again", %{server: server} do
      switch(server, :kitty)
      assert_receive {:put_image, :chart_switch}, 1000

      switch(server, unquote(renderer))
      assert_receive {:clear_image, :chart_switch}, 1000

      switch(server, :kitty)

      assert_receive {:put_image, :chart_switch}, 1000
    end
  end

  test "a switch that lands inside the image throttle window still repaints" do
    {:ok, comp} = RecordingCompositor.start_link(self())

    theme =
      case Drafter.ThemeManager.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Process.put(:drafter_compositor, comp)
    Process.put(:drafter_theme_manager, theme)
    Drafter.WidgetStripCache.create()
    Drafter.WidgetStripCache.mark_visible(:throttled, true)

    {:ok, server} =
      WidgetServer.start_link(
        module: Chart,
        id: :throttled,
        rect: @rect,
        props: %{data: @data, chart_type: :line, renderer: :kitty},
        image_throttle: {200, :ms},
        session_ctx: %{drafter_compositor: comp, drafter_theme_manager: theme}
      )

    assert_receive {:put_image, :throttled}, 1000
    drain()

    WidgetServer.update_props(server, %{
      data: @data,
      chart_type: :line,
      renderer: :text,
      _render_timestamp: 2
    })

    assert_receive {:clear_image, :throttled},
                   2000,
                   "the switch happened inside the throttle window and its repaint was dropped"
  end

  test "cycling through every mode never leaves a painted image behind", %{server: server} do
    for renderer <- [:kitty, :braille, :text, :kitty, :braille] do
      switch(server, renderer)
      Process.sleep(40)
    end

    drain()
    switch(server, :text)

    refute_receive {:put_image, :chart_switch}, 300
  end

  defp drain do
    receive do
      {:put_image, _id} -> drain()
      {:clear_image, _id} -> drain()
    after
      0 -> :ok
    end
  end
end
