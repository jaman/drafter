defmodule Drafter.Widget.CommandPalette do
  @moduledoc """
  A modal command palette overlay with incremental search and keyboard-driven selection.

  When `:visible` is `true`, the palette renders as a centred modal (60% width, 50% height)
  over a dimmed overlay. A query input at the top filters the command list by name as the
  user types. Up to 8 matching commands are shown at a time.

  Selecting a command via Enter emits an `{:action, atom}` tuple that the app's
  `handle_event/3` can pattern-match on. Built-in action atoms are `:toggle_theme`,
  `:quit_application`, `:show_help`, `:refresh_screen`, `:show_about`, and
  `:show_settings`. Pressing Escape or `q` closes the palette.

  ## Options

    * `:visible` - whether to render the overlay (default: `false`)
    * `:query` - initial filter string (default: `""`)
    * `:commands` - list of `{name, description}` tuples; defaults to the built-in command list
    * `:selected_index` - initially highlighted command index (default: `0`)
    * `:style` - map of base style overrides

  ## Key bindings

    * `↑` / `↓` — move selection
    * `Enter` — execute selected command
    * `Escape` / `q` — close without executing

  ## Usage

      command_palette(visible: true, commands: [{"Open file", "Browse and open a file"}])
  """

  use Drafter.Widget,
    handles: [:keyboard],
    focusable: true

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  def mount(props) do
    %{
      query: Map.get(props, :query, ""),
      commands: Map.get(props, :commands, default_commands()),
      selected_index: Map.get(props, :selected_index, 0),
      visible: Map.get(props, :visible, false),
      style: Map.get(props, :style, %{fg: {255, 255, 255}, bg: {40, 40, 40}})
    }
  end

  def render(state, rect) do
    if state.visible do
      render_command_palette(state, rect)
    else
      []
    end
  end

  def update(props, state) do
    Map.merge(state, props)
  end

  @command_actions %{
    "Toggle theme" => :toggle_theme,
    "Quit application" => :quit_application,
    "Show help" => :show_help,
    "Refresh screen" => :refresh_screen,
    "About" => :show_about,
    "Settings" => :show_settings
  }

  def handle_event({:key, :up}, state), do: {:ok, %{state | selected_index: max(0, state.selected_index - 1)}}

  def handle_event({:key, :down}, state) do
    {:ok, %{state | selected_index: min(length(state.commands) - 1, state.selected_index + 1)}}
  end

  def handle_event({:key, :enter}, state) do
    case Enum.at(state.commands, state.selected_index) do
      {name, _} -> Map.get(@command_actions, name, :close) |> wrap_action()
      _ -> {:close}
    end
  end

  def handle_event({:key, key}, _state) when key in [:escape, :q], do: {:close}
  def handle_event(_, state), do: {:noreply, state}

  defp wrap_action(:close), do: {:close}
  defp wrap_action(action), do: {:action, action}

  defp render_command_palette(state, rect) do
    # Calculate modal size (centered, 60% width, 50% height)
    modal_width = div(rect.width * 6, 10)
    modal_height = div(rect.height, 2)
    modal_x = div(rect.width - modal_width, 2)
    modal_y = div(rect.height - modal_height, 2)

    # Create overlay strips with modal content positioned correctly
    create_combined_overlay(state, rect, modal_x, modal_y, modal_width, modal_height)
  end

  defp create_combined_overlay(state, rect, modal_x, modal_y, modal_width, modal_height) do
    overlay_computed = Computed.for_part(:command_palette, state, :overlay)
    overlay_style = Computed.to_segment_style(overlay_computed)
    modal_content = create_modal_content_strips(state, modal_width, modal_height)
    empty_strip = Strip.new([Segment.new(String.duplicate(" ", rect.width), overlay_style)])

    Enum.map(0..(rect.height - 1), fn y ->
      render_overlay_row(y, modal_y, modal_height, modal_content, modal_x, rect.width, overlay_style, empty_strip)
    end)
  end

  defp render_overlay_row(y, modal_y, modal_height, modal_content, modal_x, screen_width, overlay_style, empty_strip) do
    modal_line_index = y - modal_y

    if y >= modal_y and y < modal_y + modal_height and modal_line_index < length(modal_content) do
      modal_strip = Enum.at(modal_content, modal_line_index)
      create_positioned_modal_strip(modal_strip, modal_x, screen_width, overlay_style)
    else
      empty_strip
    end
  end

  defp create_positioned_modal_strip(modal_strip, modal_x, screen_width, overlay_style) do
    # Create left padding (overlay background)
    left_padding =
      if modal_x > 0 do
        Segment.new(String.duplicate(" ", modal_x), overlay_style)
      else
        nil
      end

    # Get modal strip width
    modal_width = Strip.width(modal_strip)

    # Create right padding (overlay background)
    right_padding_width = screen_width - modal_x - modal_width

    right_padding =
      if right_padding_width > 0 do
        Segment.new(String.duplicate(" ", right_padding_width), overlay_style)
      else
        nil
      end

    # Combine segments
    segments = []
    segments = if left_padding, do: segments ++ [left_padding], else: segments
    segments = segments ++ modal_strip.segments
    segments = if right_padding, do: segments ++ [right_padding], else: segments

    Strip.new(segments)
  end

  defp create_modal_content_strips(state, width, _height) do
    computed = Computed.for_widget(:command_palette, state)
    modal_style = Computed.to_segment_style(computed)

    border_computed = Computed.for_part(:command_palette, state, :border)
    border_style = Computed.to_segment_style(border_computed)

    input_computed = Computed.for_part(:command_palette, state, :input)
    input_style = Computed.to_segment_style(input_computed)

    strips = []

    top_border = "┌" <> String.duplicate("─", width - 2) <> "┐"
    strips = strips ++ [create_modal_strip(top_border, 0, border_style)]

    title = "│ Command Palette" <> String.duplicate(" ", width - 18) <> "│"
    strips = strips ++ [create_modal_strip(title, 0, modal_style)]

    separator = "├" <> String.duplicate("─", width - 2) <> "┤"
    strips = strips ++ [create_modal_strip(separator, 0, border_style)]

    query_text =
      "│ > " <>
        state.query <> String.duplicate(" ", width - 6 - String.length(state.query)) <> "│"

    strips = strips ++ [create_modal_strip(query_text, 0, input_style)]

    strips = strips ++ [create_modal_strip(separator, 0, border_style)]

    filtered_commands = filter_commands(state.commands, state.query)

    command_strips =
      create_command_list(filtered_commands, state.selected_index, 0, width, state)

    strips = strips ++ command_strips

    bottom_border = "└" <> String.duplicate("─", width - 2) <> "┘"
    strips = strips ++ [create_modal_strip(bottom_border, 0, border_style)]

    strips
  end

  defp create_modal_strip(text, _x, style) do
    segment = Segment.new(text, style)
    Strip.new([segment])
  end

  defp create_command_list(commands, selected_index, _x, width, _state) do
    commands
    |> Enum.take(8)
    |> Enum.with_index()
    |> Enum.map(fn {{name, description}, index} ->
      is_selected = index == selected_index

      item_state = %{selected: is_selected}

      command_computed =
        if is_selected do
          Computed.for_part(:command_palette, item_state, :item)
        else
          Computed.for_part(:command_palette, %{}, :item)
        end

      command_style = Computed.to_segment_style(command_computed)

      prefix = if is_selected, do: "│ ▸ ", else: "│   "
      text = prefix <> name <> " - " <> description
      padded_text = String.pad_trailing(text, width - 1) <> "│"

      segment = Segment.new(padded_text, command_style)
      Strip.new([segment])
    end)
  end

  defp filter_commands(commands, query) do
    if String.length(query) == 0 do
      commands
    else
      query_lower = String.downcase(query)

      commands
      |> Enum.filter(fn {name, _description} ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, query_lower)
      end)
    end
  end

  defp default_commands do
    [
      {"Toggle theme", "Switch between light and dark themes"},
      {"Quit application", "Exit the application"},
      {"Show help", "Display help information"},
      {"Refresh screen", "Refresh the display"},
      {"About", "Show application information"},
      {"Settings", "Open application settings"}
    ]
  end
end
