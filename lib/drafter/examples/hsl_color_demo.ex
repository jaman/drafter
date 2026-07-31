defmodule Drafter.Examples.HslColorDemo do
  @moduledoc false
  use Drafter.App
  import Drafter.App

  def mount(_props) do
    %{
      hue: 0
    }
  end

  def render(state) do
    vertical([
      header("HSL Color Support Demo", show_clock: true),
      scrollable(
        [
          label("HSL Color Format Support", style: %{fg: {100, 150, 255}, bold: true}),
          label(""),
          label("HSL colors can be specified using hsl(hue, saturation%, lightness%) format:"),
          label(""),
          label("Pure Colors (100% saturation, 50% lightness):",
            style: %{fg: {200, 200, 200}, bold: true}
          ),
          label("  Red: hsl(0, 100%, 50%)", style: %{fg: "hsl(0, 100%, 50%)"}),
          label("  Orange: hsl(30, 100%, 50%)", style: %{fg: "hsl(30, 100%, 50%)"}),
          label("  Yellow: hsl(60, 100%, 50%)", style: %{fg: "hsl(60, 100%, 50%)"}),
          label("  Lime: hsl(90, 100%, 50%)", style: %{fg: "hsl(90, 100%, 50%)"}),
          label("  Green: hsl(120, 100%, 50%)", style: %{fg: "hsl(120, 100%, 50%)"}),
          label("  Teal: hsl(150, 100%, 50%)", style: %{fg: "hsl(150, 100%, 50%)"}),
          label("  Cyan: hsl(180, 100%, 50%)", style: %{fg: "hsl(180, 100%, 50%)"}),
          label("  Sky: hsl(210, 100%, 50%)", style: %{fg: "hsl(210, 100%, 50%)"}),
          label("  Blue: hsl(240, 100%, 50%)", style: %{fg: "hsl(240, 100%, 50%)"}),
          label("  Purple: hsl(270, 100%, 50%)", style: %{fg: "hsl(270, 100%, 50%)"}),
          label("  Magenta: hsl(300, 100%, 50%)", style: %{fg: "hsl(300, 100%, 50%)"}),
          label("  Pink: hsl(330, 100%, 50%)", style: %{fg: "hsl(330, 100%, 50%)"}),
          label(""),
          label("Pastel Colors (60% saturation, 70% lightness):",
            style: %{fg: {200, 200, 200}, bold: true}
          ),
          label("  Pastel Red", style: %{fg: "hsl(0, 60%, 70%)", bg: "hsl(0, 60%, 30%)"}),
          label("  Pastel Orange", style: %{fg: "hsl(30, 60%, 70%)", bg: "hsl(30, 60%, 30%)"}),
          label("  Pastel Yellow", style: %{fg: "hsl(60, 60%, 70%)", bg: "hsl(60, 60%, 30%)"}),
          label("  Pastel Green", style: %{fg: "hsl(120, 60%, 70%)", bg: "hsl(120, 60%, 30%)"}),
          label("  Pastel Cyan", style: %{fg: "hsl(180, 60%, 70%)", bg: "hsl(180, 60%, 30%)"}),
          label("  Pastel Blue", style: %{fg: "hsl(240, 60%, 70%)", bg: "hsl(240, 60%, 30%)"}),
          label("  Pastel Magenta", style: %{fg: "hsl(300, 60%, 70%)", bg: "hsl(300, 60%, 30%)"}),
          label(""),
          label("Muted Colors (40% saturation, 50% lightness):",
            style: %{fg: {200, 200, 200}, bold: true}
          ),
          label("  Muted Red", style: %{fg: "hsl(0, 40%, 50%)", bg: "hsl(0, 10%, 20%)"}),
          label("  Muted Orange", style: %{fg: "hsl(30, 40%, 50%)", bg: "hsl(30, 10%, 20%)"}),
          label("  Muted Yellow", style: %{fg: "hsl(60, 40%, 50%)", bg: "hsl(60, 10%, 20%)"}),
          label("  Muted Green", style: %{fg: "hsl(120, 40%, 50%)", bg: "hsl(120, 10%, 20%)"}),
          label("  Muted Cyan", style: %{fg: "hsl(180, 40%, 50%)", bg: "hsl(180, 10%, 20%)"}),
          label("  Muted Blue", style: %{fg: "hsl(240, 40%, 50%)", bg: "hsl(240, 10%, 20%)"}),
          label("  Muted Magenta", style: %{fg: "hsl(300, 40%, 50%)", bg: "hsl(300, 10%, 20%)"}),
          label(""),
          label("Grayscale (0% saturation):", style: %{fg: {200, 200, 200}, bold: true}),
          label("  Black: hsl(0, 0%, 0%)",
            style: %{fg: "hsl(0, 0%, 100%)", bg: "hsl(0, 0%, 0%)"}
          ),
          label("  Dark Gray: hsl(0, 0%, 25%)",
            style: %{fg: "hsl(0, 0%, 100%)", bg: "hsl(0, 0%, 25%)"}
          ),
          label("  Mid Gray: hsl(0, 0%, 50%)",
            style: %{fg: "hsl(0, 0%, 100%)", bg: "hsl(0, 0%, 50%)"}
          ),
          label("  Light Gray: hsl(0, 0%, 75%)",
            style: %{fg: "hsl(0, 0%, 0%)", bg: "hsl(0, 0%, 75%)"}
          ),
          label("  White: hsl(0, 0%, 100%)",
            style: %{fg: "hsl(0, 0%, 0%)", bg: "hsl(0, 0%, 100%)"}
          ),
          label(""),
          label("Dynamic Hue Demo (changes on timer):",
            style: %{fg: {200, 200, 200}, bold: true}
          ),
          label("  Current Hue: #{state.hue}°",
            style: %{fg: "hsl(#{state.hue}, 80%, 60%)", bold: true}
          ),
          label("  Complementary: hsl(#{rem(state.hue + 180, 360)}, 80%, 60%)",
            style: %{fg: "hsl(#{rem(state.hue + 180, 360)}, 80%, 60%)", bold: true}
          ),
          label("  Triadic 1: hsl(#{rem(state.hue + 120, 360)}, 80%, 60%)",
            style: %{fg: "hsl(#{rem(state.hue + 120, 360)}, 80%, 60%)", bold: true}
          ),
          label("  Triadic 2: hsl(#{rem(state.hue + 240, 360)}, 80%, 60%)",
            style: %{fg: "hsl(#{rem(state.hue + 240, 360)}, 80%, 60%)", bold: true}
          ),
          label(""),
          label("Also supports RGB, hex, and HSLA with alpha channel"),
          label("  rgb(255, 100, 50)", style: %{fg: "rgb(255, 100, 50)"}),
          label("  #FF6432", style: %{fg: "#FF6432"}),
          label("  hsla(200, 80%, 60%, 0.5)", style: %{fg: "hsla(200, 80%, 60%, 0.9)"})
        ],
        flex: 1
      ),
      footer(bindings: [{"Ctrl+Q", "Quit"}])
    ])
  end

  def handle_event(:on_timer, state) do
    new_hue = rem(state.hue + 5, 360)
    {:noreply, %{state | hue: new_hue}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  def on_mount(app_state) do
    Process.send_after(self(), {:timer, :on_timer}, 100)
    app_state
  end
end
