Mix.install([{:drafter, path: Path.join(__DIR__, "../..")}, {:french_curve, github: "jaman/french_curve"}, {:elixir_make, "~> 0.9"}, {:spark, "~> 2.6"}], consolidate_protocols: false)

defmodule FontCatalogue do
  use Drafter

  alias Drafter.Widget.Digits.{Figlet, Font, Image}

  @left_width 24
  @panel_gap 2
  @chrome_reserve 3
  @sample "Drafter 42"

  def mount(_props) do
    Figlet.register_bundled()
    {width, _height} = Drafter.Compositor.get_screen_size()

    %{
      selected_font: List.first(font_names()),
      terminal_width: width,
      renderer: :text,
      protocol: Image.protocol(:auto)
    }
  end

  keybinding :q, "quit" do
    {:stop, :normal}
  end

  keybinding :g, "toggle graphics" do
    {:ok, %{state | renderer: toggle(state.renderer)}}
  end

  def render(state) do
    vertical([
      header("Font Catalogue — #{renderer_label(state)}"),
      horizontal(
        [
          vertical(
            [
              option_list(
                Enum.map(font_names(), &{humanize(&1), &1}),
                on_select: :font_selected,
                on_highlight: :font_highlighted,
                selected: state.selected_font
              )
            ],
            width: @left_width
          ),
          scrollable(font_detail(state), flex: 1)
        ],
        flex: 1,
        gap: @panel_gap
      ),
      footer()
    ])
  end

  def handle_event(:font_selected, name, state), do: {:ok, %{state | selected_font: name}}
  def handle_event(:font_highlighted, name, state), do: {:ok, %{state | selected_font: name}}
  def handle_event(_widget_event, _data, state), do: {:noreply, state}

  def handle_event({:resize, {width, _height}}, state) do
    {:ok, %{state | terminal_width: width}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp font_names, do: Font.names()

  defp toggle(:text), do: :graphics
  defp toggle(_graphics), do: :text

  defp renderer_label(%{renderer: :text}), do: "cells   (press g for graphics)"

  defp renderer_label(%{protocol: nil}),
    do: "graphics requested — no pixel protocol detected, still drawing cells"

  defp renderer_label(%{protocol: protocol}), do: "graphics via #{protocol}   (press g for cells)"

  defp font_detail(state) do
    name = state.selected_font
    {digit_chars, letter_chars, other_chars} = partition_repertoire(Font.repertoire(name))

    [
      label(heading(name), style: %{bold: true, fg: :cyan}),
      label(""),
      rule(title: "Sample", title_align: :left),
      digits(@sample, font: name, renderer: state.renderer),
      label(""),
      rule(title: "Digits", title_align: :left),
      wrapped_digits(digit_chars, name, state),
      label(""),
      rule(title: "Alphabet", title_align: :left),
      wrapped_digits(letter_chars, name, state),
      label(""),
      rule(title: "Punctuation", title_align: :left),
      wrapped_digits(other_chars, name, state)
    ]
  end

  defp heading(name) do
    "#{humanize(name)}  (#{Font.height(name)} rows, widest glyph #{Font.width(name)})"
  end

  defp partition_repertoire(repertoire) do
    digit_chars = Enum.filter(repertoire, &digit?/1)
    letter_chars = Enum.filter(repertoire, &letter?/1)
    other_chars = repertoire -- (digit_chars ++ letter_chars ++ [" "])

    {digit_chars, letter_chars, other_chars}
  end

  defp wrapped_digits(chars, name, state) do
    chars
    |> pack_rows(name, available_width(state.terminal_width))
    |> Enum.map(&digits(&1, font: name, renderer: state.renderer))
    |> vertical()
  end

  defp pack_rows(chars, name, available) do
    chars
    |> Enum.reduce({[], "", 0}, fn character, {rows, current, used} ->
      width = Font.glyph_width(name, character)

      if used + width > available and current != "" do
        {[current | rows], character, width}
      else
        {rows, current <> character, used + width}
      end
    end)
    |> close_rows()
  end

  defp close_rows({rows, "", _used}), do: Enum.reverse(rows)
  defp close_rows({rows, current, _used}), do: Enum.reverse([current | rows])

  defp available_width(terminal_width) do
    max(terminal_width - @left_width - @panel_gap - @chrome_reserve, 1)
  end

  defp digit?(character), do: character =~ ~r/^[0-9]$/
  defp letter?(character), do: character =~ ~r/^[A-Za-z]$/

  defp humanize(name) do
    name
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

Drafter.run(FontCatalogue)
