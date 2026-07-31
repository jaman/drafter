defmodule Drafter.Terminal.ANSI do
  @moduledoc false

  @type key :: atom()
  @type modifiers :: [atom()]
  @type event :: {:key, key()} | {:key, key(), modifiers()} | {:mouse, map()} | :unknown

  # A reply the terminal sends back — a kitty graphics acknowledgement, an answer to an OSC
  # query — opens one of these and runs to a string terminator. Undecoded it reaches the
  # application as whatever it happens to spell: `\e_Gi=1;OK\e\\` arrives as ten keystrokes.
  @string_openers ~c"_P]X^"

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

  @doc """
  Parse an input buffer into events plus the bytes that could not yet be decided.

  A trailing sequence that is only partially received — an unterminated
  bracketed paste, a CSI awaiting its final byte, a split UTF-8 codepoint — is
  returned in the remaining buffer. Callers must carry that remainder into the
  next call.
  """
  @spec parse_sequence(binary()) :: {[event()], binary()}
  def parse_sequence(buffer), do: do_parse(buffer, [], :partial)

  @doc """
  Parse an input buffer, resolving any trailing ambiguity instead of retaining it.

  Call this when no further bytes are expected — after an escape timeout, or when
  the input stream closes. A lone `ESC` becomes the escape key, and an
  unterminated bracketed paste is delivered with the content received so far.
  """
  @spec flush_sequence(binary()) :: {[event()], binary()}
  def flush_sequence(buffer), do: do_parse(buffer, [], :flush)

  defp do_parse("", events, _mode), do: {Enum.reverse(events), ""}

  defp do_parse(buffer, events, mode) do
    case parse_bracketed_paste(buffer) do
      {:bracketed_paste, content, rest} ->
        do_parse(rest, [{:bracketed_paste, content} | events], mode)

      {:incomplete, partial} ->
        resolve_incomplete_paste(buffer, partial, events, mode)

      :no_match ->
        parse_sequence_match(buffer, events, mode)
    end
  end

  defp resolve_incomplete_paste(buffer, _partial, events, :partial) do
    {Enum.reverse(events), buffer}
  end

  defp resolve_incomplete_paste(_buffer, partial, events, :flush) do
    {Enum.reverse([{:bracketed_paste, partial} | events]), ""}
  end

  defp parse_sequence_match(buffer, events, mode) do
    if mode == :partial and incomplete_sequence?(buffer) do
      {Enum.reverse(events), buffer}
    else
      case find_longest_match(buffer) do
        {:ignore, rest} -> do_parse(rest, events, mode)
        {event, rest} -> do_parse(rest, [event | events], mode)
        :no_match -> parse_sequence_char(buffer, events, mode)
      end
    end
  end

  @doc """
  Whether the buffer ends in a control sequence that has not fully arrived.

  A lone `ESC` counts as incomplete: it is indistinguishable from the start of a
  sequence still in flight, so the caller must resolve it on a timeout via
  `flush_sequence/1`.
  """
  @spec incomplete_sequence?(binary()) :: boolean()
  def incomplete_sequence?("\e"), do: true
  def incomplete_sequence?(<<"\e[", rest::binary>>), do: csi_unterminated?(rest)
  def incomplete_sequence?("\eO"), do: true

  def incomplete_sequence?(<<"\e", opener, rest::binary>>) when opener in @string_openers,
    do: string_terminator(rest) == :none

  def incomplete_sequence?(_buffer), do: false

  defp csi_unterminated?(<<>>), do: true

  defp csi_unterminated?(<<byte, rest::binary>>) when byte >= 0x20 and byte <= 0x3F do
    csi_unterminated?(rest)
  end

  defp csi_unterminated?(_rest), do: false

  defp parse_sequence_char(<<char::utf8, rest::binary>>, events, mode)
       when char >= 32 and char <= 126 do
    do_parse(rest, [{:key, printable_key(char)} | events], mode)
  end

  defp parse_sequence_char(<<char::utf8, rest::binary>>, events, mode) do
    do_parse(rest, [{:char, char} | events], mode)
  end

  defp parse_sequence_char(incomplete, events, _mode) do
    {Enum.reverse(events), incomplete}
  end

  for char <- 32..126 do
    key = String.to_atom(<<char::utf8>>)
    defp printable_key(unquote(char)), do: unquote(key)
  end

  @paste_start "\e[200~"
  @paste_end "\e[201~"

  defp parse_bracketed_paste(<<@paste_start, after_start::binary>>) do
    case :binary.match(after_start, @paste_end) do
      {pos, _len} ->
        content = binary_part(after_start, 0, pos)
        tail_start = pos + byte_size(@paste_end)
        rest = binary_part(after_start, tail_start, byte_size(after_start) - tail_start)
        {:bracketed_paste, content, rest}

      :nomatch ->
        {:incomplete, after_start}
    end
  end

  defp parse_bracketed_paste(_buffer), do: :no_match

  defp find_longest_match(buffer) do
    case parse_mouse_event(buffer) do
      {mouse_event, rest} -> {mouse_event, rest}
      :no_match -> parse_string_sequence(buffer) || match_key_sequence(buffer)
    end
  end

  defp parse_string_sequence(<<"\e", opener, rest::binary>>) when opener in @string_openers do
    case string_terminator(rest) do
      {:ok, remainder} -> {:ignore, remainder}
      :none -> nil
    end
  end

  defp parse_string_sequence(_buffer), do: nil

  # ST ends any of them; OSC is also allowed to end at BEL.
  defp string_terminator(binary) do
    case :binary.match(binary, ["\e\\", "\a"]) do
      {index, length} ->
        start = index + length
        {:ok, binary_part(binary, start, byte_size(binary) - start)}

      :nomatch ->
        :none
    end
  end

  for {sequence, event} <-
        Enum.sort_by(@key_sequences, fn {seq, _} -> byte_size(seq) end, :desc) do
    defp match_key_sequence(unquote(sequence) <> rest) do
      {unquote(Macro.escape(event)), rest}
    end
  end

  defp match_key_sequence(_buffer), do: :no_match

  defp parse_mouse_event(buffer) do
    parse_mouse_sgr(buffer) ||
      parse_mouse_sgr_h(buffer) ||
      parse_x10_mouse_event_opt(buffer) ||
      parse_mouse_legacy(buffer) ||
      :no_match
  end

  defp parse_x10_mouse_event_opt(buffer) do
    case parse_x10_mouse_event(buffer) do
      :no_match -> nil
      result -> result
    end
  end

  defp parse_mouse_sgr(buffer) do
    case Regex.run(~r/^\e\[<(\d+);(\d+);(\d+)([Mm])/, buffer) do
      [full_match, button_str, x_str, y_str, action_char] ->
        parse_sgr_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char)

      nil ->
        nil
    end
  end

  defp parse_mouse_sgr_h(buffer) do
    case Regex.run(~r/^\e\[<(\d+);(\d+);(\d+)H/, buffer) do
      [full_match, button_str, x_str, y_str] ->
        parse_sgr_mouse_event(buffer, full_match, button_str, x_str, y_str, "M")

      nil ->
        nil
    end
  end

  defp parse_mouse_legacy(buffer) do
    case Regex.run(~r/^\e\[(\d+);(\d+);(\d+)([Mm])/, buffer) do
      [full_match, button_str, x_str, y_str, action_char] ->
        parse_legacy_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char)

      nil ->
        nil
    end
  end

  defp parse_x10_mouse_event(buffer) do
    case Regex.run(~r/^\e\[M(.)(.)(.)/s, buffer) do
      [full_match, <<button_byte>>, <<x_byte>>, <<y_byte>>] ->
        button = button_byte - 32
        x = x_byte - 33
        y = y_byte - 33
        {type, extra} = classify_mouse_action(button, "M", :x10)
        build_mouse_result(buffer, full_match, button, x, y, type, extra)

      _ ->
        :no_match
    end
  end

  defp parse_sgr_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char) do
    button = String.to_integer(button_str)
    x = String.to_integer(x_str) - 1
    y = String.to_integer(y_str) - 1
    {type, extra} = classify_mouse_action(button, action_char, :sgr)
    build_mouse_result(buffer, full_match, button, x, y, type, extra)
  end

  defp parse_legacy_mouse_event(buffer, full_match, button_str, x_str, y_str, action_char) do
    button = String.to_integer(button_str)
    x = String.to_integer(x_str) - 1
    y = String.to_integer(y_str) - 1
    {type, extra} = classify_mouse_action(button, action_char, :legacy)
    build_mouse_result(buffer, full_match, button, x, y, type, extra)
  end

  defp classify_mouse_action(button, "m", _format) when button >= 64 and button <= 67,
    do: {:ignore, nil}

  defp classify_mouse_action(button, _action_char, _format) when button >= 64 and button <= 67,
    do: {:scroll, scroll_direction(button)}

  defp classify_mouse_action(_button, "m", _format), do: {:mouse_up, nil}

  defp classify_mouse_action(button, _action_char, :legacy) do
    base = Bitwise.band(button, 0x03)
    if base == 3, do: {:mouse_up, nil}, else: {:mouse_down, nil}
  end

  defp classify_mouse_action(button, _action_char, _format) do
    base = Bitwise.band(button, 0x03)
    motion = Bitwise.band(button, 0x20) != 0
    classify_motion(motion, base)
  end

  defp classify_motion(true, 3), do: {:move, nil}
  defp classify_motion(true, _base), do: {:drag, nil}
  defp classify_motion(false, _base), do: {:mouse_down, nil}

  defp scroll_direction(64), do: :up
  defp scroll_direction(65), do: :down
  defp scroll_direction(66), do: :right
  defp scroll_direction(67), do: :left

  defp build_mouse_result(buffer, full_match, _button, _x, _y, :ignore, _extra) do
    {:ignore, String.slice(buffer, String.length(full_match)..-1//1)}
  end

  defp build_mouse_result(buffer, full_match, button, x, y, type, extra) do
    payload = build_mouse_payload(button, x, y, type, extra)
    rest = String.slice(buffer, String.length(full_match)..-1//1)
    {{:mouse, payload}, rest}
  end

  defp build_mouse_payload(button, x, y, :scroll, direction) do
    %{type: :scroll, direction: direction, x: x, y: y, modifiers: parse_mouse_modifiers(button)}
  end

  defp build_mouse_payload(button, x, y, :move, _extra) do
    %{type: :move, x: x, y: y, modifiers: parse_mouse_modifiers(button)}
  end

  defp build_mouse_payload(button, x, y, type, _extra) do
    %{
      type: type,
      button: parse_mouse_button(button),
      x: x,
      y: y,
      modifiers: parse_mouse_modifiers(button)
    }
  end

  defp parse_mouse_button(button) when button >= 64 and button <= 67, do: :scroll

  defp parse_mouse_button(button) do
    case Bitwise.band(button, 0x03) do
      0 -> :left
      1 -> :middle
      2 -> :right
      _ -> :unknown
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
  def clear_screen, do: "\e[2J"

  @doc "Clear from cursor to end of screen"
  @spec clear_to_end() :: String.t()
  def clear_to_end, do: "\e[0J"

  @doc "Clear current line"
  @spec clear_line() :: String.t()
  def clear_line, do: "\e[2K"

  @doc "Hide cursor"
  @spec hide_cursor() :: String.t()
  def hide_cursor, do: "\e[?25l"

  @doc "Show cursor"
  @spec show_cursor() :: String.t()
  def show_cursor, do: "\e[?25h"

  @spec enable_mouse(keyword()) :: String.t()
  def enable_mouse(opts \\ []) do
    if Keyword.get(opts, :hover, true) do
      "\e[?1003h\e[?1006h"
    else
      "\e[?1002h\e[?1006h"
    end
  end

  @spec disable_mouse(keyword()) :: String.t()
  def disable_mouse(opts \\ []) do
    if Keyword.get(opts, :hover, true) do
      "\e[?1006l\e[?1003l"
    else
      "\e[?1006l\e[?1002l"
    end
  end

  @doc "Enter alternative screen buffer"
  @spec enter_alt_screen() :: String.t()
  def enter_alt_screen, do: "\e[?1049h"

  @doc "Exit alternative screen buffer"
  @spec exit_alt_screen() :: String.t()
  def exit_alt_screen, do: "\e[?1049l"

  @doc "Enable synchronized rendering"
  @spec sync_start() :: String.t()
  def sync_start, do: "\e[?2026h"

  @doc "Disable synchronized rendering"
  @spec sync_end() :: String.t()
  def sync_end, do: "\e[?2026l"

  @doc "Set foreground color (RGB)"
  @spec fg_color(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def fg_color(r, g, b), do: "\e[38;2;#{r};#{g};#{b}m"

  @doc "Set background color (RGB)"
  @spec bg_color(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def bg_color(r, g, b), do: "\e[48;2;#{r};#{g};#{b}m"

  @doc "Reset all formatting"
  @spec reset() :: String.t()
  def reset, do: "\e[0m"

  @doc "Bold text"
  @spec bold() :: String.t()
  def bold, do: "\e[1m"

  @doc "Dim text"
  @spec dim() :: String.t()
  def dim, do: "\e[2m"

  @doc "Italic text"
  @spec italic() :: String.t()
  def italic, do: "\e[3m"

  @doc "Underline text"
  @spec underline() :: String.t()
  def underline, do: "\e[4m"

  @doc "Reverse video (swap fg/bg colors)"
  @spec reverse() :: String.t()
  def reverse, do: "\e[7m"
end
