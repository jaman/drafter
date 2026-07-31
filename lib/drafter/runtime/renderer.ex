defmodule Drafter.Runtime.Renderer do
  @moduledoc """
  Rendering pipeline for Drafter applications.

  Converts a widget hierarchy into terminal output via the compositor.
  Stateless — no process state, no message passing.
  """

  alias Drafter.ComponentRenderer
  alias Drafter.Compositor
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.LayerCompositor
  alias Drafter.RenderCache
  alias Drafter.Screen
  alias Drafter.ScreenManager
  alias Drafter.ThemeManager
  alias Drafter.Widget.Collapsible
  alias Drafter.WidgetHierarchy
  alias Drafter.WidgetServer
  alias Drafter.WidgetStripCache

  @spec render_app(module(), term(), map(), map() | nil) :: {:ok, map() | nil} | {:error, nil}
  def render_app(app_module, app_state, screen_rect, existing_hierarchy \\ nil) do
    screens = ScreenManager.get_all_screens()
    toasts = ScreenManager.get_toasts()

    cond do
      screens != [] ->
        render_screens_from_manager(screen_rect, app_module, app_state, existing_hierarchy)
        {:ok, existing_hierarchy}

      toasts != [] ->
        hierarchy = rebuild_app_hierarchy(app_module, app_state, screen_rect, existing_hierarchy)
        render_screens_from_manager(screen_rect, app_module, app_state, hierarchy)
        {:ok, hierarchy}

      true ->
        render_app_direct(app_module, app_state, screen_rect, existing_hierarchy)
    end
  end

  defp rebuild_app_hierarchy(app_module, app_state, screen_rect, existing_hierarchy) do
    current_theme = ThemeManager.get_current_theme()

    render_result =
      case app_module.render(app_state) do
        [] -> app_module.render(app_state, screen_rect)
        result -> result
      end

    case render_result do
      component_tree when is_tuple(component_tree) ->
        ComponentRenderer.render_tree(
          component_tree,
          screen_rect,
          current_theme,
          app_state,
          existing_hierarchy,
          app_module: app_module
        )

      _ ->
        existing_hierarchy
    end
  end

  defp render_app_direct(app_module, app_state, screen_rect, existing_hierarchy) do
    app_hash = :erlang.phash2(app_state)
    prev_hash = RenderCache.get_app_state_hash()
    layout_dirty = Process.get(:render_cache_layout_dirty, true)

    ctrace([
      "FP eq=",
      to_string(prev_hash == app_hash),
      " ld=",
      to_string(layout_dirty),
      " h=",
      to_string(existing_hierarchy != nil),
      "\n"
    ])

    if prev_hash == app_hash and existing_hierarchy != nil and not layout_dirty do
      RenderCache.put_app_state_hash(app_hash)
      render_hierarchy(existing_hierarchy, screen_rect)
      {:ok, existing_hierarchy}
    else
      RenderCache.put_app_state_hash(app_hash)
      Process.delete(:render_cache_layout_dirty)
      Process.delete(:render_cache_layout_direction)
      Process.delete(:render_cache_layout_rect)
      current_theme = ThemeManager.get_current_theme()

      t0 = System.monotonic_time(:microsecond)

      render_result =
        case app_module.render(app_state) do
          [] -> app_module.render(app_state, screen_rect)
          result -> result
        end

      t1 = System.monotonic_time(:microsecond)

      out =
        apply_render_result(
          render_result,
          app_module,
          app_state,
          screen_rect,
          current_theme,
          existing_hierarchy
        )

      if Drafter.Trace.enabled?() do
        t2 = System.monotonic_time(:microsecond)

        Drafter.Trace.log([
          "RR render1_us=",
          Integer.to_string(t1 - t0),
          " apply_us=",
          Integer.to_string(t2 - t1),
          "\n"
        ])
      end

      out
    end
  end

  defp apply_render_result(
         component_tree,
         app_module,
         app_state,
         screen_rect,
         theme,
         existing_hierarchy
       )
       when is_tuple(component_tree) do
    ta = System.monotonic_time(:microsecond)

    hierarchy =
      ComponentRenderer.render_tree(
        component_tree,
        screen_rect,
        theme,
        app_state,
        existing_hierarchy,
        app_module: app_module
      )

    tb = System.monotonic_time(:microsecond)
    render_hierarchy_layers(hierarchy, screen_rect, theme)
    tc = System.monotonic_time(:microsecond)

    ctrace([
      "A tree_us=",
      Integer.to_string(tb - ta),
      " layers_us=",
      Integer.to_string(tc - tb),
      "\n"
    ])

    {:ok, hierarchy}
  end

  defp apply_render_result(
         strips,
         _app_module,
         _app_state,
         _screen_rect,
         _theme,
         _existing_hierarchy
       )
       when is_list(strips) do
    Compositor.render_strips(strips, 0, 0)
    {:ok, nil}
  end

  defp apply_render_result({:error, _reason}, _, _, _, _, _), do: {:error, nil}

  defp render_hierarchy_layers(hierarchy, screen_rect, theme) do
    background_strips = create_app_background(screen_rect, theme)
    t0 = System.monotonic_time(:microsecond)

    {widget_layers, dirty_ids, stale_bounds} =
      create_widget_layers_tracking_dirty(hierarchy, screen_rect)

    t1 = System.monotonic_time(:microsecond)

    if widget_layers == [] do
      RenderCache.put_composited(background_strips)
      RenderCache.put_layer_count(0)
      Compositor.render_strips(background_strips, 0, 0)
    else
      viewport = %{width: screen_rect.width, height: screen_rect.height}
      background_layer = LayerCompositor.background_layer(background_strips, screen_rect)
      all_layers = [background_layer | widget_layers]

      final_strips =
        incremental_composite_or_full(all_layers, viewport, dirty_ids, stale_bounds)

      t2 = System.monotonic_time(:microsecond)
      RenderCache.put_composited(final_strips)
      RenderCache.put_layer_count(length(all_layers))
      Compositor.render_strips(final_strips, 0, 0)

      ctrace([
        "A build_us=",
        Integer.to_string(t1 - t0),
        " comp_us=",
        Integer.to_string(t2 - t1),
        "\n"
      ])
    end
  end

  @spec render_hierarchy(map(), map()) :: :ok
  def render_hierarchy(hierarchy, screen_rect) do
    screens = ScreenManager.get_all_screens()
    toasts = ScreenManager.get_toasts()
    current_theme = ThemeManager.get_current_theme()
    background_strips = create_app_background(screen_rect, current_theme)
    viewport = %{width: screen_rect.width, height: screen_rect.height}
    background_layer = LayerCompositor.background_layer(background_strips, screen_rect)

    {base_layers, dirty_ids, stale_bounds} =
      create_widget_layers_tracking_dirty(hierarchy, screen_rect)

    if screens == [] and toasts == [] do
      if base_layers == [] do
        RenderCache.put_composited(background_strips)
        RenderCache.put_layer_count(0)
        Compositor.render_strips(background_strips, 0, 0)
      else
        all_layers = [background_layer | base_layers]

        final_strips =
          incremental_composite_or_full(all_layers, viewport, dirty_ids, stale_bounds)

        RenderCache.put_composited(final_strips)
        RenderCache.put_layer_count(length(all_layers))
        Compositor.render_strips(final_strips, 0, 0)
      end
    else
      {screen_layers, overlay_layers} =
        Enum.reduce(screens, {[], []}, fn screen, acc ->
          accumulate_screen_layers(screen, acc, current_theme)
        end)

      toast_layers = Enum.map(toasts, &create_toast_layer(&1, screen_rect, current_theme))

      all_layers =
        [background_layer] ++ base_layers ++ screen_layers ++ overlay_layers ++ toast_layers

      final_strips =
        incremental_composite_or_full(all_layers, viewport, dirty_ids, stale_bounds)

      RenderCache.put_composited(final_strips)
      RenderCache.put_layer_count(length(all_layers))
      Compositor.render_strips(final_strips, 0, 0)
    end
  end

  @spec render_screens_from_manager(map(), module(), term(), map() | nil) :: :ok
  def render_screens_from_manager(screen_rect, app_module, app_state, existing_hierarchy) do
    screens = ScreenManager.get_all_screens()
    toasts = ScreenManager.get_toasts()
    current_theme = ThemeManager.get_current_theme()
    background_strips = create_app_background(screen_rect, current_theme)

    base_layers =
      compute_base_layers(
        screens,
        existing_hierarchy,
        app_module,
        app_state,
        screen_rect,
        current_theme
      )

    {screen_layers, overlay_layers} =
      Enum.reduce(screens, {[], []}, fn screen, acc ->
        accumulate_manager_screen(screen, acc, current_theme, screen_rect)
      end)

    toast_layers = Enum.map(toasts, &create_toast_layer(&1, screen_rect, current_theme))
    background_layer = LayerCompositor.background_layer(background_strips, screen_rect)
    overlay = List.flatten(screen_layers) ++ overlay_layers ++ toast_layers
    all_layers = [background_layer] ++ base_layers ++ overlay

    if length(all_layers) == 1 do
      RenderCache.put_composited(background_strips)
      RenderCache.put_layer_count(0)
      Compositor.render_strips(background_strips, 0, 0)
    else
      viewport = %{width: screen_rect.width, height: screen_rect.height}
      dirty_rows = layer_rows(overlay, viewport)
      final_strips = incremental_composite_or_full(all_layers, viewport, dirty_rows, [])
      RenderCache.put_composited(final_strips)
      RenderCache.put_layer_count(length(all_layers))
      Compositor.render_strips(final_strips, 0, 0)
    end
  end

  defp layer_rows(layers, viewport) do
    Enum.reduce(layers, MapSet.new(), fn %{bounds: bounds}, acc ->
      first = max(bounds.y, 0)
      last = min(bounds.y + bounds.height - 1, viewport.height - 1)
      if first > last, do: acc, else: Enum.into(first..last//1, acc)
    end)
  end

  defp compute_base_layers(
         screens,
         existing_hierarchy,
         _app_module,
         _app_state,
         screen_rect,
         _theme
       )
       when screens != [] and not is_nil(existing_hierarchy) do
    create_widget_layers_from_hierarchy(existing_hierarchy, screen_rect)
  end

  defp compute_base_layers(_screens, _existing_hierarchy, nil, _app_state, _screen_rect, _theme),
    do: []

  defp compute_base_layers(_screens, _existing_hierarchy, _app_module, nil, _screen_rect, _theme),
    do: []

  defp compute_base_layers(
         _screens,
         existing_hierarchy,
         app_module,
         app_state,
         screen_rect,
         theme
       ) do
    render_result =
      case app_module.render(app_state) do
        [] -> app_module.render(app_state, screen_rect)
        result -> result
      end

    case render_result do
      component_tree when is_tuple(component_tree) ->
        hierarchy =
          ComponentRenderer.render_tree(
            component_tree,
            screen_rect,
            theme,
            app_state,
            existing_hierarchy,
            app_module: app_module
          )

        create_widget_layers_from_hierarchy(hierarchy, screen_rect)

      _ ->
        []
    end
  end

  defp accumulate_manager_screen(screen, {content_acc, overlay_acc}, current_theme, screen_rect) do
    this_rect = screen.rect || calculate_screen_rect(screen, screen_rect)
    unless screen.rect, do: ScreenManager.update_screen_rect(screen.id, this_rect)

    has_border = screen.type in [:modal, :popover] and Map.get(screen.options, :border, false)
    content_rect = if has_border, do: inset_rect(this_rect), else: this_rect

    hierarchy = render_screen_hierarchy(screen, content_rect, current_theme)

    content_layers =
      if hierarchy do
        ScreenManager.update_screen_hierarchy(screen.id, hierarchy)
        create_widget_layers_from_hierarchy(hierarchy, content_rect, 80)
      else
        []
      end

    new_overlay_layers =
      if has_border do
        [create_modal_border_layer(this_rect, current_theme, screen.options) | overlay_acc]
      else
        overlay_acc
      end

    {content_acc ++ content_layers, new_overlay_layers}
  end

  defp render_screen_hierarchy(screen, content_rect, current_theme) do
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
  end

  defp accumulate_screen_layers(screen, {content_acc, overlay_acc}, current_theme) do
    screen_local_rect = screen.rect

    if screen_local_rect && screen.widget_hierarchy do
      has_border = screen.type in [:modal, :popover] and Map.get(screen.options, :border, false)
      content_rect = if has_border, do: inset_rect(screen_local_rect), else: screen_local_rect

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
  end

  defp inset_rect(rect) do
    %{
      x: rect.x + 1,
      y: rect.y + 1,
      width: max(1, rect.width - 2),
      height: max(1, rect.height - 2)
    }
  end

  @spec create_widget_layers_from_hierarchy(map(), map(), non_neg_integer()) :: [map()]
  def create_widget_layers_from_hierarchy(hierarchy, _rect, z_base \\ 0) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Map.keys()
    |> Enum.flat_map(fn widget_id ->
      build_widget_layer(hierarchy, widget_id, hidden, z_base)
    end)
  end

  defp create_widget_layers_tracking_dirty(hierarchy, _rect, z_base \\ 0) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    {reversed_layers, dirty_rows, stale_bounds} =
      hierarchy.widgets
      |> Map.keys()
      |> Enum.reduce({[], MapSet.new(), []}, fn widget_id, acc ->
        accumulate_widget_layer(hierarchy, widget_id, hidden, z_base, acc)
      end)

    layers = Enum.reverse(reversed_layers)

    if simple_render?() do
      {layers, MapSet.new(), []}
    else
      visible_ids = layers |> Enum.map(& &1.id) |> MapSet.new()
      vanished_bounds = collect_vanished_bounds(visible_ids)
      {layers, dirty_rows, stale_bounds ++ vanished_bounds}
    end
  end

  defp accumulate_widget_layer(hierarchy, widget_id, hidden, z_base, acc) do
    case build_widget_layer(hierarchy, widget_id, hidden, z_base) do
      [] -> acc
      widget_layers -> merge_widget_layers(widget_id, widget_layers, acc)
    end
  end

  defp merge_widget_layers(widget_id, widget_layers, {layer_acc, dirty_acc, stale_acc}) do
    {new_dirty, new_stale} =
      if simple_render?() do
        {dirty_acc, stale_acc}
      else
        track_widget_dirty(widget_id, hd(widget_layers), dirty_acc, stale_acc)
      end

    {prepend_reversed(widget_layers, layer_acc), new_dirty, new_stale}
  end

  defp prepend_reversed(items, acc), do: Enum.reduce(items, acc, &[&1 | &2])

  defp simple_render? do
    case Process.get(:drafter_simple_render) do
      nil ->
        v = System.get_env("DRAFTER_SIMPLE_RENDER") not in [nil, ""]
        Process.put(:drafter_simple_render, v)
        v

      v ->
        v
    end
  end

  defp track_widget_dirty(widget_id, layer, dirty_rows, stale_acc) do
    alpha = Map.get(layer, :opacity, 1.0)
    row_keys = Enum.map(layer.strips, &{&1.cache_key, alpha})
    prev_bounds = RenderCache.get_widget_bounds(widget_id)
    prev_row_keys = RenderCache.get_widget_rowkeys(widget_id)

    RenderCache.put_widget_rowkeys(widget_id, row_keys)
    RenderCache.put_widget_bounds(widget_id, layer.bounds)

    if prev_bounds == layer.bounds do
      changed = RenderCache.changed_rows(prev_row_keys, row_keys, layer.bounds.y)
      {MapSet.union(dirty_rows, changed), stale_acc}
    else
      changed = RenderCache.changed_rows(nil, row_keys, layer.bounds.y)
      stale = if prev_bounds, do: [prev_bounds | stale_acc], else: stale_acc
      {MapSet.union(dirty_rows, changed), stale}
    end
  end

  defp collect_vanished_bounds(visible_ids) do
    RenderCache.get_all_widget_bounds()
    |> Enum.reject(fn {id, _} -> MapSet.member?(visible_ids, id) end)
    |> Enum.map(fn {_, bounds} -> bounds end)
  end

  defp incremental_composite_or_full(all_layers, viewport, dirty_rows, stale_bounds) do
    if simple_render?() do
      LayerCompositor.composite(all_layers, viewport)
    else
      full_or_incremental(all_layers, viewport, dirty_rows, stale_bounds)
    end
  end

  defp full_or_incremental(all_layers, viewport, widget_dirty_rows, stale_bounds) do
    previous = RenderCache.get_composited()
    prev_layer_count = RenderCache.get_layer_count()

    has_cache =
      previous != nil and
        prev_layer_count == length(all_layers) and
        length(previous) == viewport.height

    cond do
      has_cache and MapSet.size(widget_dirty_rows) == 0 and stale_bounds == [] ->
        previous

      has_cache ->
        reuse_cache(all_layers, viewport, previous, widget_dirty_rows, stale_bounds)

      true ->
        trace_no_cache(all_layers, viewport, previous, prev_layer_count)
        LayerCompositor.composite(all_layers, viewport)
    end
  end

  defp reuse_cache(all_layers, viewport, previous, widget_dirty_rows, stale_bounds) do
    dirty_rows = add_bounds_rows(widget_dirty_rows, stale_bounds)

    if MapSet.size(dirty_rows) >= incremental_cutoff(viewport.height) do
      trace_full(all_layers, viewport, dirty_rows, stale_bounds)
      LayerCompositor.composite(all_layers, viewport)
    else
      ctrace(["C incr dirty=", Integer.to_string(MapSet.size(dirty_rows)), "\n"])
      LayerCompositor.composite_incremental(all_layers, viewport, previous, dirty_rows)
    end
  end

  defp trace_full(all_layers, viewport, dirty_rows, stale_bounds) do
    ctrace([
      "C full dirty=",
      Integer.to_string(MapSet.size(dirty_rows)),
      ">=h=",
      Integer.to_string(viewport.height),
      " lc=",
      Integer.to_string(length(all_layers)),
      " stale=",
      Integer.to_string(length(stale_bounds)),
      "\n"
    ])
  end

  defp trace_no_cache(all_layers, viewport, previous, prev_layer_count) do
    ctrace([
      "C full nocache prevnil=",
      to_string(previous == nil),
      " plc=",
      inspect(prev_layer_count),
      " lc=",
      Integer.to_string(length(all_layers)),
      " ph=",
      inspect(previous && length(previous)),
      " h=",
      Integer.to_string(viewport.height),
      "\n"
    ])
  end

  @incremental_cutoff_ratio 0.4

  defp incremental_cutoff(height), do: max(1, trunc(height * @incremental_cutoff_ratio))

  defp ctrace(iodata) do
    if Drafter.Trace.enabled?(), do: Drafter.Trace.log(iodata)
  end

  defp add_bounds_rows(dirty_rows, bounds_list) do
    Enum.reduce(bounds_list, dirty_rows, fn bounds, acc ->
      y_end = bounds.y + bounds.height - 1

      if y_end >= bounds.y do
        Enum.reduce(bounds.y..y_end//1, acc, &MapSet.put(&2, &1))
      else
        acc
      end
    end)
  end

  defp build_widget_layer(hierarchy, widget_id, hidden, z_base) do
    with false <- MapSet.member?(hidden, widget_id),
         widget_info when not is_nil(widget_info) <- Map.get(hierarchy.widgets, widget_id),
         widget_rect when not is_nil(widget_rect) <- Map.get(hierarchy.widget_rects, widget_id),
         false <- offscreen?(hierarchy, widget_id, widget_rect) do
      render_widget_layer(hierarchy, widget_id, widget_info, widget_rect, z_base)
    else
      _ ->
        ensure_image_cleared(hierarchy, widget_id)
        []
    end
  end

  defp ensure_image_cleared(hierarchy, widget_id) do
    case Map.get(hierarchy.widgets, widget_id) do
      %{module: module} ->
        if function_exported?(module, :image, 3) do
          WidgetStripCache.mark_visible(widget_id, false)
          Drafter.Compositor.clear_image(widget_id)
        end

      _ ->
        :ok
    end
  end

  defp offscreen?(hierarchy, widget_id, widget_rect) do
    case WidgetHierarchy.get_widget_scroll_parent(hierarchy, widget_id) do
      nil ->
        false

      scroll_parent_id ->
        scroll_info = WidgetHierarchy.get_scroll_container_info(hierarchy, scroll_parent_id)
        scroll_state = WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

        if scroll_info && scroll_state do
          viewport = scroll_info.viewport_rect
          scroll_y = Map.get(scroll_state, :scroll_offset_y, 0)
          viewport_top = viewport.y + scroll_y
          viewport_bottom = viewport_top + viewport.height
          widget_rect.y + widget_rect.height <= viewport_top or widget_rect.y >= viewport_bottom
        else
          false
        end
    end
  end

  defp render_widget_layer(hierarchy, widget_id, widget_info, widget_rect, z_base) do
    {render_rect, widget_strips} = fetch_widget_strips(widget_id, widget_info, widget_rect)
    scroll_parent_id = WidgetHierarchy.get_widget_scroll_parent(hierarchy, widget_id)

    {clipped_rect, clipped_strips} =
      if scroll_parent_id do
        apply_scroll_clipping(hierarchy, scroll_parent_id, render_rect, widget_strips)
      else
        {render_rect, widget_strips}
      end

    {overflowed_rect, overflowed_strips} =
      apply_overflow(
        clipped_rect,
        clipped_strips,
        widget_info,
        overflow_for(hierarchy, widget_id)
      )

    final_rect = apply_animated_presentation(overflowed_rect, widget_info)
    final_strips = overflowed_strips

    overlay_image(widget_id, widget_info, final_rect, paintable_region(final_strips, final_rect))

    if final_strips != [] do
      [
        LayerCompositor.widget_layer(
          widget_id,
          final_strips,
          final_rect,
          z_base,
          widget_info.module,
          layer_opacity(widget_info)
        )
      ]
    else
      []
    end
  end

  defp paintable_region([], _rect), do: false
  defp paintable_region(_strips, _rect) when false, do: false

  defp paintable_region(final_strips, final_rect) do
    if scroll_active?() or resize_active?() do
      false
    else
      %{final_rect | height: length(final_strips)}
    end
  end

  defp scroll_active?, do: Process.get(:scroll_gesture_active, false)

  defp resize_active? do
    case Process.get(:last_resize_ms) do
      nil -> false
      ms -> System.monotonic_time(:millisecond) - ms < 200
    end
  end

  defp fetch_widget_strips(widget_id, widget_info, widget_rect) do
    case WidgetStripCache.get(widget_id) do
      {cached_rect, strips} -> {cached_rect, strips}
      nil -> fetch_uncached_strips(widget_id, widget_info, widget_rect)
    end
  end

  defp overlay_image(widget_id, %{module: module} = widget_info, rect, region) do
    if function_exported?(module, :image, 3) do
      WidgetStripCache.mark_visible(widget_id, region)
      do_overlay_image(widget_id, widget_info, rect, region)
    else
      :ok
    end
  end

  defp do_overlay_image(widget_id, _widget_info, _rect, false) do
    Drafter.Compositor.clear_image(widget_id)
  end

  defp do_overlay_image(widget_id, widget_info, rect, _region) do
    Drafter.Compositor.place_image(widget_id, rect.x, rect.y)
    request_image_gen(widget_info)
  end

  defp request_image_gen(%{pid: pid}) when is_pid(pid),
    do: GenServer.cast(pid, :maybe_generate_image)

  defp request_image_gen(_widget_info), do: :ok

  defp fetch_uncached_strips(_widget_id, %{pid: pid}, _widget_rect) when is_pid(pid) do
    WidgetServer.get_render(pid)
  end

  defp fetch_uncached_strips(widget_id, widget_info, widget_rect) do
    cache = Process.get(:widget_render_cache, %{})
    cache_key = :erlang.phash2({widget_info.state, widget_rect.width, widget_rect.height})

    strips =
      case Map.get(cache, widget_id) do
        {^cache_key, cached} ->
          cached

        _ ->
          result = widget_info.module.render(widget_info.state, widget_rect)
          Process.put(:widget_render_cache, Map.put(cache, widget_id, {cache_key, result}))
          result
      end

    {widget_rect, strips}
  end

  @spec update_hierarchy_preferred_sizes(map()) :: map()
  def update_hierarchy_preferred_sizes(hierarchy) do
    Enum.reduce(hierarchy.widgets, hierarchy, fn {widget_id, widget_info}, acc ->
      case widget_info do
        %{pid: pid, module: module, state: cached} when is_pid(pid) ->
          new_state = WidgetServer.safe_get_state(pid) || cached
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
      {Collapsible, %{expanded: true, content: content, content_height: content_height}} ->
        lines =
          cond do
            is_binary(content) -> length(String.split(content, "\n"))
            is_list(content) -> content_height || 10
            true -> 1
          end

        preferred_size = 1 + lines

        WidgetHierarchy.update_preferred_size(hierarchy, widget_id, preferred_size)

      {Collapsible, %{expanded: false}} ->
        WidgetHierarchy.update_preferred_size(hierarchy, widget_id, 1)

      _ ->
        hierarchy
    end
  end

  defp apply_scroll_clipping(hierarchy, scroll_parent_id, widget_rect, widget_strips) do
    scroll_info = WidgetHierarchy.get_scroll_container_info(hierarchy, scroll_parent_id)
    scroll_state = WidgetHierarchy.get_widget_state(hierarchy, scroll_parent_id)

    if scroll_info && scroll_state do
      clip_to_scroll_viewport(widget_rect, widget_strips, scroll_info, scroll_state)
    else
      {widget_rect, widget_strips}
    end
  end

  defp clip_to_scroll_viewport(widget_rect, widget_strips, scroll_info, scroll_state) do
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
        do_clip(widget_rect, widget_strips, viewport, scroll_y, viewport_top, viewport_bottom)
    end
  end

  defp do_clip(widget_rect, widget_strips, viewport, scroll_y, viewport_top, viewport_bottom) do
    virtual_top = widget_rect.y
    start_idx = max(0, viewport_top - virtual_top)
    end_idx = min(length(widget_strips), viewport_bottom - virtual_top)

    available_width = viewport.x + viewport.width - widget_rect.x
    max_width = max(1, min(widget_rect.width, available_width))

    clipped_strips =
      widget_strips
      |> Enum.slice(start_idx, end_idx - start_idx)
      |> Enum.map(&Strip.crop(&1, max_width))

    screen_y = max(viewport.y, widget_rect.y - scroll_y)

    new_rect = %{
      widget_rect
      | y: screen_y,
        height: length(clipped_strips),
        width: min(widget_rect.width, max_width)
    }

    {new_rect, clipped_strips}
  end

  defp apply_overflow(rect, strips, _widget_info, :ellipsis) do
    {rect, Enum.map(strips, &Strip.overflow(&1, rect.width, :ellipsis))}
  end

  defp apply_overflow(rect, strips, %{state: state}, _mode) when is_map(state) do
    case Map.get(state, :text_overflow) do
      :ellipsis -> {rect, Enum.map(strips, &Strip.overflow(&1, rect.width, :ellipsis))}
      _ -> {rect, strips}
    end
  end

  defp apply_overflow(rect, strips, _widget_info, _mode), do: {rect, strips}

  defp overflow_for(hierarchy, widget_id) do
    WidgetHierarchy.widget_overflow(hierarchy, widget_id)
  end

  defp apply_animated_presentation(rect, %{state: state}) when is_map(state) do
    offset_rect(rect, Map.get(state, :offset_x, 0), Map.get(state, :offset_y, 0))
  end

  defp apply_animated_presentation(rect, _widget_info), do: rect

  defp layer_opacity(%{state: state}) when is_map(state) do
    case Map.get(state, :opacity) do
      alpha when is_number(alpha) -> alpha |> max(0.0) |> min(1.0)
      _ -> 1.0
    end
  end

  defp layer_opacity(_widget_info), do: 1.0

  defp offset_rect(rect, 0, 0), do: rect

  defp offset_rect(rect, dx, dy) when is_number(dx) and is_number(dy) do
    %{rect | x: rect.x + round(dx), y: rect.y + round(dy)}
  end

  defp offset_rect(rect, _dx, _dy), do: rect

  defp create_modal_border_layer(rect, theme, options) do
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
    bg_color = toast_bg_color(toast.variant)
    text_color = {255, 255, 255}

    lines = String.split(toast.message, "\n")
    max_width = lines |> Enum.max_by(&String.length/1) |> String.length()
    max_width = max(min(max_width + 4, screen_rect.width - 4), 20)
    content_width = max_width - 2

    wrapped_lines =
      Enum.flat_map(lines, fn line ->
        if String.length(line) <= content_width, do: [line], else: chunk_line(line, content_width)
      end)

    height = min(length(wrapped_lines) + 2, div(screen_rect.height, 3))
    stack_offset = toast.stack_index * (height + 1)
    {y, x} = toast_position(toast.position, screen_rect, max_width, height, stack_offset)

    toast_rect = %{x: x, y: y, width: max_width, height: height}
    style = %{fg: text_color, bg: bg_color}

    top_border = "┌" <> String.duplicate("─", max_width - 2) <> "┐"
    bottom_border = "└" <> String.duplicate("─", max_width - 2) <> "┘"

    content_strips =
      Enum.map(wrapped_lines, fn line ->
        padding = max_width - String.length(line) - 2
        left_pad = div(padding, 2)
        right_pad = padding - left_pad

        full_line =
          "│" <>
            String.duplicate(" ", left_pad) <> line <> String.duplicate(" ", right_pad) <> "│"

        Strip.new([Segment.new(full_line, style)])
      end)

    all_strips =
      [Strip.new([Segment.new(top_border, style)])] ++
        content_strips ++ [Strip.new([Segment.new(bottom_border, style)])]

    LayerCompositor.content_layer(toast.id, all_strips, toast_rect)
  end

  defp toast_bg_color(:success), do: {30, 100, 30}
  defp toast_bg_color(:error), do: {120, 30, 30}
  defp toast_bg_color(:warning), do: {120, 100, 30}
  defp toast_bg_color(_), do: {40, 40, 60}

  defp toast_position(:top_right, screen_rect, max_width, _height, stack_offset) do
    {2 + stack_offset, screen_rect.width - max_width - 2}
  end

  defp toast_position(:top_center, screen_rect, max_width, _height, stack_offset) do
    {2 + stack_offset, div(screen_rect.width - max_width, 2)}
  end

  defp toast_position(:top_left, _screen_rect, _max_width, _height, stack_offset) do
    {2 + stack_offset, 2}
  end

  defp toast_position(:middle_right, screen_rect, max_width, height, stack_offset) do
    {div(screen_rect.height - height, 2) - div(stack_offset, 2),
     screen_rect.width - max_width - 2}
  end

  defp toast_position(:middle_center, screen_rect, max_width, height, stack_offset) do
    {div(screen_rect.height - height, 2) - div(stack_offset, 2),
     div(screen_rect.width - max_width, 2)}
  end

  defp toast_position(:middle_left, screen_rect, _max_width, height, stack_offset) do
    {div(screen_rect.height - height, 2) - div(stack_offset, 2), 2}
  end

  defp toast_position(:bottom_left, screen_rect, _max_width, height, stack_offset) do
    {screen_rect.height - height - 2 - stack_offset, 2}
  end

  defp toast_position(:bottom_center, screen_rect, max_width, height, stack_offset) do
    {screen_rect.height - height - 2 - stack_offset, div(screen_rect.width - max_width, 2)}
  end

  defp toast_position(_, screen_rect, max_width, height, stack_offset) do
    {screen_rect.height - height - 2 - stack_offset, screen_rect.width - max_width - 2}
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
    Screen.calculate_rect(screen, base_rect)
  end

  defp create_app_background(rect, theme) do
    empty_style = %{bg: theme.background, fg: theme.text_primary}
    empty_line = String.duplicate(" ", rect.width)
    List.duplicate(Strip.new([Segment.new(empty_line, empty_style)]), max(rect.height, 0))
  end
end
