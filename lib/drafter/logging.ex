defmodule Drafter.Logging do
  @moduledoc false

  require Logger

  @doc """
  Configure logging for a TUI run.

  Removes the console (`:default`) handler so `Logger` output cannot paint over the
  rendered TUI. No log file is written unless `:log` asks for one.

  Options:
    * `:log` — `false` (default) silences the console only; `true` writes to
      `drafter.log` in the current directory; a string path writes to that path.
    * `:level` — log level for the file handler when one is enabled (default `:debug`).
  """
  @spec setup(keyword()) :: :ok
  def setup(opts \\ []) do
    case plan(opts) do
      :silence -> silence_console()
      {:file, path, level} -> file_logging(path, level)
    end
  end

  @doc false
  @spec plan(keyword()) :: :silence | {:file, String.t(), atom()}
  def plan(opts) do
    case Keyword.get(opts, :log, false) do
      false -> :silence
      true -> {:file, default_log_path(), Keyword.get(opts, :level, :debug)}
      path when is_binary(path) -> {:file, path, Keyword.get(opts, :level, :debug)}
      _ -> :silence
    end
  end

  defp silence_console do
    _ = :logger.remove_handler(:default)
    :ok
  end

  defp file_logging(path, level) do
    silence_console()

    handler_id = :tui_file_logger
    _ = :logger.remove_handler(handler_id)

    config = %{
      formatter: {:logger_formatter, %{template: [:time, " [", :level, "] ", :msg, "\n"]}},
      level: level,
      filter_default: :log,
      filters: [],
      config: %{type: :file, file: String.to_charlist(path)}
    }

    _ = :logger.add_handler(handler_id, :logger_std_h, config)
    :ok
  end

  defp default_log_path do
    Path.join(File.cwd!(), "drafter.log")
  end
end
