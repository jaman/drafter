defmodule Drafter.Terminal.TermiosNif do
  @moduledoc """
  Terminal and pseudoterminal control through the `termios_nif` native library.

  Covers what cannot be done from the BEAM: putting the controlling terminal into
  raw mode, reading and setting window size by ioctl, discarding the operating
  system's input queue, and allocating pseudoterminal pairs.

      {:ok, {cols, rows, _xpixel, _ypixel}} = Drafter.Terminal.TermiosNif.get_winsize()

  The library is loaded from `priv/termios_nif` on module load. A failed load is not
  an error: the Elixir bodies stay in place, so `disable_flow_control/0`,
  `enable_flow_control/0`, `enter_raw_mode/0`, `exit_raw_mode/0`,
  `set_tui_active/0`, `set_tui_inactive/0` and `flush_stdin/0` return
  `:nif_not_loaded`, while every other function raises `ErlangError` with
  `:nif_not_loaded`. Callers must handle whichever applies to the function they use.

  Raw mode is a process-independent property of the terminal. Enter it once and
  leave it once; `Drafter.Terminal.Driver` owns that lifecycle for the local
  terminal.
  """

  @on_load :load_nif

  @typedoc """
  What a function with an Elixir fallback returns.

  `:ok` on success, `:error` when the underlying `tcgetattr`/`tcsetattr` failed,
  and `:nif_not_loaded` when the native library is absent.
  """
  @type termios_result :: :ok | :error | :nif_not_loaded

  @doc """
  Load the native library, leaving the Elixir fallbacks in place if it is missing.

  Runs on module load. Always returns `:ok`, so a missing library never stops the
  module from loading.
  """
  @spec load_nif() :: :ok
  def load_nif do
    nif_path = :filename.join(:code.priv_dir(:drafter), ~c"termios_nif")

    case :erlang.load_nif(nif_path, 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc """
  Clear `IXON`/`IXOFF` on the controlling terminal, so `Ctrl+S` and `Ctrl+Q` reach
  the application.

  The settings in force at the first call are saved, if `enter_raw_mode/0` has not
  already saved them, and are what `exit_raw_mode/0` restores.
  """
  @spec disable_flow_control() :: termios_result()
  def disable_flow_control, do: :nif_not_loaded

  @doc """
  Restore `IXON`/`IXOFF` software flow control on the controlling terminal.

  Sets both bits regardless of whether they were set before, and saves nothing.
  """
  @spec enable_flow_control() :: termios_result()
  def enable_flow_control, do: :nif_not_loaded

  @doc """
  Put the controlling terminal into raw mode, saving the previous settings.

  Input is delivered unbuffered and unechoed, and control characters are passed
  through instead of generating signals. `exit_raw_mode/0` restores what was saved.
  The settings are saved only on the first call that saves them, so entering raw
  mode twice does not lose the original ones.
  """
  @spec enter_raw_mode() :: termios_result()
  def enter_raw_mode, do: :nif_not_loaded

  @doc """
  Restore the terminal settings saved by `enter_raw_mode/0`.

  Returns `:ok` when nothing was ever saved, having changed nothing.
  """
  @spec exit_raw_mode() :: termios_result()
  def exit_raw_mode, do: :nif_not_loaded

  @doc """
  Mark the terminal as held in TUI mode and install a `SIGINT` handler.

  While the mark is set, a `SIGINT` or a normal exit of the emulator restores the
  saved terminal settings and writes the sequences that leave the alternate screen,
  show the cursor and turn mouse reporting off, so a crash does not leave the
  terminal unusable.
  """
  @spec set_tui_active() :: :ok | :nif_not_loaded
  def set_tui_active, do: :nif_not_loaded

  @doc """
  Clear the TUI-mode mark set by `set_tui_active/0` and restore the default
  `SIGINT` handling.
  """
  @spec set_tui_inactive() :: :ok | :nif_not_loaded
  def set_tui_inactive, do: :nif_not_loaded

  @doc """
  Discard the bytes the operating system has queued on standard input but not
  delivered.

  Bytes already read into the emulator are unaffected.
  """
  @spec flush_stdin() :: :ok | :nif_not_loaded
  def flush_stdin, do: :nif_not_loaded

  @doc """
  The controlling terminal's size via `TIOCGWINSZ`, as `{cols, rows, xpixel, ypixel}`.

  Standard output is asked first, standard input second. `{:error, :not_a_tty}`
  means neither is a terminal. The pixel dimensions are zero on terminals that do
  not report them.
  """
  @spec get_winsize() ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}}
          | {:error, :not_a_tty}
  def get_winsize, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  The size of the terminal behind `fd`, as `{cols, rows, xpixel, ypixel}`.

  On failure the error term carries the `strerror` text for `errno` as a binary.
  """
  @spec get_winsize(integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}}
          | {:error, binary()}
  def get_winsize(_fd), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Set the window size of the pty behind `fd` via `TIOCSWINSZ`.

  The kernel then reports the new dimensions to processes on the other side of
  the pty and signals `SIGWINCH` to its foreground process group. Each dimension
  is truncated to 16 bits. A failed ioctl gives `{:error, :ioctl_failed}`.
  """
  @spec set_winsize(
          integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          :ok | {:error, :ioctl_failed}
  def set_winsize(_fd, _cols, _rows, _xpixel, _ypixel), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Allocate a pseudo-terminal pair sized `cols` by `rows`.

  Returns `{master_fd, slave_fd, slave_path}`. The master is the side this
  process reads and writes — hand it to `:erlang.open_port({:fd, master, master},
  [:binary])` to get ordinary Erlang message-passing I/O. The slave is what a
  child process uses as its controlling terminal, either by inheriting the
  descriptor or by opening `slave_path`.

  Does no forking or exec'ing. Both descriptors must be released with
  `close_fd/1`. On failure the error term carries the `strerror` text for `errno`
  as a binary.
  """
  @spec open_pty(non_neg_integer(), non_neg_integer()) ::
          {:ok, {integer(), integer(), binary()}} | {:error, binary()}
  def open_pty(_cols, _rows), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Close a descriptor returned by `open_pty/2`.

  On failure the error term carries the `strerror` text for `errno` as a binary,
  so closing the same descriptor twice gives `{:error, "Bad file descriptor"}`.
  """
  @spec close_fd(integer()) :: :ok | {:error, binary()}
  def close_fd(_fd), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Send `signal` to the process group led by `pid`.

  `pid` is a process group leader's id, which for a program started by
  `Drafter.Pty.spawn/2` is the program's own pid — it is made a session and group
  leader. Signalling the group reaches the children it started as well.

  Signal `0` delivers nothing and reports only whether the group still exists,
  giving `{:error, "No such process"}` when it does not. A `pid` of zero or less
  raises `ArgumentError` rather than signalling the caller's own group.
  """
  @spec killpg(pos_integer(), non_neg_integer()) :: :ok | {:error, binary()}
  def killpg(_pid, _signal), do: :erlang.nif_error(:nif_not_loaded)
end
