defmodule Drafter.Terminal.ANSI do
  @moduledoc """
  Decodes terminal input bytes into events and builds terminal output sequences.

  ## Input

  `parse_sequence/1` turns a byte buffer into a list of events plus the bytes that
  cannot yet be decided. `flush_sequence/1` does the same but resolves the trailing
  ambiguity instead of retaining it. `incomplete_sequence?/1` reports whether a
  buffer ends mid-sequence.

      iex> Drafter.Terminal.ANSI.parse_sequence("hi\\e[A\\e[")
      {[{:key, :h}, {:key, :i}, {:key, :up}], "\\e["}

  ## Event shapes

  Every event this module produces takes one of these forms:

    * `{:key, key}` — a named key (`:up`, `:enter`, `:f5`, `:backspace`, `:escape`)
      or, for printable ASCII 32..126, the character itself as an atom (`:a`, `:Z`,
      `:"1"`, `:" "`).
    * `{:key, key, modifiers}` — the same, with a non-empty modifier list. Modifiers
      are a subset of `[:ctrl, :alt, :shift]` and appear in that order.
    * `{:char, codepoint}` — a printable codepoint outside ASCII 32..126, as an
      integer.
    * `{:mouse, payload}` — see below.
    * `{:bracketed_paste, text}` — the content between `ESC [ 200~` and `ESC [ 201~`,
      undecoded and with the delimiters stripped.

  Control characters `\\x01`..`\\x1a` decode as `{:key, letter, [:ctrl]}`, except
  `\\x09` which is `{:key, :tab}` and `\\x0a`/`\\x0d` which are both `{:key, :enter}`.

  ## Mouse payloads

  `x` and `y` are zero-based column and row. `modifiers` is a subset of
  `[:ctrl, :alt, :shift]`.

    * `%{type: :mouse_down | :mouse_up | :drag, button: button, x: x, y: y, modifiers: mods}`
      where `button` is `:left`, `:middle`, `:right`, `:scroll` or `:unknown`
    * `%{type: :move, x: x, y: y, modifiers: mods}`
    * `%{type: :scroll, direction: :up | :down | :left | :right, x: x, y: y, modifiers: mods}`

  SGR (`ESC [ < …M/m`), legacy numeric and X10 (`ESC [ M` plus three bytes) encodings
  are all accepted. A final `H` in the SGR form is read as if it were `M`.

  ## Discarded input

  Terminals reply to queries with string-typed control sequences opened by
  `ESC P`, `ESC ]`, `ESC ^`, `ESC _` or `ESC X` and closed by a string terminator
  (`ESC \\`, or `BEL` for OSC). These are consumed and produce no event. A buffer
  ending inside one is treated as incomplete.

  The release report for a scroll button — buttons `64`..`67` with a final `m` —
  is consumed the same way, since the press already carried the scroll.

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[<64;1;1m")
      {[], ""}

  ## Output

  The remaining functions return the escape sequences for cursor placement, screen
  clearing, alternate screen, synchronized updates, mouse reporting and SGR styling.
  They only build strings; writing them is the caller's job.

      iex> Drafter.Terminal.ANSI.cursor_to(1, 1) <> Drafter.Terminal.ANSI.clear_screen()
      "\\e[1;1H\\e[2J"
  """

  @typedoc "A named key such as `:up` or `:f5`, or a printable ASCII character as an atom."
  @type key :: atom()

  @typedoc "Held modifiers, in the order `:ctrl`, `:alt`, `:shift`, and never empty in an event."
  @type modifiers :: [:ctrl | :alt | :shift]

  @typedoc """
  What a `{:mouse, payload}` event carries.

  `:button` is absent on `:move`, and `:direction` is present only on `:scroll`.
  """
  @type mouse_payload :: %{
          required(:type) => :mouse_down | :mouse_up | :drag | :move | :scroll,
          required(:x) => non_neg_integer(),
          required(:y) => non_neg_integer(),
          required(:modifiers) => modifiers(),
          optional(:button) => :left | :middle | :right | :scroll | :unknown,
          optional(:direction) => :up | :down | :left | :right
        }

  @typedoc "Everything `parse_sequence/1` and `flush_sequence/1` can produce."
  @type event ::
          {:key, key()}
          | {:key, key(), modifiers()}
          | {:char, char()}
          | {:mouse, mouse_payload()}
          | {:bracketed_paste, binary()}

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

  Printable ASCII arrives as `{:key, atom}`, and anything else printable as
  `{:char, codepoint}`:

      iex> Drafter.Terminal.ANSI.parse_sequence("A ")
      {[{:key, :A}, {:key, :" "}], ""}

      iex> Drafter.Terminal.ANSI.parse_sequence("é")
      {[{:char, 233}], ""}

  Named keys, control characters and modified keys:

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[A")
      {[{:key, :up}], ""}

      iex> Drafter.Terminal.ANSI.parse_sequence("\\x03")
      {[{:key, :c, [:ctrl]}], ""}

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[1;5C")
      {[{:key, :right, [:ctrl]}], ""}

  Mouse reports, in any of the three encodings, become a `{:mouse, payload}` pair
  with zero-based coordinates:

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[<0;10;5M")
      {[{:mouse, %{type: :mouse_down, button: :left, x: 9, y: 4, modifiers: []}}], ""}

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[<64;1;1M")
      {[{:mouse, %{type: :scroll, direction: :up, x: 0, y: 0, modifiers: []}}], ""}

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[<35;1;1M")
      {[{:mouse, %{type: :move, x: 0, y: 0, modifiers: []}}], ""}

  A bracketed paste is delivered whole, with its delimiters stripped:

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[200~two words\\e[201~")
      {[{:bracketed_paste, "two words"}], ""}

  Replies to terminal queries are consumed without producing an event:

      iex> Drafter.Terminal.ANSI.parse_sequence("\\eP1$r0m\\e\\\\x")
      {[{:key, :x}], ""}

  Whatever cannot yet be decided is handed back for the next call — an unterminated
  paste, a CSI without its final byte, and a split UTF-8 codepoint alike:

      iex> Drafter.Terminal.ANSI.parse_sequence("\\e[200~half")
      {[], "\\e[200~half"}

      iex> Drafter.Terminal.ANSI.parse_sequence("x\\e[")
      {[{:key, :x}], "\\e["}

      iex> Drafter.Terminal.ANSI.parse_sequence(<<0xC3>>)
      {[], <<0xC3>>}
  """
  @spec parse_sequence(binary()) :: {[event()], binary()}
  def parse_sequence(buffer), do: do_parse(buffer, [], :partial)

  @doc """
  Parse an input buffer, resolving any trailing ambiguity instead of retaining it.

  Call this when no further bytes are expected — after an escape timeout, or when
  the input stream closes. A lone `ESC` becomes the escape key, and an
  unterminated bracketed paste is delivered with the content received so far.

      iex> Drafter.Terminal.ANSI.flush_sequence("\\e")
      {[{:key, :escape}], ""}

      iex> Drafter.Terminal.ANSI.flush_sequence("\\e[200~half")
      {[{:bracketed_paste, "half"}], ""}

  A codepoint split across a read is the one thing still retained, since its
  remaining bytes carry no ambiguity to resolve:

      iex> Drafter.Terminal.ANSI.flush_sequence(<<0xC3>>)
      {[], <<0xC3>>}
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

      iex> Drafter.Terminal.ANSI.incomplete_sequence?("\\e")
      true

      iex> Drafter.Terminal.ANSI.incomplete_sequence?("\\e[1;5")
      true

      iex> Drafter.Terminal.ANSI.incomplete_sequence?("\\e[A")
      false

      iex> Drafter.Terminal.ANSI.incomplete_sequence?("ab")
      false

  An unterminated bracketed paste is not reported here: `ESC [ 200~` is a complete
  CSI sequence. `parse_sequence/1` holds the paste back on its own.

      iex> Drafter.Terminal.ANSI.incomplete_sequence?("\\e[200~half")
      false
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

  @doc """
  Place the cursor at column `x`, row `y`, both counted from `1`.

  The arguments are in column-then-row order, the reverse of the order they take
  in the sequence itself.

      iex> Drafter.Terminal.ANSI.cursor_to(3, 5)
      "\\e[5;3H"
  """
  @spec cursor_to(non_neg_integer(), non_neg_integer()) :: String.t()
  def cursor_to(x, y), do: "\e[#{y};#{x}H"

  @doc """
  Clear the entire screen, leaving the cursor where it is.

      iex> Drafter.Terminal.ANSI.clear_screen()
      "\\e[2J"
  """
  @spec clear_screen() :: String.t()
  def clear_screen, do: "\e[2J"

  @doc """
  Clear from the cursor to the end of the screen.

      iex> Drafter.Terminal.ANSI.clear_to_end()
      "\\e[0J"
  """
  @spec clear_to_end() :: String.t()
  def clear_to_end, do: "\e[0J"

  @doc """
  Clear the whole line the cursor is on.

      iex> Drafter.Terminal.ANSI.clear_line()
      "\\e[2K"
  """
  @spec clear_line() :: String.t()
  def clear_line, do: "\e[2K"

  @doc """
  Hide the cursor.

      iex> Drafter.Terminal.ANSI.hide_cursor()
      "\\e[?25l"
  """
  @spec hide_cursor() :: String.t()
  def hide_cursor, do: "\e[?25l"

  @doc """
  Show the cursor.

      iex> Drafter.Terminal.ANSI.show_cursor()
      "\\e[?25h"
  """
  @spec show_cursor() :: String.t()
  def show_cursor, do: "\e[?25h"

  @doc """
  Sequence that turns on mouse reporting in SGR encoding.

  Options:

    * `:hover` — when `true` (the default) any-motion tracking is enabled, so
      `:move` events arrive with no button held. When `false` only button presses,
      releases and drags are reported.

      iex> Drafter.Terminal.ANSI.enable_mouse()
      "\\e[?1003h\\e[?1006h"

      iex> Drafter.Terminal.ANSI.enable_mouse(hover: false)
      "\\e[?1002h\\e[?1006h"
  """
  @spec enable_mouse(keyword()) :: String.t()
  def enable_mouse(opts \\ []) do
    if Keyword.get(opts, :hover, true) do
      "\e[?1003h\e[?1006h"
    else
      "\e[?1002h\e[?1006h"
    end
  end

  @doc """
  Sequence that turns off mouse reporting.

  Pass the same `:hover` value that was given to `enable_mouse/1`, so the mode that
  was set is the mode that is cleared. Defaults to `true`.

      iex> Drafter.Terminal.ANSI.disable_mouse()
      "\\e[?1006l\\e[?1003l"

      iex> Drafter.Terminal.ANSI.disable_mouse(hover: false)
      "\\e[?1006l\\e[?1002l"
  """
  @spec disable_mouse(keyword()) :: String.t()
  def disable_mouse(opts \\ []) do
    if Keyword.get(opts, :hover, true) do
      "\e[?1006l\e[?1003l"
    else
      "\e[?1006l\e[?1002l"
    end
  end

  @doc """
  Switch to the alternate screen buffer, keeping the scrollback of the main one.

      iex> Drafter.Terminal.ANSI.enter_alt_screen()
      "\\e[?1049h"
  """
  @spec enter_alt_screen() :: String.t()
  def enter_alt_screen, do: "\e[?1049h"

  @doc """
  Return to the main screen buffer, restoring what was on it.

      iex> Drafter.Terminal.ANSI.exit_alt_screen()
      "\\e[?1049l"
  """
  @spec exit_alt_screen() :: String.t()
  def exit_alt_screen, do: "\e[?1049l"

  @doc """
  Open a synchronized update, so the terminal shows nothing until `sync_end/0`.

  Terminals that do not implement mode 2026 ignore it and draw as bytes arrive.

      iex> Drafter.Terminal.ANSI.sync_start()
      "\\e[?2026h"
  """
  @spec sync_start() :: String.t()
  def sync_start, do: "\e[?2026h"

  @doc """
  Close the synchronized update opened by `sync_start/0` and present the frame.

      iex> Drafter.Terminal.ANSI.sync_end()
      "\\e[?2026l"
  """
  @spec sync_end() :: String.t()
  def sync_end, do: "\e[?2026l"

  @doc """
  Set the foreground to the 24-bit color `r`, `g`, `b`, each `0..255`.

      iex> Drafter.Terminal.ANSI.fg_color(255, 0, 0)
      "\\e[38;2;255;0;0m"
  """
  @spec fg_color(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def fg_color(r, g, b), do: "\e[38;2;#{r};#{g};#{b}m"

  @doc """
  Set the background to the 24-bit color `r`, `g`, `b`, each `0..255`.

      iex> Drafter.Terminal.ANSI.bg_color(0, 0, 128)
      "\\e[48;2;0;0;128m"
  """
  @spec bg_color(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: String.t()
  def bg_color(r, g, b), do: "\e[48;2;#{r};#{g};#{b}m"

  @doc """
  Clear every attribute and both colors.

      iex> Drafter.Terminal.ANSI.reset()
      "\\e[0m"
  """
  @spec reset() :: String.t()
  def reset, do: "\e[0m"

  @doc """
  Turn on bold.

      iex> Drafter.Terminal.ANSI.bold()
      "\\e[1m"
  """
  @spec bold() :: String.t()
  def bold, do: "\e[1m"

  @doc """
  Turn on dim.

      iex> Drafter.Terminal.ANSI.dim()
      "\\e[2m"
  """
  @spec dim() :: String.t()
  def dim, do: "\e[2m"

  @doc """
  Turn on italic.

      iex> Drafter.Terminal.ANSI.italic()
      "\\e[3m"
  """
  @spec italic() :: String.t()
  def italic, do: "\e[3m"

  @doc """
  Turn on underline.

      iex> Drafter.Terminal.ANSI.underline()
      "\\e[4m"
  """
  @spec underline() :: String.t()
  def underline, do: "\e[4m"

  @doc """
  Turn on reverse video, swapping foreground and background.

      iex> Drafter.Terminal.ANSI.reverse()
      "\\e[7m"
  """
  @spec reverse() :: String.t()
  def reverse, do: "\e[7m"
end
