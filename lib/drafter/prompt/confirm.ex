defmodule Drafter.Prompt.Confirm do
  @moduledoc """
  The component behind `Drafter.Prompt.confirm/2`: a yes or no question.

  ## Options

    * `:label` - the question
    * `:default` - the answer Enter gives before any other key. Default `true`

  ## Keys

  `y` answers yes and `n` answers no at once. Left, Right, Up, Down, Tab, `h` and `l`
  switch the highlighted answer and Enter gives it. Esc stops the prompt with
  `:cancelled`.
  """

  @behaviour Drafter.Prompt.Component

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.{Frame, Style}

  defstruct label: "", answer: true

  @switches [:left, :right, :up, :down, :tab, :h, :l]

  @impl true
  def init(opts) do
    %__MODULE__{label: Keyword.get(opts, :label, ""), answer: Keyword.get(opts, :default, true)}
  end

  @impl true
  def handle_event({:key, key}, state) when key in [:y, :Y],
    do: {:done, true, %{state | answer: true}}

  def handle_event({:key, key}, state) when key in [:n, :N],
    do: {:done, false, %{state | answer: false}}

  def handle_event({:key, :enter}, state), do: {:done, state.answer, state}

  def handle_event({:key, key}, state) when key in @switches,
    do: {:cont, %{state | answer: not state.answer}}

  def handle_event({:key, :escape}, state), do: {:stop, :cancelled, state}
  def handle_event(_event, state), do: {:cont, state}

  @impl true
  def render(state, :active, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :accent, Style.symbol(style, :question)),
        Style.segment(style, :strong, " " <> state.label <> " "),
        Style.segment(style, :muted, Style.symbol(style, :prompt) <> " "),
        option("Yes", state.answer, style),
        Style.segment(style, :muted, " / "),
        option("No", not state.answer, style)
      ])
    ])
  end

  def render(state, {:done, answer}, %{style: style}) do
    Frame.new([
      Strip.new([
        Style.segment(style, :success, Style.symbol(style, :done)),
        Style.segment(style, :strong, " " <> state.label <> " "),
        Style.segment(style, :muted, Style.symbol(style, :separator) <> " "),
        Style.segment(style, :plain, word(answer))
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
  def line_prompt(%__MODULE__{label: label, answer: true}), do: [label, " [Y/n]: "]
  def line_prompt(%__MODULE__{label: label, answer: false}), do: [label, " [y/N]: "]

  @impl true
  def parse_line(line, state), do: line |> String.trim() |> String.downcase() |> answer(state)

  defp answer("", state), do: {:ok, state.answer}
  defp answer(yes, _state) when yes in ["y", "yes"], do: {:ok, true}
  defp answer(no, _state) when no in ["n", "no"], do: {:ok, false}
  defp answer(_other, _state), do: {:error, "Answer y or n."}

  defp option(text, true, style), do: Style.segment(style, :accent, text)
  defp option(text, false, style), do: Style.segment(style, :muted, text)

  defp word(true), do: "Yes"
  defp word(false), do: "No"
end
