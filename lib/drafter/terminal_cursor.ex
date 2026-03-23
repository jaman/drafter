defmodule Drafter.TerminalCursor do
  @moduledoc false

  @doc """
  Available cursor styles (limited terminal support):
  - :default - Normal cursor
  - :invisible - Hide cursor
  - :block - Block cursor (if supported)
  - :underline - Underline cursor (if supported)
  - :bar - Bar/vertical line cursor (if supported)
  """

  def set_cursor_style(:invisible) do
    IO.write("\e[?25l")  # Hide cursor
  end

  def set_cursor_style(:visible) do
    IO.write("\e[?25h")  # Show cursor
  end

  def set_cursor_style(:block) do
    IO.write("\e[2 q")   # Block cursor (limited support)
  end

  def set_cursor_style(:underline) do
    IO.write("\e[4 q")   # Underline cursor (limited support)
  end

  def set_cursor_style(:bar) do
    IO.write("\e[6 q")   # Bar cursor (limited support)
  end

  def set_cursor_style(:default) do
    IO.write("\e[0 q")   # Default cursor
  end

  @doc """
  Move cursor to specific position (0-based coordinates)
  """
  def move_cursor(x, y) do
    IO.write("\e[#{y + 1};#{x + 1}H")
  end

  @doc """
  Some terminals support limited mouse cursor changes, but this is very rare
  and not widely supported. Most TUI applications cannot change mouse cursor.
  """
  def change_mouse_cursor(_cursor_type) do
    # This is generally not supported in terminal applications
    # GUI applications use window system APIs for this
    :not_supported
  end
end
