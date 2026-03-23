defmodule Drafter.ScreenRenderer do
  @moduledoc false

  alias Drafter.{ComponentRenderer, LayerCompositor, Screen, ScreenManager, ThemeManager}
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.WidgetHierarchy

  def render_screens(base_strips, screen_rect, app_state) do
    screens = ScreenManager.get_all_screens()
    toasts = ScreenManager.get_toasts()
    theme = ThemeManager.get_current_theme()

    screens
    |> Enum.reverse()
    |> Enum.reduce(base_strips, fn screen, acc_strips ->
      render_screen_layer(screen, acc_strips, screen_rect, theme, app_state)
    end)
    |> render_toasts(toasts, screen_rect, theme)
  end

  defp render_screen_layer(
         %Screen{type: :default} = screen,
         base_strips,
         screen_rect,
         theme,
         app_state
       ) do
    screen_content = Screen.render_screen(screen)
    render_full_screen(screen_content, base_strips, screen_rect, theme, app_state, screen)
  end

  defp render_screen_layer(
         %Screen{type: :modal} = screen,
         base_strips,
         screen_rect,
         theme,
         app_state
       ) do
    modal_rect = Screen.calculate_rect(screen, screen_rect)
    ScreenManager.update_screen_rect(screen.id, modal_rect)
    screen_content = Screen.render_screen(screen)

    strips_with_overlay =
      if screen.options.overlay do
        apply_overlay(base_strips, screen_rect, screen.options)
      else
        base_strips
      end

    modal_strips = render_modal_content(screen_content, modal_rect, theme, app_state, screen)
    composite_at(strips_with_overlay, modal_strips, modal_rect)
  end

  defp render_screen_layer(
         %Screen{type: :popover} = screen,
         base_strips,
         screen_rect,
         theme,
         app_state
       ) do
    popover_rect = Screen.calculate_rect(screen, screen_rect)
    ScreenManager.update_screen_rect(screen.id, popover_rect)
    screen_content = Screen.render_screen(screen)

    popover_strips =
      render_popover_content(screen_content, popover_rect, theme, app_state, screen)

    composite_at(base_strips, popover_strips, popover_rect)
  end

  defp render_screen_layer(
         %Screen{type: :panel} = screen,
         base_strips,
         screen_rect,
         theme,
         app_state
       ) do
    panel_rect = Screen.calculate_rect(screen, screen_rect)
    ScreenManager.update_screen_rect(screen.id, panel_rect)
    screen_content = Screen.render_screen(screen)

    panel_strips = render_panel_content(screen_content, panel_rect, theme, app_state, screen)
    composite_at(base_strips, panel_strips, panel_rect)
  end

  defp render_screen_layer(_screen, base_strips, _screen_rect, _theme, _app_state) do
    base_strips
  end

  defp render_full_screen(content, _base_strips, screen_rect, theme, app_state, screen) do
    hierarchy = Map.get(screen, :widget_hierarchy)
    app_module = screen.module

    case content do
      component_tree when is_tuple(component_tree) ->
        new_hierarchy =
          ComponentRenderer.render_tree(
            component_tree,
            screen_rect,
            theme,
            app_state,
            hierarchy,
            app_module: app_module
          )

        ScreenManager.update_screen_hierarchy(screen.id, new_hierarchy)

        background_strips = create_background(screen_rect, theme)
        widget_layers = create_widget_layers(new_hierarchy, screen_rect)
        viewport = %{width: screen_rect.width, height: screen_rect.height}
        bg_layer = LayerCompositor.background_layer(background_strips, screen_rect)
        layers = [bg_layer | widget_layers]
        LayerCompositor.composite(layers, viewport)

      strips when is_list(strips) ->
        strips

      _ ->
        create_background(screen_rect, theme)
    end
  end

  defp render_modal_content(content, rect, theme, app_state, screen) do
    inner_rect = %{
      x: 0,
      y: 0,
      width: rect.width - 2,
      height: rect.height - 2
    }

    hierarchy = Map.get(screen, :widget_hierarchy)
    app_module = screen.module

    {inner_strips, _updated_hierarchy} =
      case content do
        component_tree when is_tuple(component_tree) ->
          new_hierarchy =
            ComponentRenderer.render_tree(
              component_tree,
              inner_rect,
              theme,
              app_state,
              hierarchy,
              app_module: app_module
            )

          ScreenManager.update_screen_hierarchy(screen.id, new_hierarchy)

          background_strips = create_background(inner_rect, theme)
          widget_layers = create_widget_layers(new_hierarchy, inner_rect)
          viewport = %{width: inner_rect.width, height: inner_rect.height}
          bg_layer = LayerCompositor.background_layer(background_strips, inner_rect)
          layers = [bg_layer | widget_layers]
          strips = LayerCompositor.composite(layers, viewport)

          {strips, new_hierarchy}

        strips when is_list(strips) ->
          {strips, hierarchy}

        _ ->
          {create_background(inner_rect, theme), hierarchy}
      end

    wrap_with_border(inner_strips, rect, theme, screen.options)
  end

  defp render_popover_content(content, rect, theme, app_state, screen) do
    inner_rect = %{
      x: 0,
      y: 0,
      width: rect.width - 2,
      height: rect.height - 2
    }

    hierarchy = Map.get(screen, :widget_hierarchy)
    app_module = screen.module

    {inner_strips, _updated_hierarchy} =
      case content do
        component_tree when is_tuple(component_tree) ->
          new_hierarchy =
            ComponentRenderer.render_tree(
              component_tree,
              inner_rect,
              theme,
              app_state,
              hierarchy,
              app_module: app_module
            )

          ScreenManager.update_screen_hierarchy(screen.id, new_hierarchy)

          background_strips = create_background(inner_rect, theme)
          widget_layers = create_widget_layers(new_hierarchy, inner_rect)
          viewport = %{width: inner_rect.width, height: inner_rect.height}
          bg_layer = LayerCompositor.background_layer(background_strips, inner_rect)
          layers = [bg_layer | widget_layers]
          strips = LayerCompositor.composite(layers, viewport)

          {strips, new_hierarchy}

        strips when is_list(strips) ->
          {strips, hierarchy}

        _ ->
          {create_background(inner_rect, theme), hierarchy}
      end

    if screen.options.border do
      wrap_with_border(inner_strips, rect, theme, screen.options)
    else
      inner_strips
    end
  end

  defp render_panel_content(content, rect, theme, app_state, screen) do
    inner_width = rect.width - 1
    inner_rect = %{x: 0, y: 0, width: inner_width, height: rect.height}

    hierarchy = Map.get(screen, :widget_hierarchy)
    app_module = screen.module

    {inner_strips, _updated_hierarchy} =
      case content do
        component_tree when is_tuple(component_tree) ->
          new_hierarchy =
            ComponentRenderer.render_tree(
              component_tree,
              inner_rect,
              theme,
              app_state,
              hierarchy,
              app_module: app_module
            )

          ScreenManager.update_screen_hierarchy(screen.id, new_hierarchy)

          background_strips = create_background(inner_rect, theme)
          widget_layers = create_widget_layers(new_hierarchy, inner_rect)
          viewport = %{width: inner_rect.width, height: inner_rect.height}
          bg_layer = LayerCompositor.background_layer(background_strips, inner_rect)
          layers = [bg_layer | widget_layers]
          strips = LayerCompositor.composite(layers, viewport)

          {strips, new_hierarchy}

        strips when is_list(strips) ->
          {strips, hierarchy}

        _ ->
          {create_background(inner_rect, theme), hierarchy}
      end

    border_style = %{fg: theme.border, bg: theme.panel}
    border_char = "│"

    position = screen.options.position

    Enum.map(inner_strips, fn strip ->
      if position == :left do
        Strip.append(strip, Segment.new(border_char, border_style))
      else
        Strip.prepend(strip, Segment.new(border_char, border_style))
      end
    end)
  end

  defp render_toasts(strips, [], _screen_rect, _theme) do
    strips
  end

  defp render_toasts(strips, toasts, screen_rect, theme) do
    Enum.reduce(toasts, strips, fn toast, acc ->
      render_toast(acc, toast, screen_rect, theme)
    end)
  end

  defp render_toast(strips, toast, screen_rect, theme) do
    width = min(50, screen_rect.width - 4)
    message_lines = wrap_text(toast.message, width - 4)
    height = length(message_lines) + 2

    {x, y} = calculate_toast_position(toast.position, width, height, screen_rect)

    {bg, fg, icon} =
      case toast.variant do
        :success -> {theme.success, theme.background, "✓"}
        :error -> {theme.error, theme.background, "✗"}
        :warning -> {theme.warning, theme.background, "⚠"}
        :info -> {theme.primary, theme.background, "ℹ"}
        _ -> {theme.panel, theme.text_primary, "•"}
      end

    style = %{fg: fg, bg: bg}
    border_style = %{fg: fg, bg: bg}

    toast_strips = []

    top_border = "╭" <> String.duplicate("─", width - 2) <> "╮"
    toast_strips = toast_strips ++ [Strip.new([Segment.new(top_border, border_style)])]

    content_strips =
      Enum.map(message_lines, fn line ->
        padded = " #{icon} " <> String.pad_trailing(line, width - 6) <> " "

        Strip.new([
          Segment.new("│", border_style),
          Segment.new(padded, style),
          Segment.new("│", border_style)
        ])
      end)

    toast_strips = toast_strips ++ content_strips

    bottom_border = "╰" <> String.duplicate("─", width - 2) <> "╯"
    toast_strips = toast_strips ++ [Strip.new([Segment.new(bottom_border, border_style)])]

    toast_rect = %{x: x, y: y, width: width, height: height}
    composite_at(strips, toast_strips, toast_rect)
  end

  defp calculate_toast_position(position, width, height, screen_rect) do
    case position do
      :bottom_right -> {screen_rect.width - width - 2, screen_rect.height - height - 1}
      :bottom_left -> {2, screen_rect.height - height - 1}
      :top_right -> {screen_rect.width - width - 2, 1}
      :top_left -> {2, 1}
      :bottom_center -> {div(screen_rect.width - width, 2), screen_rect.height - height - 1}
      :top_center -> {div(screen_rect.width - width, 2), 1}
      _ -> {screen_rect.width - width - 2, screen_rect.height - height - 1}
    end
  end

  defp apply_overlay(strips, _screen_rect, options) do
    {r, g, b} = options.overlay_color
    opacity = options.overlay_opacity

    Enum.map(strips, fn strip ->
      segments =
        Enum.map(strip.segments, fn segment ->
          {sr, sg, sb} = segment.style[:bg] || {0, 0, 0}

          new_bg = {
            round(sr * (1 - opacity) + r * opacity),
            round(sg * (1 - opacity) + g * opacity),
            round(sb * (1 - opacity) + b * opacity)
          }

          {fr, fg_val, fb} = segment.style[:fg] || {255, 255, 255}
          dim_factor = 0.6

          new_fg = {
            round(fr * dim_factor),
            round(fg_val * dim_factor),
            round(fb * dim_factor)
          }

          new_style = Map.merge(segment.style, %{bg: new_bg, fg: new_fg})
          %{segment | style: new_style}
        end)

      %{strip | segments: segments}
    end)
  end

  defp wrap_with_border(inner_strips, rect, theme, options) do
    border_style = %{fg: theme.primary, bg: theme.panel}
    content_bg = %{fg: theme.text_primary, bg: theme.panel}

    inner_width = rect.width - 2
    inner_height = rect.height - 2

    title = Map.get(options, :title)

    top_border =
      if title do
        title_text = " #{title} "
        title_len = String.length(title_text)
        left_dashes = div(inner_width - title_len, 2)
        right_dashes = inner_width - title_len - left_dashes

        Strip.new([
          Segment.new("╭", border_style),
          Segment.new(String.duplicate("─", left_dashes), border_style),
          Segment.new(title_text, %{fg: theme.text_primary, bg: theme.panel, bold: true}),
          Segment.new(String.duplicate("─", right_dashes), border_style),
          Segment.new("╮", border_style)
        ])
      else
        Strip.new([
          Segment.new("╭" <> String.duplicate("─", inner_width) <> "╮", border_style)
        ])
      end

    padded_inner =
      inner_strips
      |> Enum.take(inner_height)
      |> Enum.map(fn strip ->
        strip_width = Strip.width(strip)
        padding_needed = max(0, inner_width - strip_width)

        Strip.new(
          [Segment.new("│", border_style)] ++
            strip.segments ++
            [
              Segment.new(String.duplicate(" ", padding_needed), content_bg),
              Segment.new("│", border_style)
            ]
        )
      end)

    current_height = length(padded_inner)
    empty_lines_needed = inner_height - current_height

    empty_lines =
      if empty_lines_needed > 0 do
        empty_content = String.duplicate(" ", inner_width)

        for _ <- 1..empty_lines_needed do
          Strip.new([
            Segment.new("│", border_style),
            Segment.new(empty_content, content_bg),
            Segment.new("│", border_style)
          ])
        end
      else
        []
      end

    bottom_border =
      Strip.new([
        Segment.new("╰" <> String.duplicate("─", inner_width) <> "╯", border_style)
      ])

    [top_border] ++ padded_inner ++ empty_lines ++ [bottom_border]
  end

  defp composite_at(base_strips, overlay_strips, rect) do
    base_strips
    |> Enum.with_index()
    |> Enum.map(fn {strip, y} ->
      composite_strip(strip, y, overlay_strips, rect)
    end)
  end

  defp composite_strip(strip, y, overlay_strips, rect) do
    overlay_idx = y - rect.y

    if y >= rect.y and y < rect.y + rect.height and overlay_idx < length(overlay_strips) do
      merge_strip_at(strip, Enum.at(overlay_strips, overlay_idx), rect.x)
    else
      strip
    end
  end

  defp merge_strip_at(base_strip, overlay_strip, x_offset) do
    base_text = Strip.to_plain_text(base_strip)
    overlay_text = Strip.to_plain_text(overlay_strip)

    before_text = String.slice(base_text, 0, x_offset) || ""
    after_start = x_offset + String.length(overlay_text)
    after_text = String.slice(base_text, after_start, String.length(base_text)) || ""

    before_segments = extract_segments_for_range(base_strip, 0, x_offset)
    after_segments = extract_segments_for_range(base_strip, after_start, String.length(base_text))

    default_style = %{fg: {200, 200, 200}, bg: {30, 30, 30}}

    before_segment =
      if String.length(before_text) > 0 do
        style =
          case before_segments do
            [seg | _] -> seg.style
            _ -> default_style
          end

        [Segment.new(before_text, style)]
      else
        []
      end

    after_segment =
      if String.length(after_text) > 0 do
        style =
          case after_segments do
            [seg | _] -> seg.style
            _ -> default_style
          end

        [Segment.new(after_text, style)]
      else
        []
      end

    Strip.new(before_segment ++ overlay_strip.segments ++ after_segment)
  end

  defp extract_segments_for_range(strip, start_pos, end_pos) do
    {_, result} =
      Enum.reduce(strip.segments, {0, []}, fn segment, {pos, acc} ->
        seg_len = String.length(segment.text)
        seg_end = pos + seg_len

        cond do
          seg_end <= start_pos ->
            {seg_end, acc}

          pos >= end_pos ->
            {seg_end, acc}

          true ->
            {seg_end, acc ++ [segment]}
        end
      end)

    result
  end

  defp create_background(rect, theme) do
    style = %{fg: theme.text_primary, bg: theme.background}
    line = String.duplicate(" ", rect.width)

    for _ <- 0..(rect.height - 1) do
      Strip.new([Segment.new(line, style)])
    end
  end

  defp create_widget_layers(hierarchy, _rect) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Map.keys()
    |> Enum.flat_map(fn widget_id ->
      create_widget_layer(hierarchy, widget_id, hidden)
    end)
  end

  defp create_widget_layer(hierarchy, widget_id, hidden) do
    with false <- MapSet.member?(hidden, widget_id),
         widget_info when not is_nil(widget_info) <- Map.get(hierarchy.widgets, widget_id),
         widget_rect when not is_nil(widget_rect) <- Map.get(hierarchy.widget_rects, widget_id) do
      build_widget_layer(hierarchy, widget_id, widget_info, widget_rect)
    else
      _ -> []
    end
  end

  defp build_widget_layer(hierarchy, widget_id, widget_info, widget_rect) do
    scroll_parent_id = WidgetHierarchy.get_widget_scroll_parent(hierarchy, widget_id)
    scroll_info = scroll_parent_id && WidgetHierarchy.get_scroll_container_info(hierarchy, scroll_parent_id)
    scroll_state = scroll_parent_id && WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

    if scroll_info && scroll_state && widget_clipped?(widget_rect, scroll_info, scroll_state) do
      []
    else
      render_widget_to_layer(
        hierarchy, widget_id, widget_info, widget_rect, scroll_parent_id, scroll_info, scroll_state
      )
    end
  end

  defp widget_clipped?(widget_rect, scroll_info, scroll_state) do
    viewport = scroll_info.viewport_rect
    scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)
    widget_bottom = widget_rect.y + widget_rect.height
    viewport_bottom = viewport.y + scroll_y + viewport.height
    widget_bottom <= viewport.y + scroll_y or widget_rect.y >= viewport_bottom
  end

  defp render_widget_to_layer(
         _hierarchy,
         widget_id,
         widget_info,
         widget_rect,
         scroll_parent_id,
         scroll_info,
         scroll_state
       ) do
    {render_rect, widget_strips} =
      if widget_info.pid do
        Drafter.WidgetServer.get_render(widget_info.pid)
      else
        strips = widget_info.module.render(widget_info.state, widget_rect)
        {widget_rect, strips}
      end

    {final_rect, final_strips} =
      if scroll_parent_id && scroll_info && scroll_state do
        scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)

        adjusted_rect = %{
          x: widget_rect.x,
          y: widget_rect.y - scroll_y,
          width: widget_rect.width,
          height: widget_rect.height
        }

        {adjusted_rect, widget_strips}
      else
        {render_rect, widget_strips}
      end

    if final_strips != [] do
      layer = LayerCompositor.widget_layer(widget_id, final_strips, final_rect)
      [layer]
    else
      []
    end
  end

  defp wrap_text(text, max_width) do
    {lines, current_line} =
      text
      |> String.split(~r/\s+/)
      |> Enum.reduce({[], ""}, fn word, {lines, current} ->
        accumulate_word(lines, current, word, max_width)
      end)

    if current_line == "", do: lines, else: lines ++ [current_line]
  end

  defp accumulate_word(lines, current, word, max_width) do
    test_line = if current == "", do: word, else: current <> " " <> word

    if String.length(test_line) <= max_width do
      {lines, test_line}
    else
      append_overflowing_word(lines, current, word, max_width)
    end
  end

  defp append_overflowing_word(lines, "", word, max_width) do
    {lines ++ [String.slice(word, 0, max_width)], ""}
  end

  defp append_overflowing_word(lines, current, word, _max_width) do
    {lines ++ [current], word}
  end
end
