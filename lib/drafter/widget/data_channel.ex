defmodule Drafter.Widget.DataChannel do
  @moduledoc """
  Buffered data ingestion channel for a single widget.

  Accepts data pushes into a bounded RingBuffer and throttles
  render notifications. Data accumulates between renders — the
  widget only re-renders when the throttle window opens and new
  data has arrived since the last render.

  A push marks the channel dirty and, unless it is paused or a window is already
  open, schedules a `:data_channel_tick` message to the calling process. With a
  `:on_demand` throttle the message is sent immediately instead of after a delay.
  The owner reacts to the tick by calling `flush/1`, which clears the dirty flag and
  the pending window but leaves the buffer contents in place for
  `c:Drafter.Widget.apply_data_buffer/3` to read.
  """

  alias Drafter.RingBuffer

  defstruct [
    :buffer,
    :throttle_ms,
    :throttle_ref,
    dirty: false,
    paused: false
  ]

  @type t :: %__MODULE__{
          buffer: RingBuffer.t(),
          throttle_ms: pos_integer() | :on_demand,
          throttle_ref: reference() | :immediate | nil,
          dirty: boolean(),
          paused: boolean()
        }

  @doc """
  Opens a channel over a ring buffer of `buffer_size` items.

  `throttle_ms` is the minimum gap in milliseconds between tick notifications, or
  `:on_demand` to notify on the next message pass. The channel starts clean and
  unpaused with no window open.

      iex> ch = Drafter.Widget.DataChannel.new(4, 50)
      iex> {Drafter.Widget.DataChannel.dirty?(ch), Drafter.Widget.DataChannel.paused?(ch)}
      {false, false}
  """
  @spec new(pos_integer(), pos_integer() | :on_demand) :: t()
  def new(buffer_size, throttle_ms) do
    %__MODULE__{
      buffer: RingBuffer.new(buffer_size),
      throttle_ms: throttle_ms
    }
  end

  @doc """
  Appends one item to the buffer, marks the channel dirty and opens a throttle
  window if none is open.

  Pushing to a paused channel still buffers the item but schedules nothing.

      iex> ch = Drafter.Widget.DataChannel.new(4, 50) |> Drafter.Widget.DataChannel.push(:a)
      iex> {Drafter.Widget.DataChannel.dirty?(ch), Drafter.RingBuffer.to_list(Drafter.Widget.DataChannel.buffer(ch))}
      {true, [:a]}
  """
  @spec push(t(), term()) :: t()
  def push(%__MODULE__{} = ch, item) do
    buffer = RingBuffer.push(ch.buffer, item)
    schedule_if_needed(%{ch | buffer: buffer, dirty: true})
  end

  @doc """
  Appends every item of `items` in order, otherwise behaving exactly like `push/2`.

  Only one throttle window is opened for the whole batch. Items beyond the buffer's
  capacity push the oldest ones out.

      iex> ch = Drafter.Widget.DataChannel.new(2, :on_demand)
      iex> ch = Drafter.Widget.DataChannel.push_many(ch, [1, 2, 3])
      iex> Drafter.RingBuffer.to_list(Drafter.Widget.DataChannel.buffer(ch))
      [2, 3]
  """
  @spec push_many(t(), Enumerable.t()) :: t()
  def push_many(%__MODULE__{} = ch, items) do
    buffer = RingBuffer.push_many(ch.buffer, items)
    schedule_if_needed(%{ch | buffer: buffer, dirty: true})
  end

  @doc """
  Closes the throttle window and reports whether anything arrived while it was open.

  Returns `{channel, true}` when the channel was dirty, having cleared both the
  dirty flag and the pending window, and `{channel, false}` unchanged otherwise. The
  buffer is left intact, so the caller still sees every item pushed since the buffer
  was created.

      iex> ch = Drafter.Widget.DataChannel.new(4, 50) |> Drafter.Widget.DataChannel.push(:a)
      iex> {ch, flushed?} = Drafter.Widget.DataChannel.flush(ch)
      iex> {flushed?, Drafter.Widget.DataChannel.dirty?(ch), elem(Drafter.Widget.DataChannel.flush(ch), 1)}
      {true, false, false}
  """
  @spec flush(t()) :: {t(), boolean()}
  def flush(%__MODULE__{dirty: false} = ch), do: {ch, false}

  def flush(%__MODULE__{dirty: true} = ch) do
    {%{ch | dirty: false, throttle_ref: nil}, true}
  end

  @doc """
  Stops tick notifications and cancels any pending window.

  Pushes still land in the buffer and still mark the channel dirty while it is
  paused; `resume/1` opens a window immediately if there is anything to report.

      iex> ch = Drafter.Widget.DataChannel.new(4, 50) |> Drafter.Widget.DataChannel.pause()
      iex> Drafter.Widget.DataChannel.paused?(ch)
      true
  """
  @spec pause(t()) :: t()
  def pause(%__MODULE__{} = ch) do
    ch = cancel_throttle(ch)
    %{ch | paused: true}
  end

  @doc """
  Clears the paused flag and opens a throttle window when the channel is dirty.

      iex> ch = Drafter.Widget.DataChannel.new(4, 50) |> Drafter.Widget.DataChannel.pause()
      iex> Drafter.Widget.DataChannel.resume(ch) |> Drafter.Widget.DataChannel.paused?()
      false
  """
  @spec resume(t()) :: t()
  def resume(%__MODULE__{} = ch) do
    ch = %{ch | paused: false}
    schedule_if_needed(ch)
  end

  @doc """
  Whether the channel is paused.

      iex> Drafter.Widget.DataChannel.new(4, 50) |> Drafter.Widget.DataChannel.paused?()
      false
  """
  @spec paused?(t()) :: boolean()
  def paused?(%__MODULE__{paused: paused}), do: paused

  @doc """
  Whether anything has been pushed since the last `flush/1`.

      iex> Drafter.Widget.DataChannel.new(4, 50) |> Drafter.Widget.DataChannel.dirty?()
      false
  """
  @spec dirty?(t()) :: boolean()
  def dirty?(%__MODULE__{dirty: dirty}), do: dirty

  @doc """
  The channel's ring buffer, holding everything pushed so far up to its capacity.
  """
  @spec buffer(t()) :: RingBuffer.t()
  def buffer(%__MODULE__{buffer: buffer}), do: buffer

  @doc """
  Changes the buffer's capacity, keeping the newest items that still fit. Leaves the
  dirty, paused and throttle state alone.

      iex> ch = Drafter.Widget.DataChannel.new(4, :on_demand)
      iex> ch = Drafter.Widget.DataChannel.push_many(ch, [1, 2, 3, 4])
      iex> ch = Drafter.Widget.DataChannel.resize_buffer(ch, 2)
      iex> Drafter.RingBuffer.to_list(Drafter.Widget.DataChannel.buffer(ch))
      [3, 4]
  """
  @spec resize_buffer(t(), pos_integer()) :: t()
  def resize_buffer(%__MODULE__{} = ch, new_size) do
    %{ch | buffer: RingBuffer.resize(ch.buffer, new_size)}
  end

  defp schedule_if_needed(%__MODULE__{paused: true} = ch), do: ch
  defp schedule_if_needed(%__MODULE__{dirty: false} = ch), do: ch
  defp schedule_if_needed(%__MODULE__{throttle_ref: ref} = ch) when not is_nil(ref), do: ch

  defp schedule_if_needed(%__MODULE__{throttle_ms: ms} = ch) when ms == :on_demand or ms == nil do
    send(self(), :data_channel_tick)
    %{ch | throttle_ref: :immediate}
  end

  defp schedule_if_needed(%__MODULE__{} = ch) do
    ref = Process.send_after(self(), :data_channel_tick, ch.throttle_ms)
    %{ch | throttle_ref: ref}
  end

  defp cancel_throttle(%__MODULE__{throttle_ref: nil} = ch), do: ch

  defp cancel_throttle(%__MODULE__{throttle_ref: ref} = ch) do
    Process.cancel_timer(ref)
    %{ch | throttle_ref: nil}
  end
end
