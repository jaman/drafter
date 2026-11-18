defmodule Drafter.Prompt.Capture do
  @moduledoc false

  @enforce_keys [:device, :original]
  defstruct [:device, :original]

  @type t :: %__MODULE__{device: pid(), original: pid()}

  @doc """
  Send what the calling process writes to its group leader to `sink` instead, as
  `{:output, binary}` messages. Processes the caller starts meanwhile are captured
  too. Every other request still reaches the original group leader.
  """
  @spec start(pid()) :: t()
  def start(sink) do
    original = Process.group_leader()
    device = spawn(fn -> capture(sink, original) end)
    Process.group_leader(self(), device)
    %__MODULE__{device: device, original: original}
  end

  @doc """
  Give the calling process its group leader back.

  Returns once everything written so far has been sent to the sink. A process that
  was started during the capture and still runs keeps writing through the capture,
  which passes its output to the original group leader from now on.
  """
  @spec release(t()) :: :ok
  def release(%__MODULE__{device: device, original: original}) do
    Process.group_leader(self(), original)
    reference = Process.monitor(device)
    send(device, {:release, self(), reference})

    receive do
      {^reference, :released} -> Process.demonitor(reference, [:flush])
      {:DOWN, ^reference, :process, _pid, _reason} -> :ok
    end

    unless in_use?(device), do: send(device, :stop)
    :ok
  end

  defp in_use?(device) do
    Enum.any?(Process.list(), &(Process.info(&1, :group_leader) == {:group_leader, device}))
  end

  defp capture(sink, original) do
    receive do
      {:io_request, from, reply_as, request} ->
        handle(output(request), {from, reply_as, request}, sink, original)
        capture(sink, original)

      {:release, from, reference} ->
        send(from, {reference, :released})
        pass(original)
    end
  end

  defp pass(original) do
    receive do
      {:io_request, _from, _reply_as, _request} = request ->
        send(original, request)
        pass(original)

      :stop ->
        :ok
    end
  end

  defp handle({:ok, text}, {from, reply_as, _request}, sink, _original) do
    send(sink, {:output, text})
    send(from, {:io_reply, reply_as, :ok})
  end

  defp handle(:other, {from, reply_as, request}, _sink, original),
    do: send(original, {:io_request, from, reply_as, request})

  defp output({:put_chars, encoding, characters}), do: text(characters, encoding)

  defp output({:put_chars, encoding, module, function, arguments}),
    do: text(apply(module, function, arguments), encoding)

  defp output({:put_chars, characters}), do: text(characters, :latin1)
  defp output(_request), do: :other

  defp text(characters, encoding) do
    case :unicode.characters_to_binary(characters, encoding) do
      binary when is_binary(binary) -> {:ok, binary}
      _invalid -> :other
    end
  end
end
