defmodule Drafter.Prompt.Text do
  @moduledoc """
  The component behind `Drafter.Prompt.text/2`, `password/2`, `number/2` and
  `readline/2`: one line of text with editing keys, history and Tab completion.

  ## Options

    * `:label` - the question, or the prompt string when `:plain` is set
    * `:default` - the value used when the line is submitted empty
    * `:placeholder` - dimmed text shown while the line is empty
    * `:validate` - `(value -> :ok | {:error, message})`, run on submit
    * `:parse` - `(text -> {:ok, value} | {:error, message})`, run on submit before
      `:validate`; the prompt returns `value`
    * `:complete` - a `t:Drafter.Prompt.Completion.source/0` for Tab
    * `:history` - earlier lines, newest first, recalled with Up and Down
    * `:mask` - a character shown in place of every typed one
    * `:plain` - `true` draws only the label and the line, and leaves both on screen
      unchanged when the prompt ends
    * `:limit` - the most completion candidates listed at once. Default
      `config :drafter, prompt_limit: 7`

  ## Keys

  Enter submits. Esc stops the prompt with `:cancelled`, and Ctrl+D on an empty line
  stops it with `:eof`. Up and Down recall history. Tab completes: one candidate is
  inserted, and several are listed, after which Tab, Shift+Tab, Up and Down step
  through them, Enter keeps the chosen one and Esc closes the list. Every other key is
  an editing key of `Drafter.Prompt.Editor`.
  """

  @behaviour Drafter.Prompt.Component

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.{Completion, Editor, Frame, Style, Window}

  defstruct label: "",
            editor: %Editor{},
            default: nil,
            placeholder: nil,
            validate: nil,
            parse: nil,
            complete: nil,
            history: [],
            recalled: nil,
            draft: "",
            mask: nil,
            plain: false,
            error: nil,
            menu: nil,
            limit: 7

  @impl true
  def init(opts) do
    %__MODULE__{
      label: Keyword.get(opts, :label, ""),
      default: default(Keyword.get(opts, :default)),
      placeholder: Keyword.get(opts, :placeholder),
      validate: Keyword.get(opts, :validate),
      parse: Keyword.get(opts, :parse),
      complete: Keyword.get(opts, :complete),
      history: Keyword.get(opts, :history, []),
      mask: Keyword.get(opts, :mask),
      plain: Keyword.get(opts, :plain, false),
      limit: Keyword.get(opts, :limit, Application.get_env(:drafter, :prompt_limit, 7))
    }
  end

  @impl true
  def handle_event({:key, :enter}, %__MODULE__{menu: %{index: index}} = state)
      when is_integer(index),
      do: {:cont, %{state | menu: nil}}

  def handle_event({:key, :enter}, state), do: submit(state)
  def handle_event({:key, :tab}, %__MODULE__{complete: nil} = state), do: {:cont, state}
  def handle_event({:key, :tab}, %__MODULE__{menu: nil} = state), do: {:cont, complete(state)}
  def handle_event({:key, :tab}, state), do: {:cont, step(state, 1)}

  def handle_event({:key, :tab, [:shift]}, %__MODULE__{menu: %{}} = state),
    do: {:cont, step(state, -1)}

  def handle_event({:key, :down}, %__MODULE__{menu: %{}} = state), do: {:cont, step(state, 1)}
  def handle_event({:key, :up}, %__MODULE__{menu: %{}} = state), do: {:cont, step(state, -1)}
  def handle_event({:key, :up}, state), do: {:cont, recall(state, 1)}
  def handle_event({:key, :p, [:ctrl]}, state), do: {:cont, recall(state, 1)}
  def handle_event({:key, :down}, state), do: {:cont, recall(state, -1)}
  def handle_event({:key, :n, [:ctrl]}, state), do: {:cont, recall(state, -1)}

  def handle_event({:key, :escape}, %__MODULE__{menu: %{}} = state),
    do: {:cont, %{state | menu: nil}}

  def handle_event({:key, :escape}, state), do: {:stop, :cancelled, state}

  def handle_event(
        {:key, :d, [:ctrl]},
        %__MODULE__{editor: %Editor{before: [], after: []}} = state
      ),
      do: {:stop, :eof, state}

  def handle_event(event, state) do
    case Editor.edit(state.editor, event) do
      {:ok, editor} -> {:cont, %{state | editor: editor, error: nil, menu: nil}}
      :ignored -> {:cont, state}
    end
  end

  @impl true
  def render(state, :active, %{style: style, width: width}) do
    head = head(state, style)
    head_width = head |> Strip.new() |> Strip.width()
    {input, column} = input(state, style, max(width - head_width, 4))

    Frame.new(
      [Strip.new(head ++ input)] ++ error_lines(state, style) ++ menu_lines(state, style),
      {0, head_width + column}
    )
  end

  def render(%__MODULE__{plain: true} = state, _ended, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :plain, state.label),
        Style.segment(style, :plain, shown(state))
      ])
    ])
  end

  def render(state, {:done, _value}, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :success, Style.symbol(style, :done)),
        Style.segment(style, :strong, " " <> state.label <> " "),
        Style.segment(style, :muted, Style.symbol(style, :separator) <> " "),
        Style.segment(style, :plain, state |> entered() |> conceal(state.mask))
      ])
    ])
  end

  def render(state, {:stopped, _reason}, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :error, Style.symbol(style, :failed)),
        Style.segment(style, :muted, " " <> state.label)
      ])
    ])
  end

  @impl true
  def line_prompt(%__MODULE__{plain: true, label: label}), do: label

  def line_prompt(%__MODULE__{label: label, default: nil}) do
    if String.ends_with?(label, ["?", ":"]), do: [label, " "], else: [label, ": "]
  end

  def line_prompt(%__MODULE__{label: label, default: default}), do: [label, " (", default, "): "]

  @impl true
  def parse_line("", %__MODULE__{default: default} = state) when is_binary(default),
    do: accept(state, default)

  def parse_line(line, state), do: accept(state, line)

  defp default(nil), do: nil
  defp default(value), do: to_string(value)

  defp submit(state) do
    case accept(state, entered(state)) do
      {:ok, value} -> {:done, value, state}
      {:error, message} -> {:cont, %{state | error: message, menu: nil}}
    end
  end

  defp accept(state, text) do
    with {:ok, value} <- parse(state.parse, text),
         :ok <- validate(state.validate, value) do
      {:ok, value}
    end
  end

  defp parse(nil, text), do: {:ok, text}
  defp parse(parse, text), do: parse.(text)

  defp validate(nil, _value), do: :ok
  defp validate(validate, value), do: validate.(value)

  defp entered(%__MODULE__{editor: editor, default: default}),
    do: entered(Editor.text(editor), default)

  defp entered("", default) when is_binary(default), do: default
  defp entered(text, _default), do: text

  defp complete(state) do
    state.complete
    |> Completion.candidates(Editor.before_cursor(state.editor))
    |> offer(state)
  end

  defp offer([], state), do: state

  defp offer([only], state),
    do: %{state | editor: Editor.replace_word(state.editor, only), error: nil}

  defp offer(candidates, state) do
    prefix = Completion.common_prefix(candidates)
    typed = Completion.word(Editor.before_cursor(state.editor))

    editor =
      if String.length(prefix) > String.length(typed),
        do: Editor.replace_word(state.editor, prefix),
        else: state.editor

    %{state | editor: editor, error: nil, menu: %{items: candidates, index: nil}}
  end

  defp step(%__MODULE__{menu: %{items: items, index: index}} = state, by) do
    index = next_index(index, by, length(items))

    %{
      state
      | menu: %{items: items, index: index},
        editor: Editor.replace_word(state.editor, Enum.at(items, index))
    }
  end

  defp next_index(nil, by, _count) when by > 0, do: 0
  defp next_index(nil, _by, count), do: count - 1
  defp next_index(index, by, count), do: Integer.mod(index + by, count)

  defp recall(%__MODULE__{history: []} = state, _by), do: state

  defp recall(state, by) do
    current = state.recalled || -1
    target = (current + by) |> max(-1) |> min(length(state.history) - 1)
    recalled(state, current, target)
  end

  defp recalled(state, same, same), do: state

  defp recalled(state, _current, -1),
    do: %{state | recalled: nil, editor: Editor.new(state.draft), menu: nil}

  defp recalled(state, -1, target),
    do: recalled(%{state | draft: Editor.text(state.editor)}, nil, target)

  defp recalled(state, _current, target),
    do: %{state | recalled: target, editor: Editor.new(Enum.at(state.history, target)), menu: nil}

  defp head(%__MODULE__{plain: true, label: label}, style),
    do: [Style.segment(style, :plain, label)]

  defp head(state, style) do
    [
      Style.segment(style, :accent, Style.symbol(style, :question)),
      Style.segment(style, :strong, " " <> state.label <> " ")
    ] ++
      default_hint(state.default, style) ++
      [Style.segment(style, :muted, Style.symbol(style, :prompt) <> " ")]
  end

  defp default_hint(nil, _style), do: []
  defp default_hint(default, style), do: [Style.segment(style, :muted, "(" <> default <> ") ")]

  defp input(
         %__MODULE__{editor: %Editor{before: [], after: []}, placeholder: placeholder},
         style,
         _room
       )
       when is_binary(placeholder),
       do: {[Style.segment(style, :muted, placeholder)], 0}

  defp input(state, style, room) do
    {text, column} = state.editor |> mask(state.mask) |> Editor.view(room)
    {[Style.segment(style, :plain, text)], column}
  end

  defp shown(state), do: state.editor |> Editor.text() |> conceal(state.mask)

  defp mask(editor, nil), do: editor
  defp mask(editor, mask), do: Editor.masked(editor, mask)

  defp conceal(text, nil), do: text
  defp conceal(text, mask), do: String.duplicate(mask, String.length(text))

  defp error_lines(%__MODULE__{error: nil}, _style), do: []

  defp error_lines(%__MODULE__{error: message}, style) do
    [
      Strip.new([
        Style.segment(style, :error, "  " <> Style.symbol(style, :failed) <> " " <> message)
      ])
    ]
  end

  defp menu_lines(%__MODULE__{menu: nil}, _style), do: []

  defp menu_lines(%__MODULE__{menu: %{items: items, index: index}, limit: limit}, style) do
    count = length(items)
    window = Window.range(count, index || 0, limit)

    rows =
      items
      |> Enum.with_index()
      |> Enum.slice(window)
      |> Enum.map(&menu_line(&1, index, style))

    rows ++ Window.footer(window, count, style)
  end

  defp menu_line({item, index}, index, style),
    do: Strip.new([Style.segment(style, :accent, Style.symbol(style, :pointer) <> " " <> item)])

  defp menu_line({item, _index}, _chosen, style),
    do: Strip.new([Style.segment(style, :plain, "  " <> item)])
end
