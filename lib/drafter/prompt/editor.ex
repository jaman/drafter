defmodule Drafter.Prompt.Editor do
  @moduledoc """
  One line of text with a cursor in it, and the editing keys that change it.

      iex> alias Drafter.Prompt.Editor
      iex> editor = Editor.new("hello world")
      iex> {:ok, editor} = Editor.edit(editor, {:key, :w, [:ctrl]})
      iex> Editor.text(editor)
      "hello "
      iex> {:ok, editor} = Editor.edit(editor, {:key, :y, [:ctrl]})
      iex> Editor.text(editor)
      "hello world"

  The cursor sits between graphemes, so a character made of several codepoints moves
  and deletes as one. A word is a run of characters other than spaces.

  ## Keys

  `edit/2` understands these events and answers `:ignored` to any other:

    * a printable key, `{:char, codepoint}` or `{:bracketed_paste, text}` inserts
    * `Backspace`, `Ctrl+H` and `Delete`, `Ctrl+D` delete one character
    * `Left`, `Ctrl+B`, `Right`, `Ctrl+F` move one character
    * `Home`, `Ctrl+A`, `End`, `Ctrl+E` move to either end
    * `Ctrl+Left`, `Alt+Left`, `Ctrl+Right`, `Alt+Right` move one word
    * `Ctrl+W` cuts the word before the cursor, `Ctrl+U` everything before it and
      `Ctrl+K` everything after it
    * `Ctrl+Y` inserts what was cut last
  """

  alias Drafter.{Clipboard, Text}

  defstruct before: [], after: [], cut: ""

  @typedoc """
  `before` holds the graphemes before the cursor, nearest first. `after` holds the
  ones after it in reading order. `cut` is the text cut last.
  """
  @type t :: %__MODULE__{before: [String.t()], after: [String.t()], cut: String.t()}

  @doc "An editor holding `text` with the cursor at its end."
  @spec new(String.t()) :: t()
  def new(text \\ ""), do: %__MODULE__{before: text |> String.graphemes() |> Enum.reverse()}

  @doc "The whole line."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{before: before, after: rest}),
    do: IO.iodata_to_binary([Enum.reverse(before), rest])

  @doc "The text before the cursor."
  @spec before_cursor(t()) :: String.t()
  def before_cursor(%__MODULE__{before: before}), do: before |> Enum.reverse() |> Enum.join()

  @doc "Whether the line is empty."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{before: [], after: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Insert `text` at the cursor.

  Line breaks and tabs become spaces and other control characters are dropped.
  """
  @spec insert(t(), String.t()) :: t()
  def insert(%__MODULE__{before: []} = editor, text),
    do: %{editor | before: text |> printable() |> String.graphemes() |> Enum.reverse()}

  def insert(%__MODULE__{before: [last | rest]} = editor, text) do
    joined = String.graphemes(last <> printable(text))
    %{editor | before: Enum.reverse(joined, rest)}
  end

  @doc """
  Replace the word the cursor is at the end of with `replacement`.

  The word is the run of characters other than spaces before the cursor, which is
  empty when the cursor follows a space.
  """
  @spec replace_word(t(), String.t()) :: t()
  def replace_word(%__MODULE__{before: before} = editor, replacement) do
    {_word, rest} = Enum.split_while(before, &(not space?(&1)))
    insert(%{editor | before: rest}, replacement)
  end

  @doc "The same line with every character replaced by `mask`."
  @spec masked(t(), String.t()) :: t()
  def masked(%__MODULE__{before: before, after: rest} = editor, mask),
    do: %{
      editor
      | before: Enum.map(before, fn _ -> mask end),
        after: Enum.map(rest, fn _ -> mask end)
    }

  @doc """
  Apply one key or paste event.

  Returns `{:ok, editor}` for an event the editor understands, changed or not, and
  `:ignored` for any other.
  """
  @spec edit(t(), Drafter.Terminal.ANSI.event()) :: {:ok, t()} | :ignored
  def edit(editor, {:key, :backspace}), do: {:ok, backspace(editor)}
  def edit(editor, {:key, :h, [:ctrl]}), do: {:ok, backspace(editor)}
  def edit(editor, {:key, :delete}), do: {:ok, delete(editor)}
  def edit(editor, {:key, :d, [:ctrl]}), do: {:ok, delete(editor)}
  def edit(editor, {:key, :left}), do: {:ok, left(editor)}
  def edit(editor, {:key, :b, [:ctrl]}), do: {:ok, left(editor)}
  def edit(editor, {:key, :right}), do: {:ok, right(editor)}
  def edit(editor, {:key, :f, [:ctrl]}), do: {:ok, right(editor)}
  def edit(editor, {:key, :home}), do: {:ok, home(editor)}
  def edit(editor, {:key, :a, [:ctrl]}), do: {:ok, home(editor)}
  def edit(editor, {:key, :end}), do: {:ok, to_end(editor)}
  def edit(editor, {:key, :e, [:ctrl]}), do: {:ok, to_end(editor)}

  def edit(editor, {:key, :left, [modifier]}) when modifier in [:ctrl, :alt],
    do: {:ok, word_left(editor)}

  def edit(editor, {:key, :right, [modifier]}) when modifier in [:ctrl, :alt],
    do: {:ok, word_right(editor)}

  def edit(editor, {:key, :w, [:ctrl]}), do: {:ok, cut_word(editor)}
  def edit(editor, {:key, :u, [:ctrl]}), do: {:ok, cut_before(editor)}
  def edit(editor, {:key, :k, [:ctrl]}), do: {:ok, cut_after(editor)}
  def edit(editor, {:key, :y, [:ctrl]}), do: {:ok, insert(editor, editor.cut)}
  def edit(editor, {:char, codepoint}), do: {:ok, insert(editor, <<codepoint::utf8>>)}
  def edit(editor, {:bracketed_paste, text}), do: {:ok, insert(editor, Clipboard.sanitize(text))}
  def edit(editor, {:key, key}) when is_atom(key), do: typed(editor, Atom.to_string(key))
  def edit(_editor, _event), do: :ignored

  @doc """
  The part of the line that fits in `width` columns, and the cursor's column in it.

  The line scrolls so the cursor stays in view: text before the cursor is cut from the
  left until it fits in `width - 1` columns, and text after it is cut from the right.

      iex> Drafter.Prompt.Editor.view(Drafter.Prompt.Editor.new("abcdefgh"), 5)
      {"efgh", 4}
  """
  @spec view(t(), pos_integer()) :: {String.t(), non_neg_integer()}
  def view(%__MODULE__{before: before, after: rest}, width) do
    {shown_before, column} = fit(before, max(width - 1, 0))
    {shown_after, _columns} = fit(rest, width - column)
    {IO.iodata_to_binary([Enum.reverse(shown_before), shown_after]), column}
  end

  defp typed(editor, <<_codepoint::utf8>> = character), do: {:ok, insert(editor, character)}
  defp typed(_editor, _name), do: :ignored

  defp backspace(%__MODULE__{before: [_removed | rest]} = editor), do: %{editor | before: rest}
  defp backspace(editor), do: editor

  defp delete(%__MODULE__{after: [_removed | rest]} = editor), do: %{editor | after: rest}
  defp delete(editor), do: editor

  defp left(%__MODULE__{before: [grapheme | rest]} = editor),
    do: %{editor | before: rest, after: [grapheme | editor.after]}

  defp left(editor), do: editor

  defp right(%__MODULE__{after: [grapheme | rest]} = editor),
    do: %{editor | before: [grapheme | editor.before], after: rest}

  defp right(editor), do: editor

  defp home(editor), do: %{editor | before: [], after: Enum.reverse(editor.before, editor.after)}

  defp to_end(editor),
    do: %{editor | before: Enum.reverse(editor.after, editor.before), after: []}

  defp word_left(editor) do
    {word, rest} = split_word(editor.before)
    %{editor | before: rest, after: Enum.reverse(word, editor.after)}
  end

  defp word_right(editor) do
    {word, rest} = split_word(editor.after)
    %{editor | before: Enum.reverse(word, editor.before), after: rest}
  end

  defp cut_word(editor) do
    {word, rest} = split_word(editor.before)
    %{editor | before: rest, cut: word |> Enum.reverse() |> Enum.join()}
  end

  defp cut_before(editor), do: %{editor | before: [], cut: before_cursor(editor)}

  defp cut_after(editor), do: %{editor | after: [], cut: Enum.join(editor.after)}

  defp split_word(graphemes) do
    {spaces, rest} = Enum.split_while(graphemes, &space?/1)
    {word, rest} = Enum.split_while(rest, &(not space?(&1)))
    {spaces ++ word, rest}
  end

  defp space?(grapheme), do: grapheme == " "

  defp printable(text) do
    text
    |> String.replace(["\r\n", "\n", "\r", "\t"], " ")
    |> String.replace(~r/[\x00-\x1f\x7f]/, "")
  end

  defp fit(graphemes, width) do
    {taken, columns} =
      Enum.reduce_while(graphemes, {[], 0}, fn grapheme, {taken, columns} ->
        wider = columns + Text.display_width(grapheme)

        if wider > width,
          do: {:halt, {taken, columns}},
          else: {:cont, {[grapheme | taken], wider}}
      end)

    {Enum.reverse(taken), columns}
  end
end
