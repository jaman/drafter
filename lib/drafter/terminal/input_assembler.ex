defmodule Drafter.Terminal.InputAssembler do
  @moduledoc """
  Assembles raw stdin bytes into complete terminal input units before they
  reach the driver's parser.

  A minimal pump process blocks on byte-at-a-time stdin reads and forwards
  each byte as a message; the assembler runs a `receive`-based state machine,
  which is what makes real timeouts possible — a bare Escape flushes after
  #{50}ms instead of waiting for the next keypress, and a torn sequence can
  never wedge input.

  Complete units emitted to the driver as `{:stdin, chunk}`:

    * CSI sequences terminated by a final byte in `0x40..0x7E`
    * SS3 sequences (`\\eO` + one byte) — xterm-style F1–F4
    * SGR mouse reports (`\\e[<...M/m`) and X10 reports (`\\e[M` + 3 raw bytes)
    * Linux console function keys (`\\e[[` + one byte)
    * bracketed paste as a single `\\e[200~...\\e[201~` unit
    * everything else byte-by-byte (UTF-8 reassembly happens in the parser)

  Set `DRAFTER_INPUT_LOG=/path/to/file` to append a hex log of every emitted
  chunk for diagnosing terminal-specific input problems.
  """

  @escape_flush_ms 50
  @paste_flush_ms 2_000

  @spec start(pid(), keyword()) :: pid()
  def start(driver, opts \\ []) do
    pump? = Keyword.get(opts, :pump, true)

    spawn_link(fn ->
      assembler = self()
      if pump?, do: spawn_link(fn -> pump(assembler) end)
      loop(%{driver: driver, log: open_log()})
    end)
  end

  defp pump(assembler) do
    case IO.read(:stdio, 1) do
      :eof ->
        send(assembler, :input_eof)

      {:error, _reason} ->
        Process.sleep(10)
        pump(assembler)

      data when is_binary(data) ->
        send(assembler, {:byte, data})
        pump(assembler)
    end
  end

  defp loop(ctx) do
    receive do
      {:byte, "\e"} -> escape(ctx)
      {:byte, byte} -> emit_and_loop(ctx, byte)
      :input_eof -> :ok
    end
  end

  defp escape(ctx) do
    receive do
      {:byte, "["} -> csi_start(ctx)
      {:byte, "O"} -> ss3(ctx)
      {:byte, "\e"} -> emit(ctx, "\e") && escape(ctx)
      {:byte, byte} -> emit_and_loop(ctx, "\e" <> byte)
      :input_eof -> emit(ctx, "\e")
    after
      @escape_flush_ms -> emit_and_loop(ctx, "\e")
    end
  end

  defp ss3(ctx) do
    receive do
      {:byte, byte} -> emit_and_loop(ctx, "\eO" <> byte)
      :input_eof -> emit(ctx, "\eO")
    after
      @escape_flush_ms -> emit_and_loop(ctx, "\eO")
    end
  end

  defp csi_start(ctx) do
    receive do
      {:byte, "<"} -> sgr_mouse(ctx, "\e[<")
      {:byte, "["} -> linux_fkey(ctx)
      {:byte, "M"} -> x10_mouse(ctx, "\e[M", 3)
      {:byte, byte} -> csi(ctx, "\e[" <> byte, byte)
      :input_eof -> emit(ctx, "\e[")
    after
      @escape_flush_ms -> emit_and_loop(ctx, "\e[")
    end
  end

  defp csi(ctx, buffer, <<final>>) when final in 0x40..0x7E do
    finish_csi(ctx, buffer)
  end

  defp csi(ctx, buffer, _last) do
    receive do
      {:byte, byte} -> csi(ctx, buffer <> byte, byte)
      :input_eof -> emit(ctx, buffer)
    after
      @escape_flush_ms -> emit_and_loop(ctx, buffer)
    end
  end

  defp finish_csi(ctx, "\e[200~"), do: paste(ctx, "\e[200~")
  defp finish_csi(ctx, buffer), do: emit_and_loop(ctx, buffer)

  defp paste(ctx, buffer) do
    if String.ends_with?(buffer, "\e[201~") do
      emit_and_loop(ctx, buffer)
    else
      receive do
        {:byte, byte} -> paste(ctx, buffer <> byte)
        :input_eof -> emit(ctx, buffer)
      after
        @paste_flush_ms -> emit_and_loop(ctx, buffer)
      end
    end
  end

  defp linux_fkey(ctx) do
    receive do
      {:byte, byte} -> emit_and_loop(ctx, "\e[[" <> byte)
      :input_eof -> emit(ctx, "\e[[")
    after
      @escape_flush_ms -> emit_and_loop(ctx, "\e[[")
    end
  end

  defp sgr_mouse(ctx, buffer) do
    receive do
      {:byte, byte} when byte in ["M", "m"] -> emit_and_loop(ctx, buffer <> byte)
      {:byte, byte} -> sgr_mouse(ctx, buffer <> byte)
      :input_eof -> emit(ctx, buffer)
    after
      @escape_flush_ms -> emit_and_loop(ctx, buffer)
    end
  end

  defp x10_mouse(ctx, buffer, 0), do: emit_and_loop(ctx, buffer)

  defp x10_mouse(ctx, buffer, remaining) do
    receive do
      {:byte, byte} -> x10_mouse(ctx, buffer <> byte, remaining - 1)
      :input_eof -> emit(ctx, buffer)
    after
      @escape_flush_ms -> emit_and_loop(ctx, buffer)
    end
  end

  defp emit_and_loop(ctx, chunk) do
    emit(ctx, chunk)
    loop(ctx)
  end

  defp emit(ctx, chunk) do
    log_chunk(ctx.log, chunk)
    send(ctx.driver, {:stdin, chunk})
    true
  end

  defp open_log do
    case System.get_env("DRAFTER_INPUT_LOG") do
      empty when empty in [nil, ""] ->
        nil

      path ->
        case File.open(path, [:append, :utf8]) do
          {:ok, device} -> device
          {:error, _} -> nil
        end
    end
  end

  defp log_chunk(nil, _chunk), do: :ok

  defp log_chunk(device, chunk) do
    IO.write(device, [Base.encode16(chunk), " ", inspect(chunk), "\n"])
  rescue
    _ -> :ok
  end
end
