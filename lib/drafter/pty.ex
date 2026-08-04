defmodule Drafter.Pty do
  @moduledoc """
  Runs a program on a pseudoterminal and hands its byte stream to the caller.

  `spawn/2` allocates a pty, runs `program` on it in a new session with the pty as
  its controlling terminal, and returns a handle holding two ports. No relaying
  process stands between the caller and the program; `os_pid/1` is the program's own
  pid.

      {:ok, pty} = Drafter.Pty.spawn("/bin/sh", args: ["-i"], cols: 100, rows: 30)
      Drafter.Pty.write(pty, "echo hi\\n")

  The process that called `spawn/2` owns both ports and receives:

    * `{port, {:data, bytes}}` — output, where `port` is the handle's `io` port
    * `{port, {:exit_status, status}}` — exit, where `port` is the handle's `control`
      port

  Bytes written with `write/2` go to the program's standard input. `resize/3` sets the
  terminal size, which makes the kernel deliver `SIGWINCH` to the foreground process
  group.

  The slave descriptor stays open for the lifetime of the handle. Exit is therefore
  reported only through `:exit_status` on the control port; the io port does not
  reach end-of-file when the program exits. `close/1` releases both descriptors.

  Setup failures are reported as an exit status rather than written to the host's
  error output:

    * `64` — too few arguments
    * `71` — the pseudoterminal could not be opened or redirected
    * `127` — the program could not be executed; the reason is written to the
      pseudoterminal and so appears in the terminal output
  """

  alias Drafter.Terminal.TermiosNif

  @sigkill 9

  defstruct [:control, :io, :master, :slave, :slave_path]

  @type t :: %__MODULE__{
          control: port(),
          io: port(),
          master: integer(),
          slave: integer(),
          slave_path: binary()
        }

  @default_term "xterm-256color"

  @doc """
  Run `program` on a new pseudoterminal.

  `program` is an executable, resolved with `execvp`: a name without a slash is
  looked up on the `PATH` the emulator was started with, and a name with one is
  used as given.

  Options:

    * `:args` — argument list, default `[]`
    * `:cols`, `:rows` — initial terminal size in cells, default `80` by `24`
    * `:env` — extra environment as a list of `{name, value}` string pairs, default
      `[]`. It is added to `TERM` rather than to the caller's environment: the
      program inherits the emulator's environment with these entries applied on top.
    * `:term` — value for `TERM`, default `"xterm-256color"`
    * `:cd` — working directory for the program, default the caller's

  Returns `{:ok, handle}`. `{:error, :helper_missing}` means the `pty_spawn` helper
  is not in `priv`; `{:error, reason}` from the pty allocation means no
  pseudoterminal was available, and carries the `strerror` text as a binary. The
  calling process becomes the owner of both ports and must call `close/1` when
  finished.

  A program that cannot be executed is still reported as a successful spawn; the
  failure arrives as an exit status on the control port.
  """
  @spec spawn(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def spawn(program, opts \\ []) do
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)

    with {:ok, {master, slave, slave_path}} <- TermiosNif.open_pty(cols, rows),
         {:ok, helper} <- helper_path() do
      control =
        Port.open({:spawn_executable, helper}, port_options(helper, slave_path, program, opts))

      io = :erlang.open_port({:fd, master, master}, [:binary, :stream])

      {:ok,
       %__MODULE__{
         control: control,
         io: io,
         master: master,
         slave: slave,
         slave_path: slave_path
       }}
    end
  end

  @doc "Send bytes to the program's standard input."
  @spec write(t(), iodata()) :: :ok
  def write(%__MODULE__{io: io}, data) do
    Port.command(io, data)
    :ok
  end

  @doc """
  Set the terminal size to `cols` by `rows` cells.

  The kernel then reports the new size to the program and delivers `SIGWINCH` to the
  foreground process group. `{:error, :ioctl_failed}` means the master descriptor is
  no longer a pty, which is the case once `close/1` has run.
  """
  @spec resize(t(), pos_integer(), pos_integer()) :: :ok | {:error, :ioctl_failed}
  def resize(%__MODULE__{master: master}, cols, rows) do
    TermiosNif.set_winsize(master, cols, rows, 0, 0)
  end

  @doc """
  The operating system pid of the running program.

  Returns `:error` once the control port has closed, which is the case after the
  program exits or `close/1` runs.
  """
  @spec os_pid(t()) :: {:ok, non_neg_integer()} | :error
  def os_pid(%__MODULE__{control: control}) do
    case Port.info(control, :os_pid) do
      {:os_pid, pid} -> {:ok, pid}
      nil -> :error
    end
  end

  @doc """
  Shut the pseudoterminal down.

  Closes both ports and releases both descriptors. Releasing the last descriptor
  makes the kernel send `SIGHUP` to the session, ending the program if it is still
  running. Safe to call more than once; the handle is unusable afterwards.

  ## Options

    * `:kill_after` — milliseconds to wait before sending `SIGKILL` to the
      program's process group, for a program that ignores `SIGHUP`. Omitted by
      default, which sends nothing further. The signal goes to the group, so
      children the program started go with it, and is skipped if the group has
      already gone.

  Background jobs a shell placed in their own process groups are not reached,
  which is also true of the terminal emulator you are reading this in.

      Drafter.Pty.close(pty, kill_after: 2_000)

  """
  @spec close(t(), keyword()) :: :ok
  def close(%__MODULE__{} = pty, opts \\ []) do
    os_pid = pty |> os_pid() |> pid_or_nil()

    close_port(pty.io)
    close_port(pty.control)
    TermiosNif.close_fd(pty.slave)
    TermiosNif.close_fd(pty.master)

    escalate(os_pid, Keyword.get(opts, :kill_after))
  end

  defp pid_or_nil({:ok, pid}), do: pid
  defp pid_or_nil(:error), do: nil

  defp escalate(nil, _after_ms), do: :ok
  defp escalate(_os_pid, nil), do: :ok

  defp escalate(os_pid, after_ms) when is_integer(after_ms) and after_ms >= 0 do
    Kernel.spawn(fn ->
      Process.sleep(after_ms)

      if TermiosNif.killpg(os_pid, 0) == :ok do
        TermiosNif.killpg(os_pid, @sigkill)
      end
    end)

    :ok
  end

  defp close_port(port) do
    if is_port(port) and Port.info(port) != nil, do: Port.close(port)
    :ok
  catch
    :error, _ -> :ok
  end

  defp port_options(_helper, slave_path, program, opts) do
    args = [slave_path, program | Keyword.get(opts, :args, [])]

    base = [:binary, :exit_status, :hide, {:args, args}, {:env, environment(opts)}]

    case Keyword.get(opts, :cd) do
      nil -> base
      dir -> [{:cd, dir} | base]
    end
  end

  defp environment(opts) do
    term = Keyword.get(opts, :term, @default_term)
    extra = Keyword.get(opts, :env, [])

    for {name, value} <- [{"TERM", term} | extra] do
      {String.to_charlist(name), String.to_charlist(value)}
    end
  end

  defp helper_path do
    path = Path.join(:code.priv_dir(:drafter), "pty_spawn")

    if File.exists?(path), do: {:ok, String.to_charlist(path)}, else: {:error, :helper_missing}
  end
end
