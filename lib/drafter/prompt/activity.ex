defmodule Drafter.Prompt.Activity do
  @moduledoc false

  alias Drafter.Draw.Strip
  alias Drafter.Prompt.{Capture, Frame, Runner, Style, Terminal}

  @bar_width 24

  @type t :: pid()

  @doc """
  Run `work` in the calling process while a line showing `label` is kept moving on
  the terminal, and return what `work` returns.

  `work` receives the activity, to pass to `label/2` and `advance/2`. Text the calling
  process writes meanwhile is shown above the line. The line ends with a done mark
  when `work` returns and a failed mark when it raises, exits or throws, which is then
  passed on.

  ## Options

    * `:total` - the number of steps, which makes the line a progress bar
    * `:interval` - milliseconds between redraws. Default
      `config :drafter, prompt_interval: 80`
    * `:style` - overrides for `Drafter.Prompt.Style.current/1`
  """
  @spec run(String.t(), keyword(), (t() -> result)) :: result when result: var
  def run(label, opts, work) when is_function(work, 1) do
    activity = start(label, opts)
    capture = Capture.start(activity)

    try do
      work.(activity)
    catch
      kind, reason ->
        stop(activity, capture, :failed)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        stop(activity, capture, :done)
        result
    end
  end

  @doc "Change the text shown on the activity's line."
  @spec label(t(), String.t()) :: :ok
  def label(activity, text) do
    send(activity, {:label, text})
    :ok
  end

  @doc "Count `steps` more steps as done."
  @spec advance(t(), number()) :: :ok
  def advance(activity, steps \\ 1) do
    send(activity, {:advance, steps})
    :ok
  end

  defp start(label, opts) do
    scripted = Runner.scripted()
    style = Style.current(Keyword.get(opts, :style, []))
    interval = Keyword.get(opts, :interval, Application.get_env(:drafter, :prompt_interval, 80))

    spawn_link(fn ->
      loop(
        draw(%{
          terminal: scripted || Runner.open(input: false),
          label: label,
          total: Keyword.get(opts, :total),
          done: 0,
          tick: 0,
          style: style,
          interval: interval,
          due: now() + interval,
          partial: ""
        })
      )
    end)
  end

  defp stop(activity, capture, outcome) do
    Capture.release(capture)
    reference = Process.monitor(activity)
    send(activity, {:stop, outcome, self(), reference})

    receive do
      {^reference, :stopped} -> Process.demonitor(reference, [:flush])
      {:DOWN, ^reference, :process, _pid, _reason} -> :ok
    end
  end

  defp loop(state) do
    receive do
      {:label, text} -> loop(%{state | label: text})
      {:advance, steps} -> loop(%{state | done: state.done + steps})
      {:output, text} -> loop(output(state, text))
      {:stop, outcome, from, reference} -> finish(state, outcome, from, reference)
    after
      max(state.due - now(), 0) ->
        loop(draw(%{state | tick: state.tick + 1, due: now() + state.interval}))
    end
  end

  defp finish(state, outcome, from, reference) do
    state = flush(state)
    terminal = Terminal.commit(state.terminal, ended(state, outcome))
    Terminal.close(terminal)
    send(from, {reference, :stopped})
  end

  defp draw(state), do: %{state | terminal: Terminal.draw(state.terminal, moving(state))}

  defp output(state, text) do
    case split_lines(state.partial <> text) do
      {"", partial} ->
        %{state | partial: partial}

      {lines, partial} ->
        draw(%{state | terminal: Terminal.print(state.terminal, lines), partial: partial})
    end
  end

  defp flush(%{partial: ""} = state), do: state

  defp flush(state),
    do: %{state | terminal: Terminal.print(state.terminal, state.partial <> "\n"), partial: ""}

  defp split_lines(text) do
    case :binary.matches(text, "\n") do
      [] ->
        {"", text}

      breaks ->
        {position, 1} = List.last(breaks)

        {binary_part(text, 0, position + 1),
         binary_part(text, position + 1, byte_size(text) - position - 1)}
    end
  end

  defp moving(%{style: style} = state) do
    strip =
      Strip.new(
        [
          Style.segment(style, :accent, Style.spinner(style, state.tick)),
          Style.segment(style, :plain, " " <> state.label)
        ] ++ bar(state)
      )

    Frame.new([strip], {0, Strip.width(strip)})
  end

  defp ended(%{style: style} = state, :done) do
    Frame.new([
      Strip.new(
        [
          Style.segment(style, :success, Style.symbol(style, :done)),
          Style.segment(style, :plain, " " <> state.label)
        ] ++ count(state)
      )
    ])
  end

  defp ended(%{style: style} = state, :failed) do
    Frame.new([
      Strip.new([
        Style.segment(style, :error, Style.symbol(style, :failed)),
        Style.segment(style, :plain, " " <> state.label)
      ])
    ])
  end

  defp bar(%{total: nil}), do: []

  defp bar(%{style: style} = state) do
    share = share(state)
    full = round(share * @bar_width)

    [
      Style.segment(style, :plain, " "),
      Style.segment(style, :accent, String.duplicate(Style.symbol(style, :bar_full), full)),
      Style.segment(
        style,
        :muted,
        String.duplicate(Style.symbol(style, :bar_empty), @bar_width - full)
      ),
      Style.segment(style, :plain, " #{round(share * 100)}%")
    ] ++ count(state)
  end

  defp count(%{total: nil}), do: []

  defp count(%{style: style} = state),
    do: [Style.segment(style, :muted, " #{shown(state.done)}/#{shown(state.total)}")]

  defp share(%{total: total}) when total <= 0, do: 1.0
  defp share(%{done: done, total: total}), do: (done / total) |> max(0.0) |> min(1.0)

  defp shown(number) when is_integer(number), do: Integer.to_string(number)
  defp shown(number), do: :erlang.float_to_binary(number * 1.0, decimals: 1)

  defp now, do: System.monotonic_time(:millisecond)
end
