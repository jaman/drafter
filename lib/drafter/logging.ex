defmodule Drafter.Logging do
  @moduledoc false

  require Logger

  @doc "Set up logging to a file in the system temp dir (or provided path)."
  @spec setup(keyword()) :: :ok | {:error, term()}
  def setup(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    path = Keyword.get(opts, :path, default_log_path())

    _ = :logger.remove_handler(:default)

    handler_id = :tui_file_logger
    file_charlist = String.to_charlist(path)

    _ = :logger.remove_handler(handler_id)

    formatter =
      {:logger_formatter,
       %{
         template: [:time, " [", :level, "] ", :msg, "\n"]
       }}

    config = %{
      formatter: formatter,
      level: level,
      filter_default: :log,
      filters: [],
      config: %{type: :file, file: file_charlist}
    }

    case :logger.add_handler(handler_id, :logger_std_h, config) do
      :ok ->
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp default_log_path do
    Path.join(File.cwd!(), "drafter.log")
  end
end
