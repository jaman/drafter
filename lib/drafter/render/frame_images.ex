defmodule Drafter.Render.FrameImages do
  @moduledoc """
  The images of the frame being rendered, drawn before the frame is written.

  While the renderer builds a frame it records, with `queue/3`, every widget whose
  image (`c:Drafter.Widget.image_raster/2`) is on screen. `ops/0` then asks all of
  those widgets for their image at once, each drawn in its own widget server in
  parallel, and returns the operations `Drafter.Compositor.present_frame/2` applies
  together with the frame's text. Each widget draws at the cell size the calling
  process's session holds (`Drafter.Session.Context.cell_size/0`). The queue is kept
  in the calling process and emptied by `ops/0`.
  """

  alias Drafter.Session.Context
  alias Drafter.WidgetServer

  @queue_key :drafter_frame_images
  @frame_image_timeout 5_000

  @type placement :: %{anchor: map(), window: map() | nil}

  @doc """
  Record that the widget `id`, served by `pid`, shows its image at `placement` in the
  frame being rendered: `anchor` is the widget's on-screen rect and `window` the
  screen cells it may be drawn inside, or `nil` for all of them.
  """
  @spec queue(term(), pid(), placement()) :: :ok
  def queue(id, pid, placement) do
    Process.put(@queue_key, [{id, pid, placement} | Process.get(@queue_key, [])])
    :ok
  end

  @doc """
  Draw every queued image and return the compositor operations for them, in the
  order they were queued: `{:put, ...}` before `{:place, ...}` for an image with new
  bytes, `{:place, ...}` alone for one whose bytes still hold, and `{:clear, id}` for
  one the widget no longer draws. Empties the queue.
  """
  @spec ops() :: [tuple()]
  def ops do
    case Process.delete(@queue_key) do
      nil -> []
      queued -> queued |> Enum.reverse() |> Enum.uniq_by(&elem(&1, 0)) |> drawn()
    end
  end

  defp drawn(queued) do
    cell_size = Context.cell_size()

    queued
    |> Task.async_stream(&answer(&1, cell_size), timeout: :infinity, ordered: true)
    |> Enum.flat_map(fn {:ok, {id, placement, answer}} -> image_ops(id, placement, answer) end)
  end

  defp answer({id, pid, placement}, cell_size) do
    answer = WidgetServer.frame_image(pid, window(placement), cell_size, @frame_image_timeout)
    {id, placement, answer}
  end

  defp window(%{anchor: anchor, window: nil}),
    do: %{x: 0, y: 0, width: anchor.width, height: anchor.height}

  defp window(%{anchor: anchor, window: window}),
    do: %{window | x: window.x - anchor.x, y: window.y - anchor.y}

  defp image_ops(id, placement, {:put, paint, clear, region}),
    do: [{:put, id, paint, clear, region}, place(id, placement)]

  defp image_ops(id, placement, :current), do: [place(id, placement)]
  defp image_ops(id, _placement, :none), do: [{:clear, id}]

  defp place(id, %{anchor: anchor, window: window}), do: {:place, id, anchor.x, anchor.y, window}
end
