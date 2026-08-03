defmodule Drafter.Clipboard do
  @moduledoc """
  Read and write the user's clipboard.

  ## Copying

  `copy/2` writes an OSC 52 sequence to the terminal the session is attached to,
  and additionally to the local machine's clipboard via `pbcopy`, `clip`,
  `wl-copy`, `xclip` or `xsel` when one of those is on `PATH`. For a session
  served over ssh or telnet the sequence reaches the connected client's terminal,
  so the text lands on the client's clipboard.

  Terminals supporting OSC 52 include iTerm2, kitty, WezTerm, foot, Alacritty and
  xterm; some ship with it disabled. tmux passes the sequence through only with
  `set -g set-clipboard on`. The terminal sends no reply, so `copy/2` returns `:ok`
  once the sequence and any local write have been issued and never reports whether
  the terminal accepted it.

  ## Pasting

  Text the user pastes with their terminal's paste key arrives as a bracketed
  paste, delivered as a `{:bracketed_paste, text}` event. A widget receives it by
  declaring `handles: [:paste]` and implementing `handle_paste/2` — see
  `Drafter.Widget`. This is the only path that carries text from a remote client.

  `paste/0` reads the clipboard of the machine the app process runs on, which for a
  remote session is the server rather than the connected user. It shells out to a
  local clipboard tool and never issues an OSC 52 read.

  ## Configuration

      config :drafter, clipboard: false

  or `clipboard: false` passed to `Drafter.run/2` makes `copy/2` and `paste/0`
  no-ops returning `{:error, :disabled}`, and drops bracketed pastes before any
  widget sees them. A keyword list enables the two directions separately:
  `clipboard: [copy: true, paste: false]`. Key bindings are configured with
  `:clipboard_keys` — see `key/1`.
  """

  alias Drafter.Compositor

  @osc52_limit 74_994

  @type target :: :clipboard | :primary

  @doc """
  Put `text` on the clipboard.

  Options:

    * `:target` — `:clipboard` (default) or `:primary`, the X11 primary selection.

  Returns `:ok` once the sequence has been issued, `{:error, :disabled}` when copy
  is switched off, and `{:error, :too_large}` when `text` exceeds 74994 bytes, the
  most an OSC 52 sequence carries.
  """
  @spec copy(String.t(), keyword()) :: :ok | {:error, :disabled | :too_large}
  def copy(text, opts \\ [])

  def copy(text, opts) when is_binary(text) do
    cond do
      not enabled?() -> {:error, :disabled}
      byte_size(text) > @osc52_limit -> {:error, :too_large}
      true -> do_copy(text, Keyword.get(opts, :target, :clipboard))
    end
  end

  @doc """
  The clipboard contents of the machine this app process is running on.

  For a remote session that is the server, not the connected user; the user's own
  clipboard arrives as a bracketed paste instead.

  Returns `{:ok, text}`, `{:error, :unavailable}` when no clipboard tool is on
  `PATH` or the tool fails, and `{:error, :disabled}` when `enabled?/0` is false.
  """
  @spec paste() :: {:ok, String.t()} | {:error, :disabled | :unavailable}
  def paste do
    if enabled?() do
      read_local()
    else
      {:error, :disabled}
    end
  end

  @doc "Whether this run may write to the user's clipboard."
  @spec enabled?() :: boolean()
  def enabled?, do: direction_enabled?(:copy)

  @doc """
  Whether pasted text is delivered to this run at all.

  When false, a bracketed paste is dropped before any widget or app sees it. Set
  independently of `enabled?/0` via `config :drafter, clipboard: [paste: false]`.
  """
  @spec paste_enabled?() :: boolean()
  def paste_enabled?, do: direction_enabled?(:paste)

  @doc """
  The key bound to `action`, as `{key, modifiers}`, or `nil` if unbound.

  Actions are `:copy`, `:cut`, `:paste` and `:select_all`, bound by default to
  `ctrl+c`, `ctrl+x`, `ctrl+v` and `ctrl+a`. Override them per run with
  `config :drafter, clipboard_keys: [copy: {:y, [:ctrl]}]`, or unbind an action by
  giving it `false`.

  These bindings are not installed framework-wide: a widget must call this function
  (or `key?/3`) to act on them, so a widget that wants `ctrl+c` for something else
  simply does not ask.
  """
  @spec key(atom()) :: {term(), [atom()]} | nil
  def key(action) do
    configured = Application.get_env(:drafter, :clipboard_keys, [])

    case Keyword.get(configured, action, Keyword.get(default_keys(), action)) do
      false -> nil
      nil -> nil
      binding -> binding
    end
  end

  @doc "Whether `key` and `mods` are the binding for `action`."
  @spec key?(atom(), term(), [atom()]) :: boolean()
  def key?(action, key, mods) do
    case key(action) do
      nil -> false
      {bound_key, bound_mods} -> bound_key == key and Enum.sort(bound_mods) == Enum.sort(mods)
    end
  end

  @doc "The bindings used when `:clipboard_keys` says nothing."
  @spec default_keys() :: keyword()
  def default_keys do
    [copy: {:c, [:ctrl]}, cut: {:x, [:ctrl]}, paste: {:v, [:ctrl]}, select_all: {:a, [:ctrl]}]
  end

  defp direction_enabled?(direction) do
    case Application.get_env(:drafter, :clipboard, true) do
      false -> false
      true -> true
      opts when is_list(opts) -> Keyword.get(opts, direction, true) != false
      _other -> true
    end
  end

  @doc """
  The OSC 52 sequence that puts `text` on `target`.

  Exposed for callers that manage their own terminal output.
  """
  @spec osc52(String.t(), target()) :: binary()
  def osc52(text, target \\ :clipboard) do
    "\e]52;#{selection(target)};#{Base.encode64(text)}\a"
  end

  @doc """
  Strip control characters from a pasted string.

  Carriage returns and CRLF pairs become newlines. Newlines and tabs survive;
  every other codepoint below `0x20`, and `DEL` (`0x7F`), is removed. Call this on
  any text taken from a paste before acting on it, so that escape sequences the
  text carries cannot be interpreted as keystrokes.
  """
  @spec sanitize(String.t()) :: String.t()
  def sanitize(text) when is_binary(text) do
    text
    |> String.replace(~r/\r\n?/, "\n")
    |> String.graphemes()
    |> Enum.reject(&control?/1)
    |> Enum.join()
  end

  defp control?(<<codepoint::utf8>>) when codepoint in [?\n, ?\t], do: false
  defp control?(<<codepoint::utf8>>), do: codepoint < 0x20 or codepoint == 0x7F
  defp control?(_grapheme), do: false

  defp selection(:primary), do: "p"
  defp selection(_target), do: "c"

  defp do_copy(text, target) do
    write_osc52(text, target)
    write_local(text)
    :ok
  end

  defp write_osc52(text, target) do
    Compositor.write_raw(osc52(text, target))
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp write_local(text) do
    case copy_command() do
      nil ->
        :ok

      {command, args} ->
        spawn(fn -> pipe_to(command, args, text) end)
        :ok
    end
  end

  defp read_local do
    case paste_command() do
      nil ->
        {:error, :unavailable}

      {command, args} ->
        case System.cmd(command, args, stderr_to_stdout: false) do
          {output, 0} -> {:ok, output}
          _ -> {:error, :unavailable}
        end
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp pipe_to(command, args, text) do
    port = Port.open({:spawn_executable, command}, [:binary, :use_stdio, args: args])

    Port.command(port, text)
    Port.close(port)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp copy_command, do: find_command(copy_candidates())
  defp paste_command, do: find_command(paste_candidates())

  defp copy_candidates do
    case :os.type() do
      {:unix, :darwin} ->
        [{"pbcopy", []}]

      {:win32, _} ->
        [{"clip", []}]

      _ ->
        [
          {"wl-copy", []},
          {"xclip", ["-selection", "clipboard"]},
          {"xsel", ["--clipboard", "--input"]}
        ]
    end
  end

  defp paste_candidates do
    case :os.type() do
      {:unix, :darwin} ->
        [{"pbpaste", []}]

      {:win32, _} ->
        [{"powershell", ["-NoProfile", "-Command", "Get-Clipboard"]}]

      _ ->
        [
          {"wl-paste", ["--no-newline"]},
          {"xclip", ["-selection", "clipboard", "-o"]},
          {"xsel", ["--clipboard", "--output"]}
        ]
    end
  end

  defp find_command(candidates) do
    Enum.find_value(candidates, fn {name, args} ->
      case System.find_executable(name) do
        nil -> nil
        path -> {path, args}
      end
    end)
  end
end
