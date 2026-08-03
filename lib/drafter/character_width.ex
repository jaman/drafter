defmodule Drafter.CharacterWidth do
  @moduledoc """
  Terminal display width of text, in columns.

  Widths are per grapheme cluster, not per codepoint. Every measurement Drafter
  makes goes through here: strip widths, truncation, wrapping, cursor placement,
  and the compositor's column arithmetic.

  ## Examples

      iex> Drafter.CharacterWidth.string("drafter")
      7

      iex> Drafter.CharacterWidth.grapheme("漢")
      2

      iex> Drafter.CharacterWidth.grapheme("e\\u0301")
      1

  ## Choosing an implementation

  `Drafter.CharacterWidth.Default` is used when nothing is configured. A host
  that owns the grid Drafter draws into can supply its own tables instead:

      config :drafter, character_width: ETee.CharacterWidth

  The setting is read with `Application.compile_env/3`, so these functions
  compile to direct calls into the chosen module. Changing it takes effect on
  recompiling Drafter:

      mix deps.compile drafter --force

  ## Conformance

  An implementation must measure printable ASCII as one column, C0 controls and
  combining marks as zero, and East Asian wide characters as two; `U+FE0F` and
  `U+FE0E` override the base character's presentation; and `string/1` equals the
  sum of its graphemes. `Drafter.CharacterWidthConformanceTest` asserts all of
  this and can be run against a candidate module.
  """

  @typedoc "A module implementing this behaviour."
  @type implementation :: module()

  @doc "Columns one grapheme cluster occupies. Zero for an empty string."
  @callback grapheme(String.t()) :: non_neg_integer()

  @doc "Columns a whole string occupies, summed over its grapheme clusters."
  @callback string(String.t()) :: non_neg_integer()

  @doc "Columns a single codepoint occupies, ignoring any cluster it belongs to."
  @callback codepoint(non_neg_integer()) :: non_neg_integer()

  @doc """
  Whether a binary is entirely printable ASCII.

  A `true` answer means the binary's byte size equals its column width, so
  callers may skip grapheme segmentation.
  """
  @callback printable_ascii?(binary()) :: boolean()

  @implementation Application.compile_env(:drafter, :character_width, __MODULE__.Default)

  @doc "The implementation in use."
  @spec implementation() :: implementation()
  def implementation, do: @implementation

  @doc "Whether Drafter is measuring with its own tables rather than a host's."
  @spec default?() :: boolean()
  def default?, do: @implementation == __MODULE__.Default

  defdelegate grapheme(grapheme), to: @implementation
  defdelegate string(text), to: @implementation
  defdelegate codepoint(codepoint), to: @implementation
  defdelegate printable_ascii?(binary), to: @implementation
end
