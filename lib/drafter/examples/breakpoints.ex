defmodule Drafter.Examples.Breakpoints do
  @moduledoc """
  A demonstration of responsive design with breakpoints.

  Shows how the app adapts to different terminal sizes by changing
  the grid layout based on terminal width breakpoints.
  """

  use Drafter.App

  @help_text """
  # Breakpoints

  A demonstration of how to make an app respond to the dimensions of the terminal.

  Try resizing the terminal, then have a look at the source to see how it works!
  """

  @horizontal_breakpoints [
    {0, 1},
    {40, 2},
    {80, 4},
    {120, 6}
  ]

  def mount(_props) do
    %{
      grid_size: 2,
      terminal_width: 80
    }
  end

  def render(_state, rect) do
    grid_size = calculate_grid_size(rect.width)

    placeholders =
      for n <- 1..16 do
        {Drafter.Widget.Placeholder,
         %{
           text: "Placeholder #{n}",
           style: %{fg: {100, 150, 200}},
           padding: 1
         }}
      end

    markdown_strips =
      render_widget(
        {Drafter.Widget.Markdown,
         %{
           content: @help_text,
           padding: 1
         }},
        %{rect | height: 6}
      )

    grid_rect = %{rect | y: 6, height: rect.height - 7}

    grid_strips =
      render_widget(
        {Drafter.Widget.Grid,
         %{
           children: placeholders,
           grid_size: grid_size,
           padding: 1
         }},
        grid_rect
      )

    footer_rect = %{rect | y: rect.height - 1, height: 1}

    footer_strips =
      render_widget(
        {Drafter.Widget.Footer,
         %{
           text:
             "^p palette | Terminal: #{rect.width}x#{rect.height} | Grid: #{grid_size} columns",
           align: :center
         }},
        footer_rect
      )

    markdown_strips ++ grid_strips ++ footer_strips
  end

  def handle_event({:resize, {width, _height}}, state) do
    {:ok, %{state | terminal_width: width}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp calculate_grid_size(width) do
    @horizontal_breakpoints
    |> Enum.reverse()
    |> Enum.find({0, 1}, fn {min_width, _cols} -> width >= min_width end)
    |> elem(1)
  end

  defp render_widget({module, props}, rect) do
    state = module.mount(props)

    case module.render(state, rect) do
      strips when is_list(strips) -> strips
      {:error, _} -> []
    end
  end
end
