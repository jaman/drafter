defmodule Drafter.Terminal.RawMode do
  @moduledoc """
  Puts the controlling terminal into raw mode and takes it out again.

  `enter/0` returns how raw mode was entered, and `leave/1` takes that value back to
  undo it:

      {:ok, mode} = Drafter.Terminal.RawMode.enter()
      Drafter.Terminal.RawMode.leave(mode)

  The termios NIF is used where it loads and `stty` otherwise. Off unix neither runs,
  `enter/0` returns `{:ok, nil}`, and the terminal mode is left alone.

  In raw mode input arrives unbuffered and unechoed, control characters such as
  `Ctrl+C` arrive as input instead of raising signals, and a line feed written to the
  terminal no longer returns the cursor to the first column.
  """

  alias Drafter.Terminal.TermiosNif

  @typedoc "How raw mode was entered: by the NIF, by `stty` with the saved settings, or not at all."
  @type mode :: :nif | {:stty, binary()} | nil

  @doc """
  Enter raw mode.

  `{:error, :not_a_terminal}` means standard input is not a terminal, and
  `{:error, {:stty_failed, output}}` that `stty` refused.
  """
  @spec enter() :: {:ok, mode()} | {:error, term()}
  def enter, do: enter(:os.type(), TermiosNif)

  @doc "Restore the terminal settings saved by the `enter/0` that returned `mode`."
  @spec leave(mode()) :: :ok
  def leave(nil), do: :ok

  def leave(:nif) do
    TermiosNif.exit_raw_mode()
    :ok
  end

  def leave({:stty, saved}) do
    System.cmd("stty", [saved], stderr_to_stdout: true)
    :ok
  end

  defp enter({:unix, _name}, termios), do: entered(termios.enter_raw_mode())
  defp enter(_other, _termios), do: {:ok, nil}

  defp entered(:ok), do: {:ok, :nif}
  defp entered(:error), do: {:error, :not_a_terminal}
  defp entered(:nif_not_loaded), do: enter_with_stty()

  defp enter_with_stty do
    with {saved, 0} <- System.cmd("stty", ["-g"], stderr_to_stdout: true),
         {_output, 0} <- System.cmd("stty", ["raw", "-echo", "-ixon"], stderr_to_stdout: true) do
      {:ok, {:stty, String.trim(saved)}}
    else
      {output, _status} -> {:error, {:stty_failed, String.trim(output)}}
    end
  end
end
