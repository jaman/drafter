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
end
