Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule SliderDemo do
  use Drafter

  state %{
    cutoff: 0.546,
    resonance: 0.2,
    voices: 4,
    mix: 0.5,
    channels: [0.8, 0.55, 0.35, 0.7],
    renderer: :text
  }

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :r, "renderer" do
    {:ok, %{state | renderer: next_renderer(state.renderer)}}
  end

  def render(state) do
    vertical([
      header("SLIDER — #{state.renderer} renderer"),
      label(""),
      label("Bound to app state", style: %{bold: true, fg: :cyan}),
      slider(bind: :cutoff, label: "cutoff ", precision: 3, renderer: state.renderer),
      slider(bind: :resonance, label: "res    ", precision: 3, renderer: state.renderer),
      label(""),
      label("Stepped, formatted and reported", style: %{bold: true, fg: :cyan}),
      slider(
        bind: :voices,
        label: "voices ",
        min: 1,
        max: 16,
        step: 1,
        renderer: state.renderer
      ),
      slider(
        bind: :mix,
        label: "mix    ",
        format: &"#{round(&1 * 100)}%",
        on_change: :mix_changed,
        renderer: state.renderer
      ),
      slider(label: "locked ", value: 0.35, disabled: true, renderer: state.renderer),
      label(""),
      label("Vertical mixer", style: %{bold: true, fg: :cyan}),
      horizontal(
        Enum.map(Enum.with_index(state.channels), fn {value, index} ->
          slider(
            value,
            label: "ch#{index + 1}",
            orientation: :vertical,
            on_change: {:channel_changed, index},
            renderer: state.renderer,
            width: 8,
            height: 9
          )
        end),
        gap: 2,
        height: 9
      ),
      label(""),
      label(readout(state), style: %{fg: :green}),
      footer(bindings: [{"q", "Quit"}, {"r", "Renderer"}, {"←/→", "Adjust"}, {"drag", "Set"}])
    ])
  end

  def handle_event(:mix_changed, value, state) do
    {:ok, %{state | mix: value}}
  end

  def handle_event({:channel_changed, index}, value, state) do
    {:ok, %{state | channels: List.replace_at(state.channels, index, value)}}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  defp readout(state) do
    faders = Enum.map_join(state.channels, "  ", &:erlang.float_to_binary(&1, decimals: 2))

    "cutoff #{state.cutoff}   res #{state.resonance}   voices #{state.voices}   " <>
      "mix #{round(state.mix * 100)}%   faders #{faders}"
  end

  defp next_renderer(:text), do: :braille
  defp next_renderer(:braille), do: :auto
  defp next_renderer(_renderer), do: :text
end

Drafter.run(SliderDemo)
