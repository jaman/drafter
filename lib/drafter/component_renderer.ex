defmodule Drafter.ComponentRenderer do
  @moduledoc false

  alias Drafter.{CharacterSet, Layout, Theme, WidgetHierarchy}

  alias Drafter.Widget.{
    Box,
    Card,
    Collapsible,
    Label,
    OptionList,
    ScrollableContainer,
    SplitPaneDivider,
    Switch
  }

  def send_app_callback(callback_fn, data) when is_function(callback_fn), do: callback_fn.(data)
  def send_app_callback(callback_name, data), do: {:app_callback, callback_name, data}

  defp ns_widget_id(opts, app_module, type, suffix) when is_integer(suffix) do
    case Keyword.get(opts, :id) do
      nil -> keyed_or_positional_id(opts, app_module, type, suffix)
      id -> id
    end
  end

  defp keyed_or_positional_id(opts, app_module, type, suffix) do
    prefix = namespace_prefix(app_module, type)

    case Keyword.get(opts, :key) do
      nil -> String.to_atom("#{prefix}_#{suffix}")
      key -> "#{prefix}##{stringify_key(key)}"
    end
  end

  defp namespace_prefix(nil, type), do: to_string(type)

  defp namespace_prefix(app_module, type) do
    "#{app_module |> Module.split() |> List.last()}_#{type}"
  end

  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key) when is_atom(key) or is_integer(key), do: to_string(key)
  defp stringify_key(key), do: :erlang.phash2(key) |> Integer.to_string()

  defp make_ctx(theme, app_state, app_module),
    do: %{theme: theme, app_state: app_state, app_module: app_module}

  @doc """
  Convert a component tree to a widget hierarchy with automatic layout.
  """
  def render_tree(component_tree, rect, theme, app_state, existing_hierarchy \\ nil, opts \\ []) do
    app_module = Keyword.get(opts, :app_module)
    previous_focus = if existing_hierarchy, do: existing_hierarchy.focused_widget, else: nil

    old_widget_ids =
      if existing_hierarchy do
        MapSet.new(Map.keys(existing_hierarchy.widgets))
      else
        MapSet.new()
      end

    Process.put(:rendered_widget_ids, MapSet.new())

    hierarchy = existing_hierarchy || WidgetHierarchy.new()
    hierarchy = %{hierarchy | widget_scroll_parents: %{}}
    ctx = make_ctx(theme, app_state, app_module)

    {hierarchy, _} = render_component(hierarchy, component_tree, rect, ctx, nil, 1)

    rendered_ids = Process.get(:rendered_widget_ids, MapSet.new())
    Process.delete(:rendered_widget_ids)

    hidden_ids = MapSet.difference(old_widget_ids, rendered_ids)

    hierarchy = %{hierarchy | hidden_widgets: hidden_ids}
    restore_focus(hierarchy, previous_focus, hidden_ids)
  end

  defp restore_focus(hierarchy, previous_focus, hidden_ids) do
    cond do
      previous_focus && Map.has_key?(hierarchy.widgets, previous_focus) &&
          not MapSet.member?(hidden_ids, previous_focus) ->
        %{hierarchy | focused_widget: previous_focus}

      previous_focus && MapSet.member?(hidden_ids, previous_focus) ->
        focus_first_or_clear(hierarchy)

      hierarchy.focused_widget == nil ->
        focus_first_or_nil(hierarchy)

      true ->
        hierarchy
    end
  end

  defp focus_first_or_clear(hierarchy) do
    case find_first_focusable_widget(hierarchy) do
      nil -> %{hierarchy | focused_widget: nil}
      id -> WidgetHierarchy.focus_widget(hierarchy, id)
    end
  end

  defp focus_first_or_nil(hierarchy) do
    case find_first_focusable_widget(hierarchy) do
      nil -> hierarchy
      id -> WidgetHierarchy.focus_widget(hierarchy, id)
    end
  end

  defp find_first_focusable_widget(hierarchy) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Enum.filter(fn {id, info} ->
      widget_focusable?(info.module) and
        not MapSet.member?(hidden, id) and
        Map.get(info.state, :focusable) != false
    end)
    |> Enum.sort_by(fn {_id, info} -> info.order end)
    |> Enum.map(fn {id, _info} -> id end)
    |> List.first()
  end

  defp widget_focusable?(module) do
    function_exported?(module, :__widget_capabilities__, 0) and
      Map.get(module.__widget_capabilities__(), :focusable, false)
  end

  defp render_component(hierarchy, component, rect, ctx, parent_id, id_counter) do
    visible =
      case component do
        {_type, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
        {_type, _children, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
        {_type, _a, _b, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
        _ -> true
      end

    cond do
      not visible ->
        {hierarchy, id_counter}

      Layout.component_hidden?(component) ->
        {hierarchy, id_counter + Layout.count_component_slots(component)}

      true ->
        inset = Layout.apply_margin(rect, Layout.get_margin(Layout.component_opts(component)))
        render_component_internal(hierarchy, component, inset, ctx, parent_id, id_counter)
    end
  end

  defp render_component_internal(h, {:layout, direction, children, opts}, rect, ctx, pid, idc) do
    render_layout(h, direction, children, rect, ctx, pid, idc, opts)
  end

  defp render_component_internal(h, {:scrollable, children, opts}, rect, ctx, pid, idc) do
    render_scrollable(h, children, rect, ctx, pid, idc, opts)
  end

  defp render_component_internal(h, {:switch_group, group_name, switches}, rect, ctx, pid, idc) do
    render_switch_group(h, group_name, switches, rect, ctx.app_state, pid, idc)
  end

  defp render_component_internal(h, {:theme_selector, _opts}, rect, ctx, pid, idc) do
    render_theme_selector(h, rect, ctx.theme, pid, idc)
  end

  defp render_component_internal(h, {:box, children, opts}, rect, ctx, pid, idc) do
    render_box(h, children, opts, rect, ctx, pid, idc)
  end

  defp render_component_internal(h, {:grid, children, opts}, rect, ctx, pid, idc) do
    render_grid(h, children, opts, rect, ctx, pid, idc)
  end

  defp render_component_internal(h, {:card, children, opts}, rect, ctx, pid, idc) do
    render_card(h, children, opts, rect, pid, idc, ctx.app_module)
  end

  defp render_component_internal(h, {:static, content, opts}, rect, ctx, pid, idc) do
    render_static(h, content, opts, rect, ctx.theme, pid, idc)
  end

  defp render_component_internal(h, {:collapsible, title, content, opts}, rect, ctx, pid, idc) do
    render_collapsible(h, title, content, opts, rect, ctx, pid, idc)
  end

  defp render_component_internal(h, {:split_pane, children, opts}, rect, ctx, pid, idc) do
    render_split_pane(h, children, opts, rect, ctx, pid, idc)
  end

  defp render_component_internal(h, {tag, args, opts}, rect, ctx, pid, idc)
       when is_atom(tag) and is_list(opts) do
    {resolved_args, resolved_opts} = resolve_args_opts(args, opts)
    dispatch_via_registry(h, tag, resolved_args, resolved_opts, rect, ctx, pid, idc)
  end

  defp render_component_internal(h, {tag, opts}, rect, ctx, pid, idc)
       when is_atom(tag) and is_list(opts) do
    dispatch_via_registry(h, tag, nil, opts, rect, ctx, pid, idc)
  end

  defp render_component_internal(h, {module, props}, rect, ctx, pid, idc)
       when is_atom(module) and is_map(props) do
    if widget_module?(module) do
      dispatch_via_module(h, module, props, rect, ctx, pid, idc)
    else
      {h, idc}
    end
  end

  defp render_component_internal(h, _component, _rect, _ctx, _pid, idc) do
    {h, idc}
  end

  defp widget_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :mount, 1) and
      function_exported?(module, :render, 2)
  end

  defp dispatch_via_module(hierarchy, module, props, rect, ctx, parent_id, id_counter) do
    identity = props |> Map.take([:id, :key]) |> Map.to_list()
    widget_id = ns_widget_id(identity, ctx.app_module, module_tag(module), id_counter)

    mount_props =
      props
      |> Map.put_new(:app_module, ctx.app_module)
      |> Map.put(:__rect__, rect)
      |> Map.put(:__widget_id__, widget_id)

    new_hierarchy =
      hierarchy
      |> upsert_widget(widget_id, module, mount_props, parent_id, rect, [])
      |> WidgetHierarchy.set_widget_overflow(widget_id, :clip)

    {new_hierarchy, id_counter + 1}
  end

  defp module_tag(module) do
    if function_exported?(module, :component_tag, 0) do
      module.component_tag()
    else
      module |> Module.split() |> List.last() |> Macro.underscore()
    end
  end

  defp render_switch_group(
         hierarchy,
         group_name,
         switches,
         rect,
         app_state,
         parent_id,
         id_counter
       ) do
    group_state = Map.get(app_state, group_name)

    Enum.reduce(switches, {hierarchy, id_counter}, fn switch_opts, {h, idc} ->
      upsert_switch(h, switch_opts, group_name, group_state, rect, parent_id, idc)
    end)
  end

  defp upsert_switch(hierarchy, switch_opts, group_name, group_state, rect, parent_id, idc) do
    label = Keyword.get(switch_opts, :label)
    value = Keyword.get(switch_opts, :value, label)
    enabled = group_state == value
    on_change = {:switch_group_changed, group_name, value}
    widget_id = :"switch_#{group_name}_#{idc}"

    mount_props = %{
      enabled: enabled,
      label: label,
      width: rect.width,
      height: rect.height,
      show_labels: Keyword.get(switch_opts, :show_labels, false),
      switch_width: Keyword.get(switch_opts, :switch_width, 7),
      enabled_label: Keyword.get(switch_opts, :enabled_label, "ON"),
      disabled_label: Keyword.get(switch_opts, :disabled_label, "OFF"),
      on_change: on_change,
      size: Keyword.get(switch_opts, :size, :normal)
    }

    update_props = %{
      enabled: enabled,
      label: label,
      on_change: on_change,
      size: Keyword.get(switch_opts, :size, :normal)
    }

    new_h =
      upsert_named_widget(
        hierarchy,
        widget_id,
        Switch,
        mount_props,
        update_props,
        parent_id,
        rect
      )

    {new_h, idc + 1}
  end

  defp render_theme_selector(hierarchy, rect, theme, parent_id, id_counter) do
    widget_id = :"theme_selector_#{id_counter}"
    theme_options = build_theme_options()
    session = self()

    mount_props = %{
      options: theme_options,
      visible_height: rect.height,
      expand_height: :fill,
      highlighted_index: find_theme_index(theme_options, theme),
      on_select: fn option -> send(session, {:theme_change, option.id}) end,
      on_highlight: fn option -> send(session, {:theme_change, option.id}) end
    }

    new_hierarchy =
      if Map.has_key?(hierarchy.widgets, widget_id) do
        hierarchy
        |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
        |> WidgetHierarchy.update_widget_rect(widget_id, rect)
        |> WidgetHierarchy.update_widget(widget_id, %{options: theme_options})
      else
        hierarchy
        |> WidgetHierarchy.add_widget(widget_id, OptionList, mount_props, parent_id, rect)
        |> WidgetHierarchy.focus_widget(widget_id)
      end

    {new_hierarchy, id_counter + 1}
  end

  defp build_theme_options do
    Enum.map(Theme.available_themes(), fn {name, _} ->
      %{id: name, label: name, selected: false, disabled: false}
    end)
  end

  defp find_theme_index(options, theme) do
    Enum.find_index(options, fn opt -> opt.id == theme.name end) || 0
  end

  defp render_box(hierarchy, children, opts, rect, ctx, parent_id, id_counter) do
    widget_id = ns_widget_id(opts, ctx.app_module, "box", id_counter)
    title = Keyword.get(opts, :title)
    border = Keyword.get(opts, :border, CharacterSet.style(:border) || :rounded)
    padding = Keyword.get(opts, :padding, CharacterSet.style(:padding) || 1)
    custom_style = Keyword.get(opts, :style, %{})
    border_offset = if border == :none, do: 0, else: 1

    mount_props = %{
      title: title,
      border: border,
      padding: padding,
      style: custom_style,
      app_module: ctx.app_module
    }

    update_props = %{title: title, border: border, padding: padding, style: custom_style}

    content_rect = %{
      x: rect.x + border_offset + padding,
      y: rect.y + border_offset + padding,
      width: max(1, rect.width - border_offset * 2 - padding * 2),
      height: max(1, rect.height - border_offset * 2 - padding * 2)
    }

    new_h =
      upsert_named_widget(hierarchy, widget_id, Box, mount_props, update_props, parent_id, rect)

    wrapped = List.wrap(children)

    case wrapped do
      [] ->
        {new_h, id_counter + 1}

      [single] ->
        render_component(new_h, single, content_rect, ctx, widget_id, id_counter + 1)

      many ->
        render_layout(new_h, :vertical, many, content_rect, ctx, widget_id, id_counter + 1, [])
    end
  end

  defp render_card(hierarchy, children, opts, rect, parent_id, id_counter, app_module) do
    widget_id = ns_widget_id(opts, app_module, "card", id_counter)
    title = Keyword.get(opts, :title)
    border = Keyword.get(opts, :border, CharacterSet.style(:border) || :rounded)
    custom_style = Keyword.get(opts, :style, %{})
    classes = normalize_classes(Keyword.get(opts, :class, []))
    content_lines = List.wrap(children) |> Enum.map(&to_string/1)

    mount_props = %{
      title: title,
      content: content_lines,
      border: border,
      style: custom_style,
      border_color: Keyword.get(opts, :border_color),
      background: Keyword.get(opts, :background),
      color: Keyword.get(opts, :color),
      classes: classes,
      app_module: app_module
    }

    update_props = Map.delete(mount_props, :app_module)

    new_h =
      upsert_named_widget(hierarchy, widget_id, Card, mount_props, update_props, parent_id, rect)

    {new_h, id_counter + 1}
  end

  defp render_static(hierarchy, content, opts, rect, theme, parent_id, id_counter) do
    widget_id = :"static_#{id_counter}"
    custom_style = Keyword.get(opts, :style, %{})
    merged_style = Map.merge(%{fg: theme.text_primary, bg: theme.background}, custom_style)
    props = %{text: content, style: merged_style}

    new_h = upsert_named_widget(hierarchy, widget_id, Label, props, props, parent_id, rect)
    {new_h, id_counter + 1}
  end

  @collapsible_id_space 4096

  defp render_collapsible(hierarchy, title, content, opts, rect, ctx, parent_id, id_counter) do
    widget_id =
      ns_widget_id(
        opts,
        ctx.app_module,
        "collapsible",
        :erlang.phash2(title, @collapsible_id_space)
      )

    expanded = Keyword.get(opts, :expanded, false)
    on_toggle = Keyword.get(opts, :on_toggle)
    content_height = Keyword.get(opts, :content_height)

    on_toggle_fn =
      if on_toggle, do: fn value -> send_app_callback(on_toggle, value) end, else: nil

    mount_props =
      %{title: title, content: content, expanded: expanded, on_toggle: on_toggle_fn}
      |> then(fn p ->
        if content_height, do: Map.put(p, :content_height, content_height), else: p
      end)

    new_hierarchy =
      upsert_collapsible_widget(
        hierarchy,
        widget_id,
        mount_props,
        content_height,
        on_toggle_fn,
        rect,
        parent_id
      )

    current_expanded =
      case WidgetHierarchy.get_widget_state(new_hierarchy, widget_id) do
        %{expanded: exp} -> exp
        _ -> expanded
      end

    child_slots =
      if is_list(content) do
        Enum.sum(Enum.map(content, &Layout.count_component_slots/1))
      else
        0
      end

    next_counter = id_counter + 1 + child_slots

    if current_expanded and is_list(content) do
      render_collapsible_content(
        new_hierarchy,
        content,
        content_height,
        rect,
        ctx,
        widget_id,
        id_counter,
        next_counter
      )
    else
      {new_hierarchy, next_counter}
    end
  end

  defp render_collapsible_content(
         hierarchy,
         content,
         content_height,
         rect,
         ctx,
         parent_id,
         id_counter,
         next_counter
       ) do
    effective_content_height = content_height || 10

    content_rect = %{
      x: rect.x,
      y: rect.y + 1,
      width: rect.width,
      height: min(effective_content_height, max(0, rect.height - 1))
    }

    case Map.get(ctx, :scroll_viewport) do
      %{visible_top: visible_top, visible_bottom: visible_bottom} ->
        {culled_h, _} =
          render_children_culled(
            hierarchy,
            content,
            content_rect,
            ctx,
            parent_id,
            id_counter + 1,
            visible_top,
            visible_bottom
          )

        {culled_h, next_counter}

      _ ->
        {children_hierarchy, _} =
          render_layout(
            hierarchy,
            :vertical,
            content,
            content_rect,
            ctx,
            parent_id,
            id_counter + 1,
            []
          )

        {children_hierarchy, next_counter}
    end
  end

  defp render_children_culled(
         hierarchy,
         children,
         content_rect,
         ctx,
         parent_id,
         start_counter,
         visible_top,
         visible_bottom
       ) do
    child_sizes = Layout.calculate_vertical_layout(children, content_rect, [], hierarchy)

    Enum.reduce(Enum.zip(children, child_sizes), {hierarchy, start_counter}, fn {child,
                                                                                 child_size},
                                                                                {acc_h, acc_idc} ->
      child_rect = %{
        x: content_rect.x,
        y: child_size.y,
        width: content_rect.width,
        height: child_size.height
      }

      above = child_rect.y + child_rect.height <= visible_top
      below = child_rect.y >= visible_bottom

      if above or below do
        {acc_h, acc_idc + Layout.count_component_slots(child)}
      else
        render_component(acc_h, child, child_rect, ctx, parent_id, acc_idc)
      end
    end)
  end

  defp upsert_collapsible_widget(
         hierarchy,
         widget_id,
         mount_props,
         content_height,
         on_toggle_fn,
         rect,
         parent_id
       ) do
    if Map.has_key?(hierarchy.widgets, widget_id) do
      updated_props = collapsible_update_props(mount_props.content, content_height, on_toggle_fn)

      hierarchy
      |> WidgetHierarchy.update_widget_rect(widget_id, rect)
      |> maybe_update_widget(widget_id, updated_props)
    else
      WidgetHierarchy.add_widget(hierarchy, widget_id, Collapsible, mount_props, parent_id, rect)
    end
  end

  defp collapsible_update_props(content, content_height, on_toggle_fn) do
    %{content: content}
    |> put_if(content_height, :content_height, content_height)
    |> put_if(on_toggle_fn, :on_toggle, on_toggle_fn)
  end

  defp put_if(map, condition, key, value) do
    if condition, do: Map.put(map, key, value), else: map
  end

  defp maybe_update_widget(hierarchy, _widget_id, props) when map_size(props) == 0, do: hierarchy

  defp maybe_update_widget(hierarchy, widget_id, props),
    do: WidgetHierarchy.update_widget(hierarchy, widget_id, props)

  defp upsert_named_widget(
         hierarchy,
         widget_id,
         module,
         mount_props,
         update_props,
         parent_id,
         rect
       ) do
    if Map.has_key?(hierarchy.widgets, widget_id) do
      hierarchy
      |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
      |> WidgetHierarchy.update_widget_rect(widget_id, rect)
      |> WidgetHierarchy.update_widget(widget_id, update_props)
    else
      WidgetHierarchy.add_widget(hierarchy, widget_id, module, mount_props, parent_id, rect)
    end
  end

  defp normalize_classes(classes), do: Drafter.Util.normalize_classes(classes)

  defp dispatch_via_registry(hierarchy, tag, args, opts, rect, ctx, parent_id, id_counter) do
    case Drafter.Widget.Registry.lookup(tag) do
      nil ->
        {hierarchy, id_counter}

      module ->
        widget_id = ns_widget_id(opts, ctx.app_module, tag, id_counter)

        enriched_opts =
          Keyword.merge(opts,
            __rect__: rect,
            __app_state__: ctx.app_state,
            __theme__: ctx.theme,
            __app_module__: ctx.app_module,
            __widget_id__: widget_id
          )

        mount_props = module.from_component_opts(args, enriched_opts)

        new_hierarchy =
          hierarchy
          |> upsert_widget(widget_id, module, mount_props, parent_id, rect, enriched_opts)
          |> WidgetHierarchy.set_widget_overflow(widget_id, overflow_option(opts))

        {new_hierarchy, id_counter + 1}
    end
  end

  defp overflow_option(opts) do
    case Keyword.get(opts, :text_overflow) do
      :ellipsis -> :ellipsis
      _ -> :clip
    end
  end

  defp upsert_widget(hierarchy, widget_id, module, mount_props, parent_id, rect, opts) do
    if Map.has_key?(hierarchy.widgets, widget_id) do
      existing_state = WidgetHierarchy.get_widget_state(hierarchy, widget_id)
      update_props = module.update_props_from_mount(mount_props, existing_state, opts)

      hierarchy
      |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
      |> WidgetHierarchy.update_widget_rect(widget_id, rect)
      |> WidgetHierarchy.update_widget(widget_id, update_props)
    else
      server_opts = extract_data_channel_opts(opts)

      WidgetHierarchy.add_widget(
        hierarchy,
        widget_id,
        module,
        mount_props,
        parent_id,
        rect,
        server_opts
      )
    end
  end

  defp resolve_args_opts(args, opts) when is_list(args) and is_list(opts) and opts == [] do
    if Keyword.keyword?(args) do
      {nil, args}
    else
      {args, opts}
    end
  end

  defp resolve_args_opts(args, opts), do: {args, opts}

  defp extract_data_channel_opts(opts) do
    []
    |> maybe_add_opt(opts, :buffer)
    |> maybe_add_opt(opts, :refresh)
    |> maybe_add_opt(opts, :image_throttle)
  end

  defp maybe_add_opt(acc, opts, key) do
    case Keyword.get(opts, key) do
      nil -> acc
      val -> [{key, val} | acc]
    end
  end

  defp render_scrollable(hierarchy, children, rect, ctx, parent_id, id_counter, opts) do
    scroll_id = ns_widget_id(opts, ctx.app_module, "scrollable", id_counter)
    click_to_scroll = Keyword.get(opts, :click_to_scroll, false)
    scrollbar_width = 1
    content_rect = %{rect | width: rect.width - scrollbar_width}

    child_heights =
      Enum.map(children, fn child -> Layout.get_preferred_height(child, hierarchy) end)

    total_content_height = Enum.sum(child_heights)

    focusable = Keyword.get(opts, :focusable, true)

    mount_props = %{
      id: scroll_id,
      content_height: total_content_height,
      content_width: content_rect.width,
      viewport_height: rect.height,
      viewport_width: content_rect.width,
      show_vertical_scrollbar: Keyword.get(opts, :show_vertical_scrollbar, :auto),
      show_horizontal_scrollbar: Keyword.get(opts, :show_horizontal_scrollbar, :never),
      click_to_scroll: click_to_scroll,
      focusable: focusable
    }

    scrollbar_rect = %{
      x: rect.x + rect.width - scrollbar_width,
      y: rect.y,
      width: scrollbar_width,
      height: rect.height
    }

    hierarchy =
      if Map.has_key?(hierarchy.widgets, scroll_id) do
        hierarchy
        |> WidgetHierarchy.update_widget_rect(scroll_id, scrollbar_rect)
        |> WidgetHierarchy.update_widget(scroll_id, %{
          content_height: total_content_height,
          viewport_height: rect.height,
          focusable: focusable
        })
      else
        WidgetHierarchy.add_widget(
          hierarchy,
          scroll_id,
          ScrollableContainer,
          mount_props,
          parent_id,
          scrollbar_rect
        )
      end

    hierarchy =
      WidgetHierarchy.register_scroll_container(
        hierarchy,
        scroll_id,
        content_rect,
        total_content_height,
        content_rect.width,
        click_to_scroll
      )

    start_counter = id_counter + 1

    {scrollable_children, footer_child} =
      Enum.split_while(children, fn
        {:footer, _} -> false
        _ -> true
      end)

    footer_height =
      if footer_child == [], do: 0, else: Layout.get_preferred_height(hd(footer_child), hierarchy)

    scrollable_rect = %{content_rect | height: max(0, content_rect.height - footer_height)}

    scroll_offset_y =
      case WidgetHierarchy.get_widget_state(hierarchy, scroll_id) do
        nil -> 0
        state -> Map.get(state, :scroll_offset_y, 0)
      end

    viewport_height = scrollable_rect.height

    scroll_ctx =
      Map.put(ctx, :scroll_viewport, %{
        visible_top: scrollable_rect.y + scroll_offset_y,
        visible_bottom: scrollable_rect.y + scroll_offset_y + viewport_height
      })

    {updated_hierarchy, final_counter, _} =
      Enum.reduce(scrollable_children, {hierarchy, start_counter, 0}, fn child,
                                                                         {h, counter, virtual_y} ->
        child_height = Layout.get_preferred_height(child, h)

        below_viewport = virtual_y >= scroll_offset_y + viewport_height
        above_viewport = virtual_y + child_height <= scroll_offset_y

        if below_viewport or above_viewport do
          {h, counter + Layout.count_component_slots(child), virtual_y + child_height}
        else
          child_rect = %{
            x: scrollable_rect.x,
            y: scrollable_rect.y + virtual_y,
            width: scrollable_rect.width,
            height: child_height
          }

          {new_h, new_counter} =
            render_component(h, child, child_rect, scroll_ctx, scroll_id, counter)

          {new_h, new_counter, virtual_y + child_height}
        end
      end)

    {updated_hierarchy, final_counter} =
      if footer_child != [] do
        footer = hd(footer_child)

        footer_rect = %{
          x: content_rect.x,
          y: rect.y + rect.height - footer_height,
          width: content_rect.width,
          height: footer_height
        }

        render_component(updated_hierarchy, footer, footer_rect, ctx, parent_id, final_counter)
      else
        {updated_hierarchy, final_counter}
      end

    final_hierarchy =
      Enum.reduce(updated_hierarchy.widgets, updated_hierarchy, fn {widget_id, _widget_info}, h ->
        if descendant_of?(updated_hierarchy, widget_id, scroll_id) do
          WidgetHierarchy.set_widget_scroll_parent(h, widget_id, scroll_id)
        else
          h
        end
      end)

    {final_hierarchy, final_counter}
  end

  defp descendant_of?(_hierarchy, widget_id, ancestor_id) when widget_id == ancestor_id, do: false

  defp descendant_of?(hierarchy, widget_id, ancestor_id) do
    case Map.get(hierarchy.widgets, widget_id) do
      nil -> false
      %{parent: ^ancestor_id} -> true
      %{parent: nil} -> false
      %{parent: parent_id} -> descendant_of?(hierarchy, parent_id, ancestor_id)
    end
  end

  defp render_layout(hierarchy, :horizontal, children, rect, ctx, parent_id, id_counter, opts) do
    padding = Layout.get_padding(opts)
    content_rect = Layout.apply_padding(rect, padding)

    visible_children = Enum.filter(children, &Layout.component_visible?/1)

    children_opts =
      Enum.map(visible_children, fn
        {:layout, _direction, _child_children, child_opts} -> child_opts
        {_type, child_opts} when is_list(child_opts) -> child_opts
        {_type, _arg, child_opts} when is_list(child_opts) -> child_opts
        {_type, _arg1, _arg2, child_opts} when is_list(child_opts) -> child_opts
        _ -> []
      end)

    layout_opts = Keyword.put(opts, :children_opts, children_opts)

    child_sizes = Layout.calculate_horizontal_layout(visible_children, content_rect, layout_opts)

    {hierarchy, id_counter} =
      Enum.reduce(Enum.zip(visible_children, child_sizes), {hierarchy, id_counter}, fn {child,
                                                                                        child_size},
                                                                                       {acc_h,
                                                                                        acc_idc} ->
        child_rect = %{
          x: child_size.x,
          y: content_rect.y,
          width: child_size.width,
          height: content_rect.height
        }

        render_component(acc_h, child, child_rect, ctx, parent_id, acc_idc)
      end)

    {hierarchy, id_counter}
  end

  defp render_layout(hierarchy, :vertical, children, rect, ctx, parent_id, id_counter, opts) do
    padding = Layout.get_padding(opts)
    content_rect = Layout.apply_padding(rect, padding)

    visible_children = Enum.filter(children, &Layout.component_visible?/1)

    child_width =
      case Keyword.get(opts, :width) do
        nil -> content_rect.width
        w when is_integer(w) -> min(w, content_rect.width)
        _ -> content_rect.width
      end

    {docked, regular_children} = Layout.partition_docked(visible_children)
    {layout_rect, docked_rects} = reserve_docked(content_rect, docked, hierarchy)

    child_sizes = Layout.calculate_vertical_layout(regular_children, layout_rect, opts, hierarchy)

    {hierarchy, id_counter} =
      Enum.reduce(Enum.zip(regular_children, child_sizes), {hierarchy, id_counter}, fn {child,
                                                                                        child_size},
                                                                                       {acc_h,
                                                                                        acc_idc} ->
        child_rect = %{
          x: content_rect.x,
          y: child_size.y,
          width: child_width,
          height: child_size.height
        }

        render_component(acc_h, child, child_rect, ctx, parent_id, acc_idc)
      end)

    Enum.reduce(docked_rects, {hierarchy, id_counter}, fn {child, docked_rect}, {h, idc} ->
      render_component(h, child, docked_rect, ctx, parent_id, idc)
    end)
  end

  defp reserve_docked(rect, docked, hierarchy) do
    Enum.reduce(docked, {rect, []}, fn {child, edge}, {remaining, placed} ->
      {taken, left} = carve(remaining, edge, dock_extent(child, edge, hierarchy, remaining))
      {left, placed ++ [{child, taken}]}
    end)
  end

  defp dock_extent(child, edge, hierarchy, rect) when edge in [:top, :bottom] do
    min(Layout.get_preferred_height(child, hierarchy), rect.height)
  end

  defp dock_extent(child, _edge, _hierarchy, rect) do
    child |> Layout.component_opts() |> Keyword.get(:width, div(rect.width, 4)) |> min(rect.width)
  end

  defp carve(rect, :top, size) do
    {%{rect | height: size}, %{rect | y: rect.y + size, height: max(0, rect.height - size)}}
  end

  defp carve(rect, :bottom, size) do
    {%{rect | y: rect.y + rect.height - size, height: size},
     %{rect | height: max(0, rect.height - size)}}
  end

  defp carve(rect, :left, size) do
    {%{rect | width: size}, %{rect | x: rect.x + size, width: max(0, rect.width - size)}}
  end

  defp carve(rect, :right, size) do
    {%{rect | x: rect.x + rect.width - size, width: size},
     %{rect | width: max(0, rect.width - size)}}
  end

  defp render_grid(hierarchy, children, opts, rect, ctx, parent_id, id_counter) do
    visible = Enum.filter(List.wrap(children), &Layout.component_visible?/1)
    cells = Layout.calculate_grid_layout(visible, rect, opts)

    Enum.reduce(Enum.zip(visible, cells), {hierarchy, id_counter}, fn {child, cell}, {h, idc} ->
      render_component(h, child, cell, ctx, parent_id, idc)
    end)
  end

  defp render_split_pane(hierarchy, children, opts, rect, ctx, parent_id, id_counter) do
    orientation = Keyword.get(opts, :orientation, :horizontal)
    default_ratio = Keyword.get(opts, :ratio, 0.5)

    divider_id =
      case Keyword.get(opts, :id) do
        nil -> ns_widget_id(opts, ctx.app_module, "split_divider", id_counter)
        id -> String.to_atom("#{id}_divider")
      end

    divider_size = 1

    total_size = if orientation == :horizontal, do: rect.width, else: rect.height

    divider_pos = get_divider_pos(hierarchy, divider_id, default_ratio, total_size)

    {pane1_rect, divider_rect, pane2_rect} =
      pane_rects_from_pos(orientation, rect, divider_pos, divider_size)

    divider_mount = %{
      id: divider_id,
      ratio: default_ratio,
      orientation: orientation,
      total_size: total_size,
      show_handle: Keyword.get(opts, :show_handle, true),
      resize_mode: Keyword.get(opts, :resize_mode, :quick)
    }

    divider_update = %{orientation: orientation, total_size: total_size}

    hierarchy =
      if Map.has_key?(hierarchy.widgets, divider_id) do
        hierarchy
        |> WidgetHierarchy.update_widget_parent(divider_id, parent_id)
        |> WidgetHierarchy.update_widget_rect(divider_id, divider_rect)
        |> WidgetHierarchy.update_widget(divider_id, divider_update)
      else
        WidgetHierarchy.add_widget(
          hierarchy,
          divider_id,
          SplitPaneDivider,
          divider_mount,
          parent_id,
          divider_rect
        )
      end

    {hierarchy, id_counter} =
      case children do
        [child1 | [child2 | _]] ->
          {h, idc} =
            render_component(hierarchy, child1, pane1_rect, ctx, parent_id, id_counter + 1)

          render_component(h, child2, pane2_rect, ctx, parent_id, idc)

        [child1] ->
          render_component(hierarchy, child1, pane1_rect, ctx, parent_id, id_counter + 1)

        [] ->
          {hierarchy, id_counter + 1}
      end

    {hierarchy, id_counter}
  end

  defp pane_rects_from_pos(:horizontal, rect, pos, divider_size) do
    pane1_width = max(1, pos)
    pane2_width = max(1, rect.width - pane1_width - divider_size)

    pane1 = %{x: rect.x, y: rect.y, width: pane1_width, height: rect.height}
    divider = %{x: rect.x + pane1_width, y: rect.y, width: divider_size, height: rect.height}

    pane2 = %{
      x: rect.x + pane1_width + divider_size,
      y: rect.y,
      width: pane2_width,
      height: rect.height
    }

    {pane1, divider, pane2}
  end

  defp pane_rects_from_pos(:vertical, rect, pos, divider_size) do
    pane1_height = max(1, pos)
    pane2_height = max(1, rect.height - pane1_height - divider_size)

    pane1 = %{x: rect.x, y: rect.y, width: rect.width, height: pane1_height}
    divider = %{x: rect.x, y: rect.y + pane1_height, width: rect.width, height: divider_size}

    pane2 = %{
      x: rect.x,
      y: rect.y + pane1_height + divider_size,
      width: rect.width,
      height: pane2_height
    }

    {pane1, divider, pane2}
  end

  defp get_divider_pos(hierarchy, divider_id, default_ratio, total_size) do
    case WidgetHierarchy.get_widget_state(hierarchy, divider_id) do
      nil ->
        round(default_ratio * (total_size - 1))

      state ->
        SplitPaneDivider.effective_pos(%{
          fixed_pos: Map.get(state, :fixed_pos),
          ratio: Map.get(state, :ratio, default_ratio),
          total_size: total_size
        })
    end
  end
end
