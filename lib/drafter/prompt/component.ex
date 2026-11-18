defmodule Drafter.Prompt.Component do
  @moduledoc """
  Behaviour for one prompt: state, the keys that change it, and how it is drawn.

  `Drafter.Prompt.run/2` runs a component. It calls `c:init/1` once, then draws
  `c:render/3` and passes each event to `c:handle_event/2` until the component is done
  or stops. `Ctrl+C` never reaches the component; it stops the prompt with
  `:interrupted`.

      defmodule Rating do
        @behaviour Drafter.Prompt.Component

        alias Drafter.Draw.Strip
        alias Drafter.Prompt.Frame

        @impl true
        def init(opts), do: %{label: Keyword.fetch!(opts, :label), stars: 3}

        @impl true
        def handle_event({:key, :right}, state), do: {:cont, %{state | stars: min(state.stars + 1, 5)}}
        def handle_event({:key, :left}, state), do: {:cont, %{state | stars: max(state.stars - 1, 1)}}
        def handle_event({:key, :enter}, state), do: {:done, state.stars, state}
        def handle_event({:key, :escape}, state), do: {:stop, :cancelled, state}
        def handle_event(_event, state), do: {:cont, state}

        @impl true
        def render(state, _status, _context) do
          Frame.new([Strip.from_text(state.label <> " " <> String.duplicate("★", state.stars))])
        end
      end

      {:ok, stars} = Drafter.Prompt.run(Rating, label: "Rate it")

  ## Line input

  When standard input is not a terminal a prompt cannot be drawn, and the component is
  asked through `c:line_prompt/1` and `c:parse_line/2` instead: the question is
  written, one line is read, and a rejected line is asked for again. A component
  without these two callbacks returns `{:error, :not_a_terminal}` there.
  """

  alias Drafter.Prompt.{Frame, Style, Terminal}

  @type state :: term()

  @typedoc """
  Why `c:render/3` is being called: the prompt is waiting for keys, it finished with a
  value, or it stopped without one.
  """
  @type status :: :active | {:done, term()} | {:stopped, stop_reason()}

  @typedoc """
  Why a prompt ended without a value: `Esc`, `Ctrl+C`, or the end of input
  (`Ctrl+D` on an empty line, or standard input closing).
  """
  @type stop_reason :: :cancelled | :interrupted | :eof

  @typedoc """
  What `c:render/3` may draw into. `width` is the widest a line can be and `rows` the
  most lines a frame can have.
  """
  @type context :: %{width: pos_integer(), rows: pos_integer(), style: Style.t()}

  @doc "The component's starting state, from the options given to `Drafter.Prompt.run/2`."
  @callback init(keyword()) :: state()

  @doc """
  Apply one event.

  `{:cont, state}` keeps the prompt open, `{:done, value, state}` finishes it with
  `value`, and `{:stop, reason, state}` ends it without one.
  """
  @callback handle_event(Terminal.event(), state()) ::
              {:cont, state()} | {:done, term(), state()} | {:stop, stop_reason(), state()}

  @doc """
  The frame to show for `state`.

  Called with `:active` after every event, and once with the outcome when the prompt
  ends; that last frame stays on screen.
  """
  @callback render(state(), status(), context()) :: Frame.t()

  @doc "The question as one line of text, written before a line is read."
  @callback line_prompt(state()) :: iodata()

  @doc """
  Turn a line read from standard input into the prompt's value.

  `line` has no trailing line break. `{:error, message}` writes `message` and asks
  again.
  """
  @callback parse_line(String.t(), state()) :: {:ok, term()} | {:error, String.t()}

  @optional_callbacks line_prompt: 1, parse_line: 2
end
