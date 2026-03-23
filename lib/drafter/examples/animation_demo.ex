defmodule Drafter.Examples.AnimationDemo do
  @moduledoc false
  use Drafter.App

  def mount(_props) do
    %{
      color_index: 0,
      mode: :static,
      tick: 0
    }
  end

  @colors [
    {255, 100, 100},
    {100, 255, 100},
    {100, 100, 255},
    {255, 255, 100},
    {255, 100, 255},
    {100, 255, 255}
  ]

  @color_names ["Red", "Green", "Blue", "Yellow", "Magenta", "Cyan"]

  def render(state) do
    current_color = Enum.at(@colors, state.color_index, {255, 255, 255})
    color_name = Enum.at(@color_names, state.color_index, "White")

    {opacity, display_color} = compute_animation(state, current_color)
    text_fg = text_color(display_color)

    vertical([
      header("Animation Demo", show_clock: true),
      vertical(
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
            label(Float.round(opacity, 2) |> to_string(), style: %{color: :success})
          ]),
          label("Tick: " <> to_string(state.tick)),
          label(""),
          rule(),
          label(""),
          horizontal([
            render_css_box(current_color, display_color, color_name, opacity, text_fg),
            label("  "),
            render_alias_box(current_color, display_color, color_name, opacity, text_fg)
          ]),
          label(""),
          rule(),
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
          ),
          label(""),
          rule(),
          label("Press 1-6 for colors, Q to quit")
        ],
        flex: 1
      ),
      footer(bindings: [{"q", "Quit"}])
    ])
  end

  defp render_css_box(current_color, display_color, color_name, opacity, _text_fg) do
    card(
      ["Color: #{color_name}", "Opacity: #{Float.round(opacity, 2)}"],
      title: "CSS Style (color/bg)",
      border_color: current_color,
      background: display_color
    )
  end

  defp render_alias_box(current_color, display_color, color_name, opacity, _text_fg) do
    card(
      ["Color: #{color_name}", "Opacity: #{Float.round(opacity, 2)}"],
      title: "Alias Style (fg/bg)",
      border_color: current_color,
      background: display_color
    )
  end

  defp compute_animation(state, current_color) do
    case state.mode do
      :pulse ->
        op = 0.3 + 0.7 * (:math.sin(state.tick / 15) + 1) / 2
        {op, blend_color({30, 30, 40}, current_color, op)}

      :rainbow ->
        idx = rem(div(state.tick, 10), length(@colors))
        col = Enum.at(@colors, idx)
        {1.0, col}

      _ ->
        {1.0, current_color}
    end
  end

  defp mode_name(:static), do: "Static"
  defp mode_name(:pulse), do: "Pulsing"
  defp mode_name(:rainbow), do: "Rainbow"

  defp blend_color({r1, g1, b1}, {r2, g2, b2}, opacity) do
    {
      round(r1 + (r2 - r1) * opacity),
      round(g1 + (g2 - g1) * opacity),
      round(b1 + (b2 - b1) * opacity)
    }
  end

  defp text_color({r, g, b}) do
    luminance = 0.299 * r + 0.587 * g + 0.114 * b
    if luminance > 128, do: {0, 0, 0}, else: {255, 255, 255}
  end

  def on_ready(state) do
    Drafter.set_interval(33, :anim_tick)
    state
  end

  def on_timer(:anim_tick, state) do
    %{state | tick: state.tick + 1}
  end

  def handle_event(event, state) do
    case event do
      {:key, :q, [:ctrl]} ->
        {:stop, :normal}

      {:key, :q} ->
        {:stop, :normal}

      {:key, key} when key in [?1, ?2, ?3, ?4, ?5, ?6] ->
        {:ok, %{state | color_index: key - ?1}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_event({:set_mode, mode}, _data, state) do
    {:ok, %{state | mode: mode, tick: 0}}
  end

  def handle_event(:prev_color, _data, state) do
    idx = if state.color_index == 0, do: length(@colors) - 1, else: state.color_index - 1
    {:noreply, %{state | color_index: idx}}
  end

  def handle_event(:next_color, _data, state) do
    idx = rem(state.color_index + 1, length(@colors))
    {:noreply, %{state | color_index: idx}}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}
end
