Mix.install([{:drafter, path: Path.join(__DIR__, "..")}])

defmodule HslColors do
  use Drafter.App
  import Drafter.App

  def mount(_props), do: %{hue: 0}

  def keybindings, do: [{"q", "quit"}]

  def on_ready(state) do
    Drafter.set_interval(100, :tick)
    state
  end

  def on_timer(:tick, state), do: %{state | hue: rem(state.hue + 5, 360)}

  def render(state) do
    vertical([
      header("HSL Color Demo", show_clock: true),
      scrollable(
        [
          label("Pure Colors (hsl(h, 100%, 50%)):", style: %{bold: true}),
          label("  Red", style: %{fg: "hsl(0, 100%, 50%)"}),
          label("  Orange", style: %{fg: "hsl(30, 100%, 50%)"}),
          label("  Yellow", style: %{fg: "hsl(60, 100%, 50%)"}),
          label("  Green", style: %{fg: "hsl(120, 100%, 50%)"}),
          label("  Cyan", style: %{fg: "hsl(180, 100%, 50%)"}),
          label("  Blue", style: %{fg: "hsl(240, 100%, 50%)"}),
          label("  Magenta", style: %{fg: "hsl(300, 100%, 50%)"}),
          label(""),
          label("Pastel Colors (60% saturation, 70% lightness):", style: %{bold: true}),
          label("  Pastel Red", style: %{fg: "hsl(0, 60%, 70%)", bg: "hsl(0, 60%, 30%)"}),
          label("  Pastel Orange", style: %{fg: "hsl(30, 60%, 70%)", bg: "hsl(30, 60%, 30%)"}),
          label("  Pastel Yellow", style: %{fg: "hsl(60, 60%, 70%)", bg: "hsl(60, 60%, 30%)"}),
          label("  Pastel Green", style: %{fg: "hsl(120, 60%, 70%)", bg: "hsl(120, 60%, 30%)"}),
          label("  Pastel Cyan", style: %{fg: "hsl(180, 60%, 70%)", bg: "hsl(180, 60%, 30%)"}),
          label("  Pastel Blue", style: %{fg: "hsl(240, 60%, 70%)", bg: "hsl(240, 60%, 30%)"}),
          label("  Pastel Magenta", style: %{fg: "hsl(300, 60%, 70%)", bg: "hsl(300, 60%, 30%)"}),
          label(""),
          label("Grayscale (0% saturation):", style: %{bold: true}),
          label("  Black", style: %{fg: "hsl(0, 0%, 100%)", bg: "hsl(0, 0%, 0%)"}),
          label("  Dark Gray", style: %{fg: "hsl(0, 0%, 100%)", bg: "hsl(0, 0%, 25%)"}),
          label("  Mid Gray", style: %{fg: "hsl(0, 0%, 0%)", bg: "hsl(0, 0%, 50%)"}),
          label("  Light Gray", style: %{fg: "hsl(0, 0%, 0%)", bg: "hsl(0, 0%, 75%)"}),
          label("  White", style: %{fg: "hsl(0, 0%, 0%)", bg: "hsl(0, 0%, 100%)"}),
          label(""),
          label("Dynamic hue (timer):", style: %{bold: true}),
          label("  Current hue: #{state.hue}°",
            style: %{fg: "hsl(#{state.hue}, 80%, 60%)", bold: true}
          ),
          label("  Complementary: #{rem(state.hue + 180, 360)}°",
            style: %{fg: "hsl(#{rem(state.hue + 180, 360)}, 80%, 60%)", bold: true}
          ),
          label("  Triadic 1: #{rem(state.hue + 120, 360)}°",
            style: %{fg: "hsl(#{rem(state.hue + 120, 360)}, 80%, 60%)", bold: true}
          ),
          label("  Triadic 2: #{rem(state.hue + 240, 360)}°",
            style: %{fg: "hsl(#{rem(state.hue + 240, 360)}, 80%, 60%)", bold: true}
          ),
          label(""),
          label("Also supported: rgb(255,100,50), #FF6432, hsla(200,80%,60%,0.9)"),
          label("  rgb(255, 100, 50)", style: %{fg: "rgb(255, 100, 50)"}),
          label("  #FF6432", style: %{fg: "#FF6432"}),
          label("  hsla(200, 80%, 60%, 0.9)", style: %{fg: "hsla(200, 80%, 60%, 0.9)"})
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event({:key, :q}, _state), do: {:stop, :normal}
  def handle_event(_event, state), do: {:noreply, state}
end

Drafter.run(HslColors)
