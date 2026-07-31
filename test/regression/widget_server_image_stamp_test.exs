defmodule Drafter.Regression.WidgetServerImageStampTest do
  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip

  alias Drafter.WidgetServer

  defmodule RecordingCompositor do
    use GenServer

    def start_link(parent), do: GenServer.start_link(__MODULE__, parent)

    @impl true
    def init(parent), do: {:ok, parent}

    @impl true
    def handle_cast(
          {:put_image, _id, _paint, _clear, _dx, _dy, _cols, _rows, stamp, _place},
          parent
        ) do
      send(parent, {:put_image_stamp, stamp})
      {:noreply, parent}
    end

    def handle_cast(_other, parent), do: {:noreply, parent}
  end

  defmodule StampWidget do
    @moduledoc false

    defstruct value: 0

    def mount(props), do: %__MODULE__{value: Map.get(props, :value, 0)}

    def render(_state, rect) do
      blank = Strip.from_text(String.duplicate(" ", max(1, rect.width)))
      List.duplicate(blank, max(1, rect.height))
    end

    def image(state, rect, _id) do
      {"FRAME_#{state.value}", "", %{dx: 0, dy: 0, cols: rect.width, rows: rect.height}}
    end
  end

  test "image generation stamps each put_image with a monotonically increasing per-widget number" do
    {:ok, comp} = RecordingCompositor.start_link(self())
    Process.put(:drafter_compositor, comp)
    Drafter.WidgetStripCache.create()
    Drafter.WidgetStripCache.mark_visible(:stamp_widget, true)

    {:ok, server} =
      WidgetServer.start_link(
        module: StampWidget,
        id: :stamp_widget,
        rect: %{x: 0, y: 0, width: 6, height: 2},
        image_throttle: {1, :ms},
        session_ctx: %{drafter_compositor: comp}
      )

    WidgetServer.set_state(server, %StampWidget{value: 1})
    assert_receive {:put_image_stamp, first}, 500

    Process.sleep(20)
    WidgetServer.set_state(server, %StampWidget{value: 2})
    assert_receive {:put_image_stamp, second}, 500
    assert second > first
  end
end
