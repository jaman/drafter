defmodule Drafter.Terminal.ANSI do
  @moduledoc false

  @type key :: atom()
  @type modifiers :: [atom()]
  @type event :: {:key, key()} | {:key, key(), modifiers()} | {:mouse, map()} | :unknown

  @key_sequences %{
    "\e[A" => {:key, :up},
    "\e[B" => {:key, :down},
    "\e[C" => {:key, :right},
    "\e[D" => {:key, :left},
    "\e[1;2A" => {:key, :up, [:shift]},
    "\e[1;2B" => {:key, :down, [:shift]},
    "\e[1;2C" => {:key, :right, [:shift]},
    "\e[1;2D" => {:key, :left, [:shift]},
    "\e[1;3A" => {:key, :up, [:alt]},
    "\e[1;3B" => {:key, :down, [:alt]},
    "\e[1;3C" => {:key, :right, [:alt]},
    "\e[1;3D" => {:key, :left, [:alt]},
    "\e[1;5A" => {:key, :up, [:ctrl]},
    "\e[1;5B" => {:key, :down, [:ctrl]},
    "\e[1;5C" => {:key, :right, [:ctrl]},
    "\e[1;5D" => {:key, :left, [:ctrl]},
    "\eOP" => {:key, :f1},
    "\eOQ" => {:key, :f2},
    "\eOR" => {:key, :f3},
    "\eOS" => {:key, :f4},
    "\e[15~" => {:key, :f5},
    "\e[17~" => {:key, :f6},
    "\e[18~" => {:key, :f7},
    "\e[19~" => {:key, :f8},
    "\e[20~" => {:key, :f9},
    "\e[21~" => {:key, :f10},
    "\e[23~" => {:key, :f11},
    "\e[24~" => {:key, :f12},
    "\e[H" => {:key, :home},
    "\e[F" => {:key, :end},
    "\e[2~" => {:key, :insert},
    "\e[3~" => {:key, :delete},
    "\e[5~" => {:key, :page_up},
    "\e[6~" => {:key, :page_down},
    "\e[Z" => {:key, :tab, [:shift]},
    "\e" => {:key, :escape},
    "\x01" => {:key, :a, [:ctrl]},
    "\x02" => {:key, :b, [:ctrl]},
    "\x03" => {:key, :c, [:ctrl]},
    "\x04" => {:key, :d, [:ctrl]},
    "\x05" => {:key, :e, [:ctrl]},
    "\x06" => {:key, :f, [:ctrl]},
    "\x07" => {:key, :g, [:ctrl]},
    "\x08" => {:key, :h, [:ctrl]},
    #    "\x08" => {:key, :backspace},
    "\x09" => {:key, :tab},
    "\x0a" => {:key, :enter},
    "\x0b" => {:key, :k, [:ctrl]},
    "\x0c" => {:key, :l, [:ctrl]},
    "\x0d" => {:key, :enter},
    "\x0e" => {:key, :n, [:ctrl]},
    "\x0f" => {:key, :o, [:ctrl]},
    "\x10" => {:key, :p, [:ctrl]},
    "\x11" => {:key, :q, [:ctrl]},
    "\x12" => {:key, :r, [:ctrl]},
    "\x13" => {:key, :s, [:ctrl]},
    "\x14" => {:key, :t, [:ctrl]},
    "\x15" => {:key, :u, [:ctrl]},
    "\x16" => {:key, :v, [:ctrl]},
    "\x17" => {:key, :w, [:ctrl]},
    "\x18" => {:key, :x, [:ctrl]},
    "\x19" => {:key, :y, [:ctrl]},
    "\x1a" => {:key, :z, [:ctrl]},
    "\x7f" => {:key, :backspace}
  }

  @doc "Parse input buffer into events and remaining buffer."
  @spec parse_sequence(binary()) :: {[event()], binary()}
  def parse_sequence(buffer) do
    parse_sequence(buffer, [])
  end

  defp parse_sequence("", events), do: {Enum.reverse(events), ""}

  defp parse_sequence(buffer, events) do
    case find_longest_match(buffer) do
      {:ignore, rest} ->
        parse_sequence(rest, events)

      {event, rest} ->
        parse_sequence(rest, [event | events])

      :no_match ->
        case buffer do
          <<char::utf8, rest::binary>> when char >= 32 and char <= 126 ->
            key_atom = String.to_atom(<<char::utf8>>)
            event = {:key, key_atom}
            parse_sequence(rest, [event | events])

          <<_char::utf8, rest::binary>> ->
            parse_sequence(rest, events)

          incomplete ->
            {Enum.reverse(events), incomplete}
        end
    end
  end

  defp find_longest_match(buffer) do
    case parse_mouse_event(buffer) do
      {mouse_event, rest} ->
        {mouse_event, rest}

      :no_match ->
        @key_sequences
        |> Enum.filter(fn {seq, _event} -> String.starts_with?(buffer, seq) end)
        |> Enum.max_by(fn {seq, _event} -> String.length(seq) end, fn -> nil end)
        |> case do
          {seq, event} ->
            rest = String.slice(buffer, String.length(seq)..-1//1)
            {event, rest}

          nil ->
            :no_match
        end
    end
  end

  defp parse_mouse_event(buffer) do
    case Regex.run(~r/^\e\[<(\d+);(\d+);(\d+)([Mm])/, buffer) do
      [full_match, button_str, x_str, y_str, action_char] ->
        parse_sgr_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char)

      nil ->
        case Regex.run(~r/^\e\[<(\d+);(\d+);(\d+)H/, buffer) do
          [full_match, button_str, x_str, y_str] ->
            parse_sgr_mouse_event(buffer, full_match, button_str, x_str, y_str, "M")

          nil ->
            case parse_x10_mouse_event(buffer) do
              {event, rest} ->
                {event, rest}

              :no_match ->
                case Regex.run(~r/^\e\[(\d+);(\d+);(\d+)([Mm])/, buffer) do
                  [full_match, button_str, x_str, y_str, action_char] ->
                    parse_legacy_mouse_event(
                      buffer,
                      full_match,
                      button_str,
                      x_str,
                      y_str,
                      action_char
                    )

                  nil ->
                    :no_match
                end
            end
        end
    end
  end

  defp parse_x10_mouse_event(buffer) do
    case Regex.run(~r/^\e\[M(.)(.)(.)/s, buffer) do
      [full_match, <<button_byte>>, <<x_byte>>, <<y_byte>>] ->
        button = button_byte - 32
        x = x_byte - 33
        y = y_byte - 33

        base = Bitwise.band(button, 0x03)
        motion = Bitwise.band(button, 0x20) != 0

        {type, extra} =
          cond do
            button >= 64 and button <= 67 ->
              direction =
                case button do
                  64 -> :up
                  65 -> :down
                  66 -> :right
                  67 -> :left
                end

              {:scroll, direction}

            motion and base == 3 ->
              {:move, nil}

            motion ->
              {:drag, nil}

            true ->
              {:mouse_down, nil}
          end

        mouse_event =
          case type do
            :scroll ->
              {:mouse,
               %{
                 type: :scroll,
                 direction: extra,
                 x: x,
                 y: y,
                 modifiers: parse_mouse_modifiers(button)
               }}

            :move ->
              {:mouse,
               %{
                 type: :move,
                 x: x,
                 y: y,
                 modifiers: parse_mouse_modifiers(button)
               }}

            _ ->
              {:mouse,
               %{
                 type: type,
                 button: parse_mouse_button(button),
                 x: x,
                 y: y,
                 modifiers: parse_mouse_modifiers(button)
               }}
          end

        rest = String.slice(buffer, String.length(full_match)..-1//1)
        {mouse_event, rest}

      _ ->
        :no_match
    end
  end

  defp parse_sgr_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char) do
    button = String.to_integer(button_str)
    x = String.to_integer(x_str) - 1
    y = String.to_integer(y_str) - 1

    base = Bitwise.band(button, 0x03)
    motion = Bitwise.band(button, 0x20) != 0

    {type, extra} =
      cond do
        button >= 64 and button <= 67 ->
          direction =
            case button do
              64 -> :up
              65 -> :down
              66 -> :right
              67 -> :left
            end

          {:scroll, direction}

        action_char == "m" ->
          {:mouse_up, nil}

        action_char == "M" and motion and base == 3 ->
          {:move, nil}

        action_char == "M" and motion ->
          {:drag, nil}

        action_char == "M" ->
          {:mouse_down, nil}

        true ->
          {:mouse_down, nil}
      end

    mouse_payload =
      case type do
        :scroll ->
          %{
            type: :scroll,
            direction: extra,
            x: x,
            y: y,
            modifiers: parse_mouse_modifiers(button)
          }

        :move ->
          %{
            type: :move,
            x: x,
            y: y,
            modifiers: parse_mouse_modifiers(button)
          }

        _ ->
          %{
            type: type,
            button: parse_mouse_button(button),
            x: x,
            y: y,
            modifiers: parse_mouse_modifiers(button)
          }
      end

    mouse_event = {:mouse, mouse_payload}
    rest = String.slice(buffer, String.length(full_match)..-1//1)
    {mouse_event, rest}
  end

  defp parse_legacy_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char) do
    button = String.to_integer(button_str)
    x = String.to_integer(x_str) - 1
    y = String.to_integer(y_str) - 1

    base = Bitwise.band(button, 0x03)
    motion = Bitwise.band(button, 0x20) != 0

    {type, extra} =
      cond do
        button >= 64 and button <= 67 ->
          direction =
            case button do
              64 -> :up
              65 -> :down
              66 -> :right
              67 -> :left
            end

          {:scroll, direction}

        action_char == "m" ->
          {:mouse_up, nil}

        action_char == "M" and motion and base == 3 ->
          {:move, nil}

        action_char == "M" and motion ->
          {:drag, nil}

        action_char == "M" and base == 3 ->
          {:mouse_up, nil}

        action_char == "M" ->
          {:mouse_down, nil}

        true ->
          {:mouse_down, nil}
      end

    mouse_event =
      case type do
        :scroll ->
          {:mouse,
           %{
             type: :scroll,
             direction: extra,
             x: x,
             y: y,
             modifiers: parse_mouse_modifiers(button)
           }}

        :move ->
          {:mouse,
           %{
             type: :move,
             x: x,
             y: y,
             modifiers: parse_mouse_modifiers(button)
           }}

        _ ->
          {:mouse,
           %{
             type: type,
             button: parse_mouse_button(button),
             x: x,
             y: y,
             modifiers: parse_mouse_modifiers(button)
           }}
      end

    rest = String.slice(buffer, String.length(full_match)..-1//1)
    {mouse_event, rest}
  end

  defp parse_mouse_button(button) do
    cond do
      button >= 64 and button <= 67 ->
        :scroll

      true ->
        case Bitwise.band(button, 0x03) do
          0 -> :left
          1 -> :middle
          2 -> :right
          _ -> :unknown
        end
    end
  end

  defp parse_mouse_modifiers(button) do
    modifiers = []
    modifiers = if Bitwise.band(button, 0x04) != 0, do: [:shift | modifiers], else: modifiers
    modifiers = if Bitwise.band(button, 0x08) != 0, do: [:alt | modifiers], else: modifiers
    modifiers = if Bitwise.band(button, 0x10) != 0, do: [:ctrl | modifiers], else: modifiers
    modifiers
  end

  @doc "Move cursor to specific position (1-indexed)"
  @spec cursor_to(non_neg_integer(), non_neg_integer()) :: String.t()
  def cursor_to(x, y), do: "\e[#{y};#{x}H"

  @doc "Clear entire screen"
  @spec clear_screen() :: String.t()
  def clear_screen(), do: "\e[2J"

  @doc "Clear from cursor to end of screen"
  @spec clear_to_end() :: String.t()
  def clear_to_end(), do: "\e[0J"

  @doc "Clear current line"
  @spec clear_line() :: String.t()
  def clear_line(), do: "\e[2K"

  @doc "Hide cursor"
  @spec hide_cursor() :: String.t()
  def hide_cursor(), do: "\e[?25l"

  @doc "Show cursor"
  @spec show_cursor() :: String.t()
  def show_cursor(), do: "\e[?25h"

  @doc "Enable mouse reporting"
  @spec enable_mouse() :: String.t()
  def enable_mouse() do
    "\e[?1002h\e[?1006h"
  end

  @doc "Disable mouse reporting"
  @spec disable_mouse() :: String.t()
  def disable_mouse() do
    "\e[?1006l\e[?1002l"
  end

  @doc "Enter alternative screen buffer"
  @spec enter_alt_screen() :: String.t()
  def enter_alt_screen(), do: "\e[?1049h"

  @doc "Exit alternative screen buffer"
  @spec exit_alt_screen() :: String.t()
  def exit_alt_screen(), do: "\e[?1049l"

  @doc "Enable synchronized rendering"
  @spec sync_start() :: String.t()
  def sync_start(), do: "\e[?2026h"

  @doc "Disable synchronized rendering"
  @spec sync_end() :: String.t()
  def sync_end(), do: "\e[?2026l"

  @doc "Set foreground color (RGB)"
  @spec fg_color(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def fg_color(r, g, b), do: "\e[38;2;#{r};#{g};#{b}m"

  @doc "Set background color (RGB)"
  @spec bg_color(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def bg_color(r, g, b), do: "\e[48;2;#{r};#{g};#{b}m"

  @doc "Reset all formatting"
  @spec reset() :: String.t()
  def reset(), do: "\e[0m"

  @doc "Bold text"
  @spec bold() :: String.t()
  def bold(), do: "\e[1m"

  @doc "Dim text"
  @spec dim() :: String.t()
  def dim(), do: "\e[2m"

  @doc "Italic text"
  @spec italic() :: String.t()
  def italic(), do: "\e[3m"

  @doc "Underline text"
  @spec underline() :: String.t()
  def underline(), do: "\e[4m"

  @doc "Reverse video (swap fg/bg colors)"
  @spec reverse() :: String.t()
  def reverse(), do: "\e[7m"
end
