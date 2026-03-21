defmodule Drafter.Runtime.Renderer do
  @moduledoc """
  Rendering pipeline for Drafter applications.

  Converts a widget hierarchy into terminal output via the compositor.
  Stateless — no process state, no message passing.
  """

  alias Drafter.{ComponentRenderer, Compositor, ThemeManager, LayerCompositor, WidgetHierarchy}

  @spec render_app(module(), term(), map(), map() | nil) :: {:ok, map() | nil} | {:error, nil}
  def render_app(app_module, app_state, screen_rect, existing_hierarchy \\ nil) do
    screens = Drafter.ScreenManager.get_all_screens()
    toasts = Drafter.ScreenManager.get_toasts()

    if length(screens) > 0 or length(toasts) > 0 do
      render_screens_from_manager(screen_rect, app_module, app_state, existing_hierarchy)
      {:ok, existing_hierarchy}
    else
      current_theme = ThemeManager.get_current_theme()

      render_result =
        case app_module.render(app_state) do
          [] ->
            app_module.render(app_state, screen_rect)

          result ->
            result
        end

      case render_result do
        component_tree when is_tuple(component_tree) ->
          hierarchy =
            ComponentRenderer.render_tree(
              component_tree,
              screen_rect,
              current_theme,
              app_state,
              existing_hierarchy,
              app_module: app_module
            )

          background_strips = create_app_background(screen_rect, current_theme)
          widget_layers = create_widget_layers_from_hierarchy(hierarchy, screen_rect)

          if length(widget_layers) == 0 do
            Compositor.render_strips(background_strips, 0, 0)
          else
            viewport = %{width: screen_rect.width, height: screen_rect.height}
            background_layer = LayerCompositor.background_layer(background_strips, screen_rect)
            layers = [background_layer] ++ widget_layers
            final_strips = LayerCompositor.composite(layers, viewport)
            Compositor.render_strips(final_strips, 0, 0)
          end

          {:ok, hierarchy}

        strips when is_list(strips) ->
          Compositor.render_strips(strips, 0, 0)
          {:ok, nil}

        {:error, _reason} ->
          {:error, nil}
      end
    end
  end

  @spec render_hierarchy(map(), map()) :: :ok
  def render_hierarchy(hierarchy, screen_rect) do
    screens = Drafter.ScreenManager.get_all_screens()
    toasts = Drafter.ScreenManager.get_toasts()
    current_theme = ThemeManager.get_current_theme()
    background_strips = create_app_background(screen_rect, current_theme)
    viewport = %{width: screen_rect.width, height: screen_rect.height}
    background_layer = LayerCompositor.background_layer(background_strips, screen_rect)
    base_layers = create_widget_layers_from_hierarchy(hierarchy, screen_rect)

    if screens == [] and toasts == [] do
      if base_layers == [] do
        Compositor.render_strips(background_strips, 0, 0)
      else
        final_strips = LayerCompositor.composite([background_layer] ++ base_layers, viewport)
        Compositor.render_strips(final_strips, 0, 0)
      end
    else
      {screen_layers, overlay_layers} =
        Enum.reduce(screens, {[], []}, fn screen, {content_acc, overlay_acc} ->
          screen_local_rect = screen.rect

          if screen_local_rect && screen.widget_hierarchy do
            has_border =
              screen.type in [:modal, :popover] and Map.get(screen.options, :border, false)

            content_rect =
              if has_border do
                %{
                  x: screen_local_rect.x + 1,
                  y: screen_local_rect.y + 1,
                  width: max(1, screen_local_rect.width - 2),
                  height: max(1, screen_local_rect.height - 2)
                }
              else
                screen_local_rect
              end

            content_layers =
              create_widget_layers_from_hierarchy(screen.widget_hierarchy, content_rect, 80)

            new_overlay_layers =
              if has_border do
                [
                  create_modal_border_layer(screen_local_rect, current_theme, screen.options)
                  | overlay_acc
                ]
              else
                overlay_acc
              end

            {content_acc ++ content_layers, new_overlay_layers}
          else
            {content_acc, overlay_acc}
          end
        end)

      toast_layers = Enum.map(toasts, &create_toast_layer(&1, screen_rect, current_theme))

      all_layers =
        [background_layer] ++ base_layers ++ screen_layers ++ overlay_layers ++ toast_layers

      final_strips = LayerCompositor.composite(all_layers, viewport)
      Compositor.render_strips(final_strips, 0, 0)
    end
  end

  @spec render_screens_from_manager(map(), module(), term(), map() | nil) :: :ok
  def render_screens_from_manager(screen_rect, app_module, app_state, existing_hierarchy) do
    screens = Drafter.ScreenManager.get_all_screens()
    toasts = Drafter.ScreenManager.get_toasts()
    current_theme = ThemeManager.get_current_theme()

    background_strips = create_app_background(screen_rect, current_theme)

    has_covering_screens = screens != []

    base_layers =
      if has_covering_screens && existing_hierarchy do
        create_widget_layers_from_hierarchy(existing_hierarchy, screen_rect)
      else
        if app_module && app_state do
          render_result =
            case app_module.render(app_state) do
              [] ->
                app_module.render(app_state, screen_rect)

              result ->
                result
            end

          case render_result do
            component_tree when is_tuple(component_tree) ->
              hierarchy =
                ComponentRenderer.render_tree(
                  component_tree,
                  screen_rect,
                  current_theme,
                  app_state,
                  existing_hierarchy,
                  app_module: app_module
                )

              create_widget_layers_from_hierarchy(hierarchy, screen_rect)

            _ ->
              []
          end
        else
          []
        end
      end

    {screen_layers, overlay_layers} =
      Enum.reduce(screens, {[], []}, fn screen, {content_acc, overlay_acc} ->
        this_screen_rect =
          if screen.rect, do: screen.rect, else: calculate_screen_rect(screen, screen_rect)

        unless screen.rect do
          Drafter.ScreenManager.update_screen_rect(screen.id, this_screen_rect)
        end

        has_border = screen.type in [:modal, :popover] and Map.get(screen.options, :border, false)

        content_rect =
          if has_border do
            %{
              x: this_screen_rect.x + 1,
              y: this_screen_rect.y + 1,
              width: max(1, this_screen_rect.width - 2),
              height: max(1, this_screen_rect.height - 2)
            }
          else
            this_screen_rect
          end

        hierarchy =
          case screen.module.render(screen.state) do
            component_tree when is_tuple(component_tree) ->
              ComponentRenderer.render_tree(
                component_tree,
                content_rect,
                current_theme,
                screen.state,
                screen.widget_hierarchy,
                app_module: screen.module
              )

            _ ->
              screen.widget_hierarchy
          end

        content_layers =
          if hierarchy do
            Drafter.ScreenManager.update_screen_hierarchy(screen.id, hierarchy)
            create_widget_layers_from_hierarchy(hierarchy, content_rect, 80)
          else
            []
          end

        new_overlay_layers =
          if has_border do
            [
              create_modal_border_layer(this_screen_rect, current_theme, screen.options)
              | overlay_acc
            ]
          else
            overlay_acc
          end

        {content_acc ++ content_layers, new_overlay_layers}
      end)

    screen_layers = List.flatten(screen_layers)

    toast_layers =
      Enum.map(toasts, fn toast ->
        create_toast_layer(toast, screen_rect, current_theme)
      end)

    all_layers =
      [LayerCompositor.background_layer(background_strips, screen_rect)] ++
        base_layers ++ screen_layers ++ overlay_layers ++ toast_layers

    if length(all_layers) == 1 do
      Compositor.render_strips(background_strips, 0, 0)
    else
      viewport = %{width: screen_rect.width, height: screen_rect.height}
      final_strips = LayerCompositor.composite(all_layers, viewport)
      Compositor.render_strips(final_strips, 0, 0)
    end
  end

  @spec create_widget_layers_from_hierarchy(map(), map(), non_neg_integer()) :: [map()]
  def create_widget_layers_from_hierarchy(hierarchy, _rect, z_base \\ 0) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())
    widget_ids = Map.keys(hierarchy.widgets)

    Enum.flat_map(widget_ids, fn widget_id ->
      if MapSet.member?(hidden, widget_id) do
        []
      else
        case Map.get(hierarchy.widgets, widget_id) do
          nil ->
            []

          widget_info ->
            widget_rect = Map.get(hierarchy.widget_rects, widget_id)

            if widget_rect && widget_info do
              {render_rect, widget_strips} =
                case Drafter.WidgetStripCache.get(widget_id) do
                  {cached_rect, strips} ->
                    {cached_rect, strips}

                  nil ->
                    if widget_info.pid do
                      Drafter.WidgetServer.get_render(widget_info.pid)
                    else
                      cache = Process.get(:widget_render_cache, %{})

                      cache_key =
                        :erlang.phash2({widget_info.state, widget_rect.width, widget_rect.height})

                      strips =
                        case Map.get(cache, widget_id) do
                          {^cache_key, cached} ->
                            cached

                          _ ->
                            result =
                              apply(widget_info.module, :render, [widget_info.state, widget_rect])

                            Process.put(
                              :widget_render_cache,
                              Map.put(cache, widget_id, {cache_key, result})
                            )

                            result
                        end

                      {widget_rect, strips}
                    end
                end

              scroll_parent_id =
                WidgetHierarchy.get_widget_scroll_parent(hierarchy, widget_id)

              {final_rect, final_strips} =
                if scroll_parent_id do
                  apply_scroll_clipping(hierarchy, scroll_parent_id, render_rect, widget_strips)
                else
                  {render_rect, widget_strips}
                end

              if length(final_strips) > 0 do
                layer = LayerCompositor.widget_layer(widget_id, final_strips, final_rect, z_base)
                [layer]
              else
                []
              end
            else
              []
            end
        end
      end
    end)
  end

  @spec update_hierarchy_preferred_sizes(map()) :: map()
  def update_hierarchy_preferred_sizes(hierarchy) do
    Enum.reduce(hierarchy.widgets, hierarchy, fn {widget_id, widget_info}, acc ->
      case widget_info do
        %{pid: pid, module: module, state: _state} when is_pid(pid) ->
          new_state = Drafter.WidgetServer.get_state(pid)
          updated_widget = %{widget_info | state: new_state}
          new_widgets = Map.put(acc.widgets, widget_id, updated_widget)

          acc
          |> Map.put(:widgets, new_widgets)
          |> update_widget_preferred_size(widget_id, module, new_state)

        _ ->
          acc
      end
    end)
  end

  defp update_widget_preferred_size(hierarchy, widget_id, module, state) do
    case {module, state} do
      {Drafter.Widget.Collapsible,
       %{expanded: true, content: content, content_height: content_height}} ->
        lines =
          cond do
            is_binary(content) -> length(String.split(content, "\n"))
            is_list(content) -> content_height || 10
            true -> 1
          end

        preferred_size = 1 + lines

        WidgetHierarchy.update_preferred_size(hierarchy, widget_id, preferred_size)

      {Drafter.Widget.Collapsible, %{expanded: false}} ->
        WidgetHierarchy.update_preferred_size(hierarchy, widget_id, 1)

      _ ->
        hierarchy
    end
  end

  defp apply_scroll_clipping(hierarchy, scroll_parent_id, widget_rect, widget_strips) do
    scroll_info = WidgetHierarchy.get_scroll_container_info(hierarchy, scroll_parent_id)
    scroll_state = WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

    if scroll_info && scroll_state do
      viewport = scroll_info.viewport_rect
      scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)

      virtual_top = widget_rect.y
      virtual_bottom = widget_rect.y + length(widget_strips)

      viewport_top = viewport.y + scroll_y
      viewport_bottom = viewport_top + viewport.height

      cond do
        virtual_bottom <= viewport_top ->
          {widget_rect, []}

        virtual_top >= viewport_bottom ->
          {widget_rect, []}

        true ->
          start_strip_idx = max(0, viewport_top - virtual_top)
          end_strip_idx = min(length(widget_strips), viewport_bottom - virtual_top)

          clipped_strips =
            Enum.slice(widget_strips, start_strip_idx, end_strip_idx - start_strip_idx)

          screen_y = max(viewport.y, widget_rect.y - scroll_y)

          available_width = viewport.x + viewport.width - widget_rect.x
          max_width = max(1, min(widget_rect.width, available_width))

          clipped_strips =
            Enum.map(clipped_strips, fn strip ->
              Drafter.Draw.Strip.crop(strip, max_width)
            end)

          new_rect = %{
            widget_rect
            | y: screen_y,
              height: length(clipped_strips),
              width: min(widget_rect.width, max_width)
          }

          {new_rect, clipped_strips}
      end
    else
      {widget_rect, widget_strips}
    end
  end

  defp create_modal_border_layer(rect, theme, options) do
    alias Drafter.Draw.{Strip, Segment}

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
        right_dashes = max(0, inner_width - title_len - left_dashes)

        Strip.new([
          Segment.new("╭", border_style),
          Segment.new(String.duplicate("─", left_dashes), border_style),
          Segment.new(title_text, %{fg: theme.text_primary, bg: theme.panel, bold: true}),
          Segment.new(String.duplicate("─", right_dashes), border_style),
          Segment.new("╮", border_style)
        ])
      else
        Strip.new([Segment.new("╭" <> String.duplicate("─", inner_width) <> "╮", border_style)])
      end

    side_strips =
      for _ <- 1..inner_height do
        Strip.new([
          Segment.new("│", border_style),
          Segment.new(String.duplicate(" ", inner_width), content_bg),
          Segment.new("│", border_style)
        ])
      end

    bottom_border =
      Strip.new([Segment.new("╰" <> String.duplicate("─", inner_width) <> "╯", border_style)])

    strips = [top_border] ++ side_strips ++ [bottom_border]
    LayerCompositor.create_layer(:modal_border, strips, rect, 80)
  end

  defp create_toast_layer(toast, screen_rect, _theme) do
    message = toast.message
    variant = toast.variant

    bg_color =
      case variant do
        :success -> {30, 100, 30}
        :error -> {120, 30, 30}
        :warning -> {120, 100, 30}
        _ -> {40, 40, 60}
      end

    text_color = {255, 255, 255}

    lines = String.split(message, "\n")
    max_width = Enum.max_by(lines, &String.length/1) |> String.length()
    max_width = min(max_width + 4, screen_rect.width - 4)
    max_width = max(max_width, 20)

    content_width = max_width - 2

    wrapped_lines =
      Enum.flat_map(lines, fn line ->
        if String.length(line) <= content_width do
          [line]
        else
          chunk_line(line, content_width)
        end
      end)

    height = length(wrapped_lines) + 2
    height = min(height, div(screen_rect.height, 3))

    stack_offset = toast.stack_index * (height + 1)

    {y, x} =
      case toast.position do
        :top_right ->
          {2 + stack_offset, screen_rect.width - max_width - 2}

        :top_center ->
          {2 + stack_offset, div(screen_rect.width - max_width, 2)}

        :top_left ->
          {2 + stack_offset, 2}

        :middle_right ->
          {div(screen_rect.height - height, 2) - div(stack_offset, 2),
           screen_rect.width - max_width - 2}

        :middle_center ->
          {div(screen_rect.height - height, 2) - div(stack_offset, 2),
           div(screen_rect.width - max_width, 2)}

        :middle_left ->
          {div(screen_rect.height - height, 2) - div(stack_offset, 2), 2}

        :bottom_left ->
          {screen_rect.height - height - 2 - stack_offset, 2}

        :bottom_center ->
          {screen_rect.height - height - 2 - stack_offset, div(screen_rect.width - max_width, 2)}

        _ ->
          {screen_rect.height - height - 2 - stack_offset, screen_rect.width - max_width - 2}
      end

    toast_rect = %{x: x, y: y, width: max_width, height: height}

    border_style = %{fg: text_color, bg: bg_color}
    content_style = %{fg: text_color, bg: bg_color}

    top_border = "┌" <> String.duplicate("─", max_width - 2) <> "┐"
    bottom_border = "└" <> String.duplicate("─", max_width - 2) <> "┘"

    content_strips =
      wrapped_lines
      |> Enum.with_index()
      |> Enum.map(fn {line, _idx} ->
        padding = max_width - String.length(line) - 2
        left_pad = div(padding, 2)
        right_pad = padding - left_pad

        full_line =
          "│" <>
            String.duplicate(" ", left_pad) <> line <> String.duplicate(" ", right_pad) <> "│"

        Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(full_line, content_style)])
      end)

    top_strip = Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(top_border, border_style)])

    bottom_strip =
      Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(bottom_border, border_style)])

    all_strips = [top_strip] ++ content_strips ++ [bottom_strip]
    LayerCompositor.content_layer(toast.id, all_strips, toast_rect)
  end

  defp chunk_line(line, max_len) do
    if String.length(line) <= max_len do
      [line]
    else
      {chunk, rest} = String.split_at(line, max_len)
      [chunk | chunk_line(rest, max_len)]
    end
  end

  defp calculate_screen_rect(screen, base_rect) do
    Drafter.Screen.calculate_rect(screen, base_rect)
  end

  defp create_app_background(rect, theme) do
    empty_style = %{bg: theme.background, fg: theme.text_primary}
    empty_line = String.duplicate(" ", rect.width)

    for _row <- 0..(rect.height - 1) do
      Drafter.Draw.Strip.new([Drafter.Draw.Segment.new(empty_line, empty_style)])
    end
  end
end
