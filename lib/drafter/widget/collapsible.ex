defmodule Drafter.Widget.Collapsible do
  @moduledoc """
  Renders an expandable section with a title row and collapsible content.

  The widget displays a `▶` arrow when collapsed and `▼` when expanded.
  Pressing `Enter`, `Space`, or clicking the title row toggles the expanded
  state. The `:on_toggle` callback is invoked with the new boolean state after
  each toggle.

  Content can be a plain string (word-wrapped to fit the available width) or a
  list of child widgets built with the same helper functions available in
  `Drafter.App` (e.g. `checkbox/2`, `radio_set/2`, `text_input/1`). Child
  widgets are fully interactive — they receive focus, keyboard, and mouse events
  just like top-level widgets. Use `:content_height` to reserve the right number
  of rows for the expanded body when passing child widgets.

  ## Options

    * `:title` - header text shown in the toggle row (default `"Collapsible"`)
    * `:content` - body string or list of child widget descriptors (default `""`)
    * `:content_height` - number of rows reserved for child widgets when expanded;
      ignored for string content (default `10`)
    * `:expanded` - initial expansion state: `true` / `false` (default)
    * `:on_toggle` - one-arity callback invoked with the new `expanded` boolean

  ## Usage

      collapsible("About", "Plain text is word-wrapped automatically.")

      collapsible(
        "Preferences",
        [
          checkbox("Enable notifications", id: :notifs, checked: state.notifs, on_change: :notifs_changed),
          checkbox("Dark mode", id: :dark, checked: state.dark, on_change: :dark_changed)
        ],
        content_height: 2
      )

      collapsible(
        "Theme",
        [radio_set([{"Light", "light"}, {"Dark", "dark"}], id: :theme, selected: state.theme, on_change: :theme_changed)],
        content_height: 2,
        expanded: true
      )
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :click],
    layout_impact: :below

  alias Drafter.{CharacterSet, Text, ThemeManager}
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :title,
    :content,
    :content_height,
    :expanded,
    :focused,
    :hovered,
    :on_toggle
  ]

  def mount(props) do
    content = Map.get(props, :content, "")

    %__MODULE__{
      title: Map.get(props, :title, "Collapsible"),
      content: content,
      content_height: Map.get(props, :content_height, default_content_height(content)),
      expanded: Map.get(props, :expanded, false),
      focused: Map.get(props, :focused, false),
      hovered: Map.get(props, :hovered, false),
      on_toggle: Map.get(props, :on_toggle)
    }
  end

  def render(state, rect) do
    theme = ThemeManager.get_current_theme()
    bg_style = %{fg: theme.text_primary, bg: theme.background}

    arrow =
      if state.expanded, do: CharacterSet.arrow(:expand), else: CharacterSet.arrow(:collapse)

    title_computed = Computed.for_widget(:collapsible, state)
    arrow_computed = Computed.for_part(:collapsible, state, :arrow)

    title_style = Computed.to_segment_style(title_computed)
    arrow_style = Computed.to_segment_style(arrow_computed)

    title_text = " " <> state.title
    padded_title = String.pad_trailing(title_text, rect.width - 2)

    title_strip =
      Strip.new([
        Segment.new(arrow, arrow_style),
        Segment.new(padded_title, title_style)
      ])

    if state.expanded do
      content_strips = render_content(state.content, state.content_height, rect, bg_style)
      all_strips = [title_strip | content_strips]
      current_height = length(all_strips)

      if current_height < rect.height do
        empty_strip = Strip.new([Segment.new(String.duplicate(" ", rect.width), bg_style)])
        all_strips ++ List.duplicate(empty_strip, rect.height - current_height)
      else
        Enum.take(all_strips, rect.height)
      end
    else
      if rect.height > 1 do
        empty_strip = Strip.new([Segment.new(String.duplicate(" ", rect.width), bg_style)])
        [title_strip | List.duplicate(empty_strip, rect.height - 1)]
      else
        [title_strip]
      end
    end
  end

  def update(props, state) do
    new_content =
      if Map.has_key?(props, :content), do: props.content, else: state.content

    new_content_height =
      cond do
        Map.has_key?(props, :content_height) ->
          props.content_height

        Map.has_key?(props, :content) and is_binary(new_content) != is_binary(state.content) ->
          default_content_height(new_content)

        true ->
          state.content_height
      end

    state
    |> Map.merge(props)
    |> Map.put(:content_height, new_content_height)
  end

  def handle_event({:key, key}, state) when key in [:enter, :" "], do: toggle(state)
  def handle_event({:mouse, %{type: :mouse_up, y: 0}}, state), do: toggle(state)
  def handle_event({:mouse, %{type: :mouse_up}}, state), do: {:noreply, state}
  def handle_event({:focus}, state), do: {:ok, %{state | focused: true, hovered: true}}
  def handle_event({:blur}, state), do: {:ok, %{state | focused: false, hovered: false}}
  def handle_event(:hover, state), do: {:ok, %{state | hovered: true}}
  def handle_event(:unhover, state), do: {:ok, %{state | hovered: false}}
  def handle_event(_, state), do: {:bubble, state}

  defp render_content(content, _content_height, rect, bg_style) when is_binary(content) do
    content_lines = Text.wrap(content, rect.width - 2, :word)

    Enum.map(content_lines, fn line ->
      padded_line = "  " <> Text.pad_right(line, rect.width - 2)
      Strip.new([Segment.new(padded_line, bg_style)])
    end)
  end

  defp render_content(content, content_height, _rect, bg_style) when is_list(content) do
    empty_strip = Strip.new([Segment.new("", bg_style)])
    List.duplicate(empty_strip, content_height || 0)
  end

  defp default_content_height(content) when is_binary(content), do: nil
  defp default_content_height(_content), do: 10

  defp toggle(state) do
    new_state = %{state | expanded: not state.expanded}

    if state.on_toggle do
      try do
        state.on_toggle.(new_state.expanded)
      rescue
        _ -> :ok
      end
    end

    {:ok, new_state, [{:widget_layout_needed, :below}]}
  end
end
