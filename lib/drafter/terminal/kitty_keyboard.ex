defmodule Drafter.Terminal.KittyKeyboard do
  @moduledoc """
  The kitty keyboard protocol: the sequences that switch it on and off, and the
  parsing of the key reports a terminal sends while it is on.

  `push/0` asks for disambiguated escape codes, press/repeat/release event types,
  every key as an escape code, and the text a key produces. `pop/0` restores the
  mode that was in force before. `query/0` asks for the current flags; a terminal
  that speaks the protocol answers `CSI ? flags u`, one that does not stays silent.

  `parse/1` turns one report into events for `Drafter.Terminal.ANSI`:

    * a press yields the same `{:key, ...}` or `{:char, ...}` event the legacy
      encoding would have produced, followed by `{:key_down, key, modifiers}`
    * a repeat yields the legacy event only
    * a release yields `{:key_up, key, modifiers}`
    * the reply to `query/0` yields `{:key_release_support, true}` when the flags in
      force include event types, so releases will be reported, and
      `{:key_release_support, false}` when they do not — a terminal that speaks the
      protocol but took only some of what `push/0` asked for

  `key` in `:key_down` and `:key_up` is the unshifted key: `:a` for both `a` and
  `A`, `:"1"` for both `1` and `!`, a name such as `:left_shift` or `:kp_5` for a key
  with no glyph, and an integer codepoint for a glyph outside ASCII. `modifiers`
  is the `[:ctrl, :alt, :shift]` subset held, in that order, and may be empty.
  Caps lock and num lock are not modifiers. Keys with no glyph produce no legacy
  event unless the terminal reported text for them.
  """

  alias Drafter.Terminal.ANSI

  @flags 27
  @event_types 2
  @finals ~c"u~ABCDEFHPQS"

  @type key :: atom() | non_neg_integer()
  @type event ::
          ANSI.event()
          | {:key_down, key(), ANSI.modifiers()}
          | {:key_up, key(), ANSI.modifiers()}
          | {:key_release_support, boolean()}

  @functional %{
    57_358 => :caps_lock,
    57_359 => :scroll_lock,
    57_360 => :num_lock,
    57_361 => :print_screen,
    57_362 => :pause,
    57_363 => :menu,
    57_399 => :kp_0,
    57_400 => :kp_1,
    57_401 => :kp_2,
    57_402 => :kp_3,
    57_403 => :kp_4,
    57_404 => :kp_5,
    57_405 => :kp_6,
    57_406 => :kp_7,
    57_407 => :kp_8,
    57_408 => :kp_9,
    57_409 => :kp_decimal,
    57_410 => :kp_divide,
    57_411 => :kp_multiply,
    57_412 => :kp_subtract,
    57_413 => :kp_add,
    57_414 => :kp_enter,
    57_415 => :kp_equal,
    57_416 => :kp_separator,
    57_417 => :kp_left,
    57_418 => :kp_right,
    57_419 => :kp_up,
    57_420 => :kp_down,
    57_421 => :kp_page_up,
    57_422 => :kp_page_down,
    57_423 => :kp_home,
    57_424 => :kp_end,
    57_425 => :kp_insert,
    57_426 => :kp_delete,
    57_427 => :kp_begin,
    57_428 => :media_play,
    57_429 => :media_pause,
    57_430 => :media_play_pause,
    57_431 => :media_reverse,
    57_432 => :media_stop,
    57_433 => :media_fast_forward,
    57_434 => :media_rewind,
    57_435 => :media_track_next,
    57_436 => :media_track_previous,
    57_437 => :media_record,
    57_438 => :lower_volume,
    57_439 => :raise_volume,
    57_440 => :mute_volume,
    57_441 => :left_shift,
    57_442 => :left_control,
    57_443 => :left_alt,
    57_444 => :left_super,
    57_445 => :left_hyper,
    57_446 => :left_meta,
    57_447 => :right_shift,
    57_448 => :right_control,
    57_449 => :right_alt,
    57_450 => :right_super,
    57_451 => :right_hyper,
    57_452 => :right_meta,
    57_453 => :iso_level3_shift,
    57_454 => :iso_level5_shift
  }

  @function_keys for n <- 13..35, into: %{}, do: {57_363 + n, :"f#{n}"}

  @named %{27 => :escape, 13 => :enter, 9 => :tab, 127 => :backspace}

  @letter_finals %{
    ?A => :up,
    ?B => :down,
    ?C => :right,
    ?D => :left,
    ?E => :kp_begin,
    ?F => :end,
    ?H => :home,
    ?P => :f1,
    ?Q => :f2,
    ?S => :f4
  }

  @tilde_keys %{
    2 => :insert,
    3 => :delete,
    5 => :page_up,
    6 => :page_down,
    7 => :home,
    8 => :end,
    11 => :f1,
    12 => :f2,
    13 => :f3,
    14 => :f4,
    15 => :f5,
    17 => :f6,
    18 => :f7,
    19 => :f8,
    20 => :f9,
    21 => :f10,
    23 => :f11,
    24 => :f12
  }

  @doc "The sequence that turns the protocol on for the running program."
  @spec push() :: String.t()
  def push, do: "\e[>#{@flags}u"

  @doc "The sequence that turns it off again."
  @spec pop() :: String.t()
  def pop, do: "\e[<u"

  @doc "The sequence that asks the terminal whether it speaks the protocol."
  @spec query() :: String.t()
  def query, do: "\e[?u"

  @doc """
  Parse one report at the head of `buffer`.

  Returns the events it produced and the bytes after it, or `:no_match` when the
  buffer does not begin with a report this module reads. A report whose final
  byte has not arrived is `:no_match` as well; `Drafter.Terminal.ANSI` holds those
  back before asking.

  With `key_release` false, only reports the legacy encodings cannot produce are
  read: a `u` final, or an event type or alternate key after a colon. With it true
  every CSI key report is read, including the legacy forms, each press gaining its
  `:key_down`.
  """
  @spec parse(binary(), boolean()) :: {[event()], binary()} | :no_match
  def parse(buffer, key_release \\ false)

  def parse(<<"\e[?", rest::binary>>, _key_release) do
    case Integer.parse(rest) do
      {flags, <<"u", after_reply::binary>>} ->
        {[{:key_release_support, Bitwise.band(flags, @event_types) != 0}], after_reply}

      _ ->
        :no_match
    end
  end

  def parse(<<"\e[", rest::binary>>, key_release) do
    case split_params(rest, <<>>) do
      {params, final, after_report} when final in @finals ->
        if key_release or protocol_only?(params, final) do
          {events(params, final), after_report}
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  def parse(_buffer, _key_release), do: :no_match

  defp protocol_only?(_params, ?u), do: true
  defp protocol_only?(params, _final), do: Enum.any?(params, &String.contains?(&1, ":"))

  @doc """
  The `{:key_down, key, modifiers}` event matching a legacy key press.

  Used while the protocol is on for the keys a terminal still reports in their
  legacy encoding, so every press has a `:key_down` whichever encoding it arrived in.
  """
  @spec key_down({:key, atom()} | {:key, atom(), ANSI.modifiers()}) ::
          {:key_down, key(), ANSI.modifiers()}
  def key_down({:key, key}), do: {:key_down, base_of_legacy(key), []}
  def key_down({:key, key, modifiers}), do: {:key_down, base_of_legacy(key), modifiers}

  defp base_of_legacy(key) do
    case Atom.to_string(key) do
      <<char>> when char in ?A..?Z -> String.to_atom(<<char + 32>>)
      _ -> key
    end
  end

  defp split_params(<<byte, rest::binary>>, acc) when byte in 0x30..0x3F do
    split_params(rest, <<acc::binary, byte>>)
  end

  defp split_params(<<final, rest::binary>>, acc) when final in 0x40..0x7E do
    {String.split(acc, ";"), final, rest}
  end

  defp split_params(_incomplete, _acc), do: :incomplete

  defp events(params, ?u) do
    [key_field | more] = params
    {code, _alternates} = subparams(key_field)
    {modifiers, type} = modifiers_and_type(Enum.at(more, 0))
    text = text_codepoints(Enum.at(more, 1))

    case code do
      nil -> []
      code -> emit(type, key_of(code), legacy_of(code, modifiers, text), modifiers)
    end
  end

  defp events(params, ?~) do
    [number_field | more] = params
    {number, _} = subparams(number_field)
    {modifiers, type} = modifiers_and_type(Enum.at(more, 0))
    named(Map.get(@tilde_keys, number), type, modifiers)
  end

  defp events(params, final) do
    {modifiers, type} = modifiers_and_type(Enum.at(params, 1))
    named(Map.get(@letter_finals, final), type, modifiers)
  end

  defp named(nil, _type, _modifiers), do: []

  defp named(name, type, modifiers) do
    emit(type, name, [legacy_key(name, modifiers)], modifiers)
  end

  defp emit(_type, nil, _legacy, _modifiers), do: []
  defp emit(1, key, legacy, modifiers), do: legacy ++ [{:key_down, key, modifiers}]
  defp emit(2, _key, legacy, _modifiers), do: legacy
  defp emit(3, key, _legacy, modifiers), do: [{:key_up, key, modifiers}]
  defp emit(_type, _key, _legacy, _modifiers), do: []

  defp subparams(field) do
    case String.split(field, ":") do
      [""] -> {nil, []}
      [head | tail] -> {to_int(head), Enum.map(tail, &to_int/1)}
    end
  end

  defp modifiers_and_type(nil), do: {[], 1}

  defp modifiers_and_type(field) do
    case subparams(field) do
      {nil, _} -> {[], 1}
      {mods, []} -> {modifier_list(mods - 1), 1}
      {mods, [type | _]} -> {modifier_list(mods - 1), type || 1}
    end
  end

  defp modifier_list(bits) do
    for {flag, bit} <- [ctrl: 4, alt: 2, shift: 1], Bitwise.band(bits, bit) != 0, do: flag
  end

  defp text_codepoints(nil), do: []

  defp text_codepoints(field) do
    field |> String.split(":") |> Enum.map(&to_int/1) |> Enum.reject(&is_nil/1)
  end

  defp to_int(""), do: nil

  defp to_int(digits) do
    case Integer.parse(digits) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp key_of(code) when code in 32..126, do: ANSI.printable_key(code)
  defp key_of(code) when is_map_key(@named, code), do: Map.fetch!(@named, code)
  defp key_of(code) when is_map_key(@functional, code), do: Map.fetch!(@functional, code)
  defp key_of(code) when is_map_key(@function_keys, code), do: Map.fetch!(@function_keys, code)
  defp key_of(code) when code >= 57_344 and code <= 63_743, do: nil
  defp key_of(code), do: code

  defp legacy_of(code, modifiers, text) when is_map_key(@named, code) do
    [legacy_key(Map.fetch!(@named, code), modifiers)] ++ typed(text, modifiers)
  end

  defp legacy_of(code, modifiers, text) when code in 32..126 or code > 63_743 or code < 57_344 do
    glyph_events(code, modifiers, text)
  end

  defp legacy_of(_code, modifiers, text), do: typed(text, modifiers)

  defp glyph_events(code, modifiers, text) do
    cond do
      :ctrl in modifiers or :alt in modifiers -> [{:key, key_of(code), modifiers}]
      text != [] -> typed(text, modifiers)
      modifiers == [:shift] -> [shifted(code)]
      true -> [glyph(code)]
    end
  end

  defp typed(text, modifiers) do
    if :ctrl in modifiers or :alt in modifiers do
      []
    else
      for codepoint <- text, codepoint >= 32, do: glyph(codepoint)
    end
  end

  defp glyph(code) when code in 32..126, do: {:key, ANSI.printable_key(code)}
  defp glyph(code), do: {:char, code}

  defp shifted(code) when code in ?a..?z, do: {:key, ANSI.printable_key(code - 32)}
  defp shifted(code) when code in 32..126, do: {:key, ANSI.printable_key(code), [:shift]}
  defp shifted(code), do: {:char, code}

  defp legacy_key(name, []), do: {:key, name}
  defp legacy_key(name, modifiers), do: {:key, name, modifiers}
end
