defmodule Drafter.Prompt.Completion do
  @moduledoc """
  Tab completion sources for text prompts.

  A source is a list of words, or a function that takes the text before the cursor and
  returns the candidates for the word being typed. The word being typed is the run of
  characters other than whitespace that ends at the cursor, and a candidate replaces
  all of it.

      iex> Drafter.Prompt.Completion.candidates(["start", "status", "stop"], "service sta")
      ["start", "status"]

      iex> Drafter.Prompt.Completion.common_prefix(["start", "status"])
      "sta"

  `paths/1` builds a source that completes file names:

      Drafter.Prompt.text("Config file", complete: Drafter.Prompt.Completion.paths())
  """

  @type source :: [String.t()] | (String.t() -> [String.t()])

  @doc """
  The candidates `source` offers for the text before the cursor.

  A list offers its words that start with the word being typed.
  """
  @spec candidates(source(), String.t()) :: [String.t()]
  def candidates(words, before) when is_list(words) do
    word = word(before)
    Enum.filter(words, &String.starts_with?(&1, word))
  end

  def candidates(source, before) when is_function(source, 1), do: source.(before)

  @doc """
  The word being typed: what follows the last whitespace in `before`.

      iex> Drafter.Prompt.Completion.word("git che")
      "che"

      iex> Drafter.Prompt.Completion.word("git ")
      ""
  """
  @spec word(String.t()) :: String.t()
  def word(before), do: before |> String.split(~r/\s/) |> List.last()

  @doc """
  The longest text every candidate starts with.

      iex> Drafter.Prompt.Completion.common_prefix(["lib/a.ex", "lib/b.ex"])
      "lib/"

      iex> Drafter.Prompt.Completion.common_prefix([])
      ""
  """
  @spec common_prefix([String.t()]) :: String.t()
  def common_prefix([]), do: ""

  def common_prefix([first | rest]) do
    rest
    |> Enum.reduce(String.graphemes(first), &shared(&2, String.graphemes(&1)))
    |> Enum.join()
  end

  @doc """
  A source that completes the word being typed as a file path.

  A candidate keeps the directory part as it was typed, so `~/Doc` completes to
  `~/Documents/`. Directories end in `/`. Names starting with `.` are offered only
  when the name being typed starts with `.`.

  ## Options

    * `:only` - `:directories` offers directories alone. Default `:all`.
  """
  @spec paths(keyword()) :: (String.t() -> [String.t()])
  def paths(opts \\ []) do
    only = Keyword.get(opts, :only, :all)
    fn before -> before |> word() |> list_paths(only) end
  end

  @doc """
  A source for a command line: the first word completes to a command name and the
  words after it complete from that command's own source.

  `commands` maps each command name to the source for its arguments; use `[]` for a
  command that takes none.

      iex> source = Drafter.Prompt.Completion.commands(%{"open" => ["inbox", "outbox"], "quit" => []})
      iex> source.("q")
      ["quit"]
      iex> source.("open in")
      ["inbox"]
  """
  @spec commands(%{String.t() => source()}) :: (String.t() -> [String.t()])
  def commands(commands) when is_map(commands) do
    names = commands |> Map.keys() |> Enum.sort()

    fn before ->
      case before |> String.trim_leading() |> String.split(~r/\s+/, parts: 2) do
        [_name] -> candidates(names, before)
        [name, _arguments] -> commands |> Map.get(name, []) |> candidates(before)
      end
    end
  end

  defp shared([same | left], [same | right]), do: [same | shared(left, right)]
  defp shared(_left, _right), do: []

  defp list_paths(word, only) do
    {typed_directory, name} = split_path(word)
    directory = Path.expand(if typed_directory == "", do: ".", else: typed_directory)

    case File.ls(directory) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&offered?(&1, name))
        |> Enum.sort()
        |> Enum.map(&{typed_directory <> &1, File.dir?(Path.join(directory, &1))})
        |> Enum.filter(fn {_path, directory?} -> directory? or only == :all end)
        |> Enum.map(&complete_path/1)

      {:error, _reason} ->
        []
    end
  end

  defp split_path(word) do
    case :binary.matches(word, "/") do
      [] ->
        {"", word}

      slashes ->
        {position, 1} = List.last(slashes)

        {binary_part(word, 0, position + 1),
         binary_part(word, position + 1, byte_size(word) - position - 1)}
    end
  end

  defp offered?("." <> _rest = entry, "." <> _typed = name), do: String.starts_with?(entry, name)
  defp offered?("." <> _rest, _name), do: false
  defp offered?(entry, name), do: String.starts_with?(entry, name)

  defp complete_path({path, true}), do: path <> "/"
  defp complete_path({path, false}), do: path
end
