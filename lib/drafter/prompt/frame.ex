defmodule Drafter.Prompt.Frame do
  @moduledoc """
  What a prompt shows at one moment: lines of styled text and the text cursor's place.

  `lines` is a list of `Drafter.Draw.Strip`, top to bottom. `cursor` is `{row, column}`
  counted from the frame's first line and first column, or `nil` to hide the cursor.

      iex> alias Drafter.Draw.Strip
      iex> frame = Drafter.Prompt.Frame.new([Strip.from_text("Name: ada")], {0, 9})
      iex> Drafter.Prompt.Frame.text(frame)
      "Name: ada"
  """

  alias Drafter.Draw.Strip

  @enforce_keys [:lines]
  defstruct lines: [], cursor: nil

  @type cursor :: {non_neg_integer(), non_neg_integer()} | nil
  @type t :: %__MODULE__{lines: [Strip.t()], cursor: cursor()}

  @doc "A frame of `lines` with the cursor at `cursor`, hidden when `cursor` is `nil`."
  @spec new([Strip.t()], cursor()) :: t()
  def new(lines, cursor \\ nil) when is_list(lines), do: %__MODULE__{lines: lines, cursor: cursor}

  @doc "The frame's text without styling, its lines joined by newlines."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{lines: lines}) do
    Enum.map_join(lines, "\n", fn %Strip{segments: segments} ->
      Enum.map_join(segments, & &1.text)
    end)
  end
end
