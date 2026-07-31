defmodule Drafter.Terminal.TermiosNif do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    nif_path = :filename.join(:code.priv_dir(:drafter), ~c"termios_nif")

    case :erlang.load_nif(nif_path, 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  def disable_flow_control, do: :nif_not_loaded
  def enable_flow_control, do: :nif_not_loaded
  def enter_raw_mode, do: :nif_not_loaded
  def exit_raw_mode, do: :nif_not_loaded
  def set_tui_active, do: :nif_not_loaded
  def set_tui_inactive, do: :nif_not_loaded
  def flush_stdin, do: :nif_not_loaded

  @doc """
  The controlling terminal's size via `TIOCGWINSZ`, as `{cols, rows, xpixel, ypixel}`.

  The pixel dimensions are zero on terminals that do not report them.
  """
  @spec get_winsize() ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}}
          | {:error, atom()}
          | {:error, atom()}
  def get_winsize, do: :erlang.nif_error(:nif_not_loaded)

  @doc "The size of the terminal behind `fd`, as `{cols, rows, xpixel, ypixel}`."
  @spec get_winsize(integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}}
          | {:error, binary()}
  def get_winsize(_fd), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Set the window size of the pty behind `fd` via `TIOCSWINSZ`.

  The kernel then reports the new dimensions to processes on the other side of
  the pty and signals `SIGWINCH` to its foreground process group.
  """
  @spec set_winsize(
          integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          :ok | {:error, atom()}
  def set_winsize(_fd, _cols, _rows, _xpixel, _ypixel), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Allocate a pseudo-terminal pair sized `cols` by `rows`.

  Returns `{master_fd, slave_fd, slave_path}`. The master is the side this
  process reads and writes — hand it to `:erlang.open_port({:fd, master, master},
  [:binary])` to get ordinary Erlang message-passing I/O. The slave is what a
  child process uses as its controlling terminal, either by inheriting the
  descriptor or by opening `slave_path`.

  Does no forking or exec'ing. Both descriptors must be released with
  `close_fd/1`.
  """
  @spec open_pty(non_neg_integer(), non_neg_integer()) ::
          {:ok, {integer(), integer(), binary()}} | {:error, binary()}
  def open_pty(_cols, _rows), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Close a descriptor returned by `open_pty/2`."
  @spec close_fd(integer()) :: :ok | {:error, binary()}
  def close_fd(_fd), do: :erlang.nif_error(:nif_not_loaded)
end
