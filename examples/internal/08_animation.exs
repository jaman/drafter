Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}])

defmodule Animation do
  use Drafter.App
  import Drafter.App

  @colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100},
    {255, 100, 255},
    {100, 255, 255}
  ]
  @color_names ["Red", "Green", "Blue", "Yellow", "Magenta", "Cyan"]

  def mount(_props), do: %{color_index: 0, mode: :static, tick: 0}

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  def on_ready(state) do
    Drafter.set_interval(24, :fps)
    state
  end

  def on_timer(:fps, state), do: %{state | tick: state.tick + 1}

  def render(state) do
    current_color = Enum.at(@colors, state.color_index)
    color_name = Enum.at(@color_names, state.color_index)
    {opacity, display_color} = compute_animation(state, current_color)

    vertical([
      header("Animation Demo", show_clock: true),
      scrollable(
        [
          label(""),
          horizontal([
            label("Color: ", style: %{bold: true}),
            label(color_name, style: %{color: current_color, bold: true})
          ]),
          horizontal([
            label("Mode: ", style: %{bold: true}),
            label(mode_name(state.mode), style: %{color: :accent})
          ]),
          horizontal([
            label("Opacity: ", style: %{bold: true}),
            label("#{Float.round(opacity, 2)}", style: %{color: :success})
          ]),
          label(""),
          rule(),
          label(""),
          horizontal([
            card(
              ["Color: #{color_name}", "Opacity: #{Float.round(opacity, 2)}"],
              title: "CSS Style",
              border_color: current_color,
              background: display_color
            ),
            label("  "),
            card(
              ["Color: #{color_name}", "Opacity: #{Float.round(opacity, 2)}"],
              title: "Alias Style",
              border_color: current_color,
              background: display_color
            )
          ]),
          label(""),
          rule(),
          label(""),
          horizontal(
            [
              button("Static", on_click: {:set_mode, :static}),
              button("Pulse", on_click: {:set_mode, :pulse}),
              button("Rainbow", on_click: {:set_mode, :rainbow})
            ],
            gap: 1
          ),
          label(""),
          horizontal(
            [
              button("Prev Color", on_click: :prev_color),
              button("Next Color", on_click: :next_color)
            ],
            gap: 1
          )
        ],
        flex: 1
      ),
      footer()
    ])
  end

  def handle_event({:set_mode, mode}, _data, state), do: {:ok, %{state | mode: mode, tick: 0}}

  def handle_event(:prev_color, _data, state) do
    idx = if state.color_index == 0, do: length(@colors) - 1, else: state.color_index - 1
    {:ok, %{state | color_index: idx}}
  end

  def handle_event(:next_color, _data, state) do
    {:ok, %{state | color_index: rem(state.color_index + 1, length(@colors))}}
  end

  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event({:key, k}, state) when k in ~w(1 2 3 4 5 6)a do
    {:ok, %{state | color_index: Atom.to_string(k) |> String.to_integer() |> Kernel.-(1)}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp compute_animation(%{mode: :pulse, tick: tick}, color) do
    op = 0.3 + 0.7 * (:math.sin(tick / 15) + 1) / 2
    {op, blend_color({30, 30, 40}, color, op)}
  end

  defp compute_animation(%{mode: :rainbow, tick: tick}, _color) do
    idx = rem(div(tick, 10), length(@colors))
    {1.0, Enum.at(@colors, idx)}
  end

  defp compute_animation(_state, color), do: {1.0, color}

  defp mode_name(:static), do: "Static"
  defp mode_name(:pulse), do: "Pulsing"
  defp mode_name(:rainbow), do: "Rainbow"

  defp blend_color({r1, g1, b1}, {r2, g2, b2}, opacity) do
    {round(r1 + (r2 - r1) * opacity), round(g1 + (g2 - g1) * opacity),
     round(b1 + (b2 - b1) * opacity)}
  end
end

Drafter.run(Animation)
