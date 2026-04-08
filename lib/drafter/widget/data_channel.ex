defmodule Drafter.Widget.DataChannel do
  @moduledoc """
  Buffered data ingestion channel for a single widget.

  Accepts data pushes into a bounded RingBuffer and throttles
  render notifications. Data accumulates between renders — the
  widget only re-renders when the throttle window opens and new
  data has arrived since the last render.
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
          throttle_ref: reference() | nil,
          dirty: boolean(),
          paused: boolean()
        }

  @spec new(pos_integer(), pos_integer() | :on_demand) :: t()
  def new(buffer_size, throttle_ms) do
    %__MODULE__{
      buffer: RingBuffer.new(buffer_size),
      throttle_ms: throttle_ms
    }
  end

  @spec push(t(), term()) :: t()
  def push(%__MODULE__{} = ch, item) do
    buffer = RingBuffer.push(ch.buffer, item)
    schedule_if_needed(%{ch | buffer: buffer, dirty: true})
  end

  @spec push_many(t(), Enumerable.t()) :: t()
  def push_many(%__MODULE__{} = ch, items) do
    buffer = RingBuffer.push_many(ch.buffer, items)
    schedule_if_needed(%{ch | buffer: buffer, dirty: true})
  end

  @spec flush(t()) :: {t(), boolean()}
  def flush(%__MODULE__{dirty: false} = ch), do: {ch, false}

  def flush(%__MODULE__{dirty: true} = ch) do
    {%{ch | dirty: false, throttle_ref: nil}, true}
  end

  @spec pause(t()) :: t()
  def pause(%__MODULE__{} = ch) do
    ch = cancel_throttle(ch)
    %{ch | paused: true}
  end

  @spec resume(t()) :: t()
  def resume(%__MODULE__{} = ch) do
    ch = %{ch | paused: false}
    schedule_if_needed(ch)
  end

  @spec paused?(t()) :: boolean()
  def paused?(%__MODULE__{paused: paused}), do: paused

  @spec dirty?(t()) :: boolean()
  def dirty?(%__MODULE__{dirty: dirty}), do: dirty

  @spec buffer(t()) :: RingBuffer.t()
  def buffer(%__MODULE__{buffer: buffer}), do: buffer

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
