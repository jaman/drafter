defmodule Drafter.ComponentRenderer do
  @moduledoc false

  alias Drafter.{WidgetHierarchy, Theme, ThemeHelper, Binding}

  alias Drafter.Widget.{
    Box,
    Button,
    Card,
    Checkbox,
    TextInput,
    TextArea,
    OptionList,
    Label,
    DataTable,
    Tree,
    ProgressBar,
    Rule,
    Switch,
    Digits,
    Markdown,
    Placeholder,
    RadioSet,
    SelectionList,
    Collapsible,
    TabbedContent,
    Header,
    Footer,
    ScrollableContainer,
    LoadingIndicator,
    Link,
    Log,
    RichLog,
    Pretty,
    MaskedInput,
    Sparkline,
    DirectoryTree,
    Chart,
    Gauge
  }

  defp send_app_callback(callback_fn, data) when is_function(callback_fn) do
    result = callback_fn.(data)
    result
  end

  defp send_app_callback(callback_name, data) do
    {:app_callback, callback_name, data}
  end

  defp ns_widget_id(opts, app_module, type, suffix) do
    case Keyword.get(opts, :id) do
      nil ->
        mod = if app_module, do: app_module |> Module.split() |> List.last(), else: nil
        if mod, do: String.to_atom("#{mod}_#{type}_#{suffix}"), else: String.to_atom("#{type}_#{suffix}")
      id ->
        id
    end
  end

  defp create_text_input_bound_callback(opts) do
    session_pid = self()

    case Keyword.get(opts, :bind) do
      nil ->
        case Keyword.get(opts, :on_change) do
          nil ->
            nil

          callback ->
            fn {text, validation_result} ->
              send_bound_app_callback(session_pid, callback, {text, validation_result})
            end
        end

      bind_key when is_atom(bind_key) ->
        on_change = Keyword.get(opts, :on_change)

        fn {text, validation_result} ->
          send(session_pid, {:bound_state_update, bind_key, text})

          if on_change do
            send_bound_app_callback(session_pid, on_change, {text, validation_result})
          end
        end
    end
  end

  defp send_bound_app_callback(session_pid, callback_name, data) do
    case Drafter.ScreenManager.get_active_screen() do
      nil ->
        send(session_pid, {:app_event, callback_name, data})

      _screen ->
        send(session_pid, {:tui_event, {:app_callback, callback_name, data}})
    end
  end

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

    {hierarchy, _} =
      render_component(hierarchy, component_tree, rect, theme, app_state, nil, 1, app_module)

    rendered_ids = Process.get(:rendered_widget_ids, MapSet.new())
    Process.delete(:rendered_widget_ids)

    hidden_ids = MapSet.difference(old_widget_ids, rendered_ids)

    hierarchy = %{hierarchy | hidden_widgets: hidden_ids}

    hierarchy =
      cond do
        previous_focus && Map.has_key?(hierarchy.widgets, previous_focus) &&
            not MapSet.member?(hidden_ids, previous_focus) ->
          %{hierarchy | focused_widget: previous_focus}

        previous_focus && MapSet.member?(hidden_ids, previous_focus) ->
          first_focusable = find_first_focusable_widget(hierarchy)

          if first_focusable do
            WidgetHierarchy.focus_widget(hierarchy, first_focusable)
          else
            %{hierarchy | focused_widget: nil}
          end

        hierarchy.focused_widget == nil ->
          first_focusable = find_first_focusable_widget(hierarchy)

          if first_focusable do
            WidgetHierarchy.focus_widget(hierarchy, first_focusable)
          else
            hierarchy
          end

        true ->
          hierarchy
      end

    hierarchy
  end

  defp find_first_focusable_widget(hierarchy) do
    hidden = Map.get(hierarchy, :hidden_widgets, MapSet.new())

    hierarchy.widgets
    |> Enum.filter(fn {id, info} ->
      is_widget_focusable?(info.module) and not MapSet.member?(hidden, id)
    end)
    |> Enum.sort_by(fn {_id, info} -> info.order end)
    |> Enum.map(fn {id, _info} -> id end)
    |> List.first()
  end

  defp is_widget_focusable?(module) do
    if function_exported?(module, :__widget_capabilities__, 0) do
      capabilities = module.__widget_capabilities__()
      Map.get(capabilities, :focusable, false)
    else
      legacy_focusable_modules = [
        Drafter.Widget.Button,
        Drafter.Widget.TextInput,
        Drafter.Widget.TextArea,
        Drafter.Widget.Checkbox,
        Drafter.Widget.OptionList,
        Drafter.Widget.DataTable,
        Drafter.Widget.Tree,
        Drafter.Widget.DirectoryTree,
        Drafter.Widget.Switch,
        Drafter.Widget.RadioSet,
        Drafter.Widget.SelectionList,
        Drafter.Widget.Collapsible,
        Drafter.Widget.TabbedContent,
        Drafter.Widget.Link,
        Drafter.Widget.MaskedInput
      ]

      module in legacy_focusable_modules
    end
  end

  defp render_component(
         hierarchy,
         component,
         rect,
         theme,
         app_state,
         parent_id,
         id_counter,
         app_module
       ) do
    visible =
      case component do
        {_type, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
        {_type, _children, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
        {_type, _a, _b, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
        _ -> true
      end

    if not visible do
      {hierarchy, id_counter}
    else
      render_component_internal(
        hierarchy,
        component,
        rect,
        theme,
        app_state,
        parent_id,
        id_counter,
        app_module
      )
    end
  end

  defp render_component_internal(
         hierarchy,
         component,
         rect,
         theme,
         app_state,
         parent_id,
         id_counter,
         app_module
       ) do
    case component do
      {:layout, direction, children, opts} ->
        render_layout(
          hierarchy,
          direction,
          children,
          rect,
          theme,
          app_state,
          parent_id,
          id_counter,
          opts,
          app_module
        )

      {:scrollable, children, opts} ->
        render_scrollable(
          hierarchy,
          children,
          rect,
          theme,
          app_state,
          parent_id,
          id_counter,
          opts,
          app_module
        )

      {:button, text, opts} ->
        widget_id = ns_widget_id(opts, app_module, "button", id_counter)
        on_click = Keyword.get(opts, :on_click)
        button_type = Keyword.get(opts, :variant, Keyword.get(opts, :type, :default))
        custom_style = Keyword.get(opts, :style, %{})
        disabled = Keyword.get(opts, :disabled, false)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        on_click_wrapper =
          if on_click != nil and not disabled do
            fn -> send_app_callback(on_click, nil) end
          else
            nil
          end

        mount_props = %{
          text: text,
          button_type: button_type,
          style: custom_style,
          classes: classes,
          disabled: disabled,
          on_click: on_click_wrapper,
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            updated_props = %{
              text: text,
              button_type: button_type,
              classes: classes,
              disabled: disabled,
              on_click: mount_props.on_click,
              app_module: app_module
            }

            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, updated_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Button,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:checkbox, label, opts} ->
        widget_id = ns_widget_id(opts, app_module, "checkbox", id_counter)
        checked = Binding.get_bound_value(opts, app_state, Keyword.get(opts, :checked, false))
        custom_style = Keyword.get(opts, :style, %{})
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          label: label,
          checked: checked,
          style: custom_style,
          classes: classes,
          on_change: Binding.create_bound_callback(opts, :checked)
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              checked: checked,
              on_change: Binding.create_bound_callback(opts, :checked),
              classes: classes
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Checkbox,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:text_input, opts} ->
        widget_id = ns_widget_id(opts, app_module, "text_input", id_counter)
        value = Binding.get_bound_value(opts, app_state, "")
        placeholder = Keyword.get(opts, :placeholder, "")
        on_submit = Keyword.get(opts, :on_submit)
        keep_focus = Keyword.get(opts, :keep_focus, false)
        validators = Keyword.get(opts, :validators)
        disabled = Keyword.get(opts, :disabled, false)
        readonly = Keyword.get(opts, :readonly, false)
        password = Keyword.get(opts, :password, false)
        restrict = Keyword.get(opts, :restrict)
        type = Keyword.get(opts, :type, :text)
        select_on_focus = Keyword.get(opts, :select_on_focus, false)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          text: value,
          placeholder: placeholder,
          width: rect.width - 2,
          classes: classes,
          validators: validators,
          disabled: disabled,
          readonly: readonly,
          password: password,
          restrict: restrict,
          type: type,
          select_on_focus: select_on_focus,
          on_change: create_text_input_bound_callback(opts),
          on_submit:
            if on_submit do
              session_pid = self()
              fn {text, _validation_result} ->
                result = send_app_callback(on_submit, text)
                if keep_focus, do: send(session_pid, {:focus_widget, widget_id})
                result
              end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            existing_state = WidgetHierarchy.get_widget_state(hierarchy, widget_id)

            updated_props = %{
              on_change: mount_props.on_change,
              on_submit: mount_props.on_submit,
              classes: classes,
              validators: validators,
              disabled: disabled,
              readonly: readonly,
              password: password,
              restrict: restrict,
              type: type,
              select_on_focus: select_on_focus
            }

            new_width = rect.width - 2

            updated_props =
              if existing_state.width != new_width do
                Map.put(updated_props, :width, new_width)
              else
                updated_props
              end

            updated_props =
              if existing_state.placeholder != placeholder do
                Map.put(updated_props, :placeholder, placeholder)
              else
                updated_props
              end

            updated_props =
              if (Keyword.has_key?(opts, :bind) or Keyword.has_key?(opts, :value)) and
                   existing_state.text != value do
                Map.put(updated_props, :text, value)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)

            if map_size(updated_props) > 0 do
              WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
            else
              hierarchy
            end
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              TextInput,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:text_area, opts} ->
        widget_id = ns_widget_id(opts, app_module, "text_area", id_counter)
        value = Keyword.get(opts, :value, "")
        placeholder = Keyword.get(opts, :placeholder, "")
        on_change = Keyword.get(opts, :on_change)
        height = Keyword.get(opts, :height, 6)
        show_line_numbers = Keyword.get(opts, :show_line_numbers, false)
        read_only = Keyword.get(opts, :read_only, false)
        tab_behavior = Keyword.get(opts, :tab_behavior, :focus)
        tab_size = Keyword.get(opts, :tab_size, 2)
        max_checkpoints = Keyword.get(opts, :max_checkpoints, 50)
        highlight_cursor_line = Keyword.get(opts, :highlight_cursor_line, false)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          text: value,
          placeholder: placeholder,
          width: rect.width - 2,
          height: height,
          show_line_numbers: show_line_numbers,
          read_only: read_only,
          tab_behavior: tab_behavior,
          tab_size: tab_size,
          max_checkpoints: max_checkpoints,
          highlight_cursor_line: highlight_cursor_line,
          classes: classes,
          on_change:
            if on_change do
              fn new_text -> send_app_callback(on_change, new_text) end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            existing_state = WidgetHierarchy.get_widget_state(hierarchy, widget_id)

            updated_props = %{
              on_change: mount_props.on_change,
              classes: classes,
              read_only: read_only,
              tab_behavior: tab_behavior,
              tab_size: tab_size,
              max_checkpoints: max_checkpoints,
              highlight_cursor_line: highlight_cursor_line
            }

            new_width = rect.width - 2

            updated_props =
              if existing_state.width != new_width do
                Map.put(updated_props, :width, new_width)
              else
                updated_props
              end

            updated_props =
              if existing_state && existing_state.text != value do
                Map.put(updated_props, :text, value)
              else
                updated_props
              end

            updated_props =
              if existing_state.placeholder != placeholder do
                Map.put(updated_props, :placeholder, placeholder)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)

            if map_size(updated_props) > 0 do
              WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
            else
              hierarchy
            end
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              TextArea,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:data_table, opts} ->
        widget_id = ns_widget_id(opts, app_module, "data_table", id_counter)
        columns = Keyword.get(opts, :columns, [])
        data = Keyword.get(opts, :data, [])
        on_select = Keyword.get(opts, :on_select)
        on_sort = Keyword.get(opts, :on_sort)
        on_layout_change = Keyword.get(opts, :on_layout_change)
        on_row_highlight = Keyword.get(opts, :on_row_highlight)
        on_header_select = Keyword.get(opts, :on_header_select)
        height = Keyword.get(opts, :height, 15)
        actual_height = if height == :auto, do: 8, else: height

        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        custom_styles = Keyword.get(opts, :styles, %{})
        themed_styles = ThemeHelper.data_table_styles(theme, custom_styles)

        wrapped_on_layout_change =
          if on_layout_change do
            fn layout -> send_app_callback(on_layout_change, layout) end
          else
            nil
          end

        wrapped_on_row_highlight =
          if on_row_highlight do
            fn row -> send_app_callback(on_row_highlight, row) end
          else
            nil
          end

        wrapped_on_header_select =
          if on_header_select do
            fn column_key -> send_app_callback(on_header_select, column_key) end
          else
            nil
          end

        mount_props =
          Map.merge(
            %{
              columns: columns,
              data: data,
              width: rect.width,
              height: actual_height,
              selection_mode: Keyword.get(opts, :selection_mode, :single),
              show_header: Keyword.get(opts, :show_header, true),
              zebra_stripes: Keyword.get(opts, :zebra_stripes, true),
              show_scrollbars: Keyword.get(opts, :show_scrollbars, true),
              column_fit_mode: Keyword.get(opts, :column_fit_mode, :fit),
              mouse_scroll_moves_selection:
                Keyword.get(opts, :mouse_scroll_moves_selection, true),
              mouse_scroll_selects_item: Keyword.get(opts, :mouse_scroll_selects_item, false),
              sort_by: Keyword.get(opts, :sort_by),
              locked: Keyword.get(opts, :locked, true),
              resizable: Keyword.get(opts, :resizable, true),
              col_widths: Keyword.get(opts, :col_widths),
              col_order: Keyword.get(opts, :col_order),
              cursor_type: Keyword.get(opts, :cursor_type, :row),
              cell_padding: Keyword.get(opts, :cell_padding, 0),
              classes: classes,
              on_select:
                if on_select do
                  fn selected_rows -> send_app_callback(on_select, selected_rows) end
                else
                  nil
                end,
              on_sort:
                if on_sort do
                  fn column, direction ->
                    send_app_callback(on_sort, {column, direction})
                  end
                else
                  nil
                end,
              on_layout_change: wrapped_on_layout_change,
              on_row_highlight: wrapped_on_row_highlight,
              on_header_select: wrapped_on_header_select
            },
            themed_styles
          )

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            existing_state = WidgetHierarchy.get_widget_state(hierarchy, widget_id)

            updated_props = %{
              columns: columns,
              data: data,
              classes: classes,
              on_select: mount_props.on_select,
              on_sort: mount_props.on_sort,
              on_layout_change: wrapped_on_layout_change,
              on_row_highlight: wrapped_on_row_highlight,
              on_header_select: wrapped_on_header_select,
              cursor_type: Keyword.get(opts, :cursor_type, :row),
              cell_padding: Keyword.get(opts, :cell_padding, 0),
              col_widths: Keyword.get(opts, :col_widths),
              col_order: Keyword.get(opts, :col_order)
            }

            updated_props =
              if existing_state.width != rect.width do
                Map.put(updated_props, :width, rect.width)
              else
                updated_props
              end

            updated_props =
              if existing_state.height != actual_height do
                Map.put(updated_props, :height, actual_height)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)
            WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              DataTable,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:tree, opts} ->
        widget_id = ns_widget_id(opts, app_module, "tree", id_counter)
        data = Keyword.get(opts, :data, [])
        on_select = Keyword.get(opts, :on_select)
        on_expand = Keyword.get(opts, :on_expand)
        on_node_highlight = Keyword.get(opts, :on_node_highlight)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          data: data,
          width: rect.width,
          height: rect.height,
          selection_mode: Keyword.get(opts, :selection_mode, :single),
          show_icons: Keyword.get(opts, :show_icons, true),
          indent_size: Keyword.get(opts, :indent_size, 2),
          classes: classes,
          on_select:
            if on_select do
              fn selected_nodes -> send_app_callback(on_select, selected_nodes) end
            else
              nil
            end,
          on_expand:
            if on_expand do
              fn node, expanded -> send_app_callback(on_expand, {node, expanded}) end
            else
              nil
            end,
          on_node_highlight:
            if on_node_highlight do
              fn node -> send_app_callback(on_node_highlight, node) end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            existing_state = WidgetHierarchy.get_widget_state(hierarchy, widget_id)

            updated_props = %{
              data: data,
              classes: classes,
              on_select: mount_props.on_select,
              on_expand: mount_props.on_expand,
              on_node_highlight: mount_props.on_node_highlight
            }

            updated_props =
              if existing_state.width != rect.width do
                Map.put(updated_props, :width, rect.width)
              else
                updated_props
              end

            updated_props =
              if existing_state.height != rect.height do
                Map.put(updated_props, :height, rect.height)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)
            WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Tree,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:progress_bar, opts} ->
        widget_id = ns_widget_id(opts, app_module, "progress_bar", id_counter)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          progress: Keyword.get(opts, :progress, 0.0),
          max_value: Keyword.get(opts, :max_value, 100.0),
          label: Keyword.get(opts, :label),
          show_percentage: Keyword.get(opts, :show_percentage, true),
          show_value: Keyword.get(opts, :show_value, false),
          width: rect.width,
          height: rect.height,
          orientation: Keyword.get(opts, :orientation, :horizontal),
          pulse: Keyword.get(opts, :pulse, false),
          indeterminate: Keyword.get(opts, :indeterminate, false),
          bar_char: Keyword.get(opts, :bar_char, "█"),
          empty_char: Keyword.get(opts, :empty_char, "░"),
          classes: classes
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            updated_props = %{
              progress: mount_props.progress,
              max_value: mount_props.max_value,
              label: mount_props.label,
              show_percentage: mount_props.show_percentage,
              show_value: mount_props.show_value,
              pulse: mount_props.pulse,
              indeterminate: mount_props.indeterminate,
              classes: classes
            }

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)
            WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              ProgressBar,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:switch_group, group_name, switches} ->
        group_state = Map.get(app_state, group_name, nil)

        {hierarchy, id_counter} =
          Enum.reduce(switches, {hierarchy, id_counter}, fn switch_opts,
                                                            {acc_hierarchy, acc_id} ->
            label = Keyword.get(switch_opts, :label)
            value = Keyword.get(switch_opts, :value, label)
            on_change = {:switch_group_changed, group_name, value}

            widget_id = :"switch_#{group_name}_#{acc_id}"
            enabled = group_state == value

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

            new_hierarchy =
              if Map.has_key?(acc_hierarchy.widgets, widget_id) do
                updated_props = %{
                  enabled: enabled,
                  label: label,
                  on_change: on_change,
                  size: Keyword.get(switch_opts, :size, :normal)
                }

                acc_hierarchy
                |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
                |> WidgetHierarchy.update_widget_rect(widget_id, rect)
                |> WidgetHierarchy.update_widget(widget_id, updated_props)
              else
                WidgetHierarchy.add_widget(
                  acc_hierarchy,
                  widget_id,
                  Switch,
                  mount_props,
                  parent_id,
                  rect
                )
              end

            {new_hierarchy, acc_id + 1}
          end)

        {hierarchy, id_counter}

      {:switch, opts} ->
        widget_id = ns_widget_id(opts, app_module, "switch", id_counter)
        enabled_from_opts = Keyword.get(opts, :enabled)

        enabled =
          if Binding.has_binding?(opts) do
            Binding.get_bound_value(opts, app_state, false)
          else
            if enabled_from_opts == nil, do: false, else: enabled_from_opts
          end

        label = Keyword.get(opts, :label)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        on_change =
          cond do
            Keyword.has_key?(opts, :on_change) and not Binding.has_binding?(opts) ->
              Keyword.get(opts, :on_change)

            true ->
              Binding.create_bound_callback(opts, :enabled)
          end

        mount_props = %{
          enabled: enabled,
          label: label,
          width: rect.width,
          height: rect.height,
          show_labels: Keyword.get(opts, :show_labels, false),
          switch_width: Keyword.get(opts, :switch_width, 7),
          enabled_label: Keyword.get(opts, :enabled_label, "ON"),
          disabled_label: Keyword.get(opts, :disabled_label, "OFF"),
          classes: classes,
          on_change: on_change,
          size: Keyword.get(opts, :size, :normal)
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            current_widget = Map.get(hierarchy.widgets, widget_id)

            updated_props = %{
              label: label,
              on_change: mount_props.on_change,
              classes: classes,
              size: Keyword.get(opts, :size, :normal)
            }

            has_external_control =
              Binding.has_binding?(opts) or
                (Keyword.has_key?(opts, :on_change) and Keyword.has_key?(opts, :enabled))

            widget_is_on = current_widget.state.state == :on

            should_update_enabled =
              if has_external_control and not Binding.has_binding?(opts) do
                enabled != widget_is_on
              else
                has_external_control
              end

            updated_props =
              if should_update_enabled do
                Map.put(updated_props, :enabled, enabled)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)
            WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Switch,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:theme_selector, _opts} ->
        widget_id = :"theme_selector_#{id_counter}"
        available_themes = Theme.available_themes()

        theme_options =
          Enum.map(available_themes, fn {name, _theme} ->
            %{id: name, label: name, selected: false, disabled: false}
          end)

        current_theme_index =
          Enum.find_index(theme_options, fn opt ->
            opt.id == theme.name
          end) || 0

        mount_props = %{
          options: theme_options,
          visible_height: rect.height,
          expand_height: :fill,
          highlighted_index: current_theme_index,
          on_select: fn option ->
            send(self(), {:theme_change, option.id})
          end,
          on_highlight: fn option ->
            send(self(), {:theme_change, option.id})
          end
        }

        # Check if theme selector already exists and preserve its state
        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            # Widget exists - preserve its state but update rect and current theme index
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{options: theme_options})
          else
            # New widget - add it and set initial focus
            new_h =
              WidgetHierarchy.add_widget(
                hierarchy,
                widget_id,
                OptionList,
                mount_props,
                parent_id,
                rect
              )

            # Set initial focus on theme selector for better UX
            WidgetHierarchy.focus_widget(new_h, widget_id)
          end

        {new_hierarchy, id_counter + 1}

      {:option_list, items, opts} ->
        widget_id = ns_widget_id(opts, app_module, "option_list", id_counter)
        on_select = Keyword.get(opts, :on_select)
        on_highlight = Keyword.get(opts, :on_highlight)
        selected = Keyword.get(opts, :selected)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        options =
          Enum.map(items, fn
            {label, id} ->
              %{id: id, label: to_string(label), selected: id == selected, disabled: false}

            label when is_binary(label) ->
              %{id: label, label: label, selected: label == selected, disabled: false}

            %{id: id} = item ->
              Map.merge(%{selected: id == selected, disabled: false}, item)
          end)

        highlighted_index =
          if selected do
            Enum.find_index(options, fn opt -> opt.id == selected end) || 0
          else
            0
          end

        mount_props = %{
          options: options,
          visible_height: rect.height,
          expand_height: :fill,
          highlighted_index: highlighted_index,
          classes: classes,
          on_select:
            if on_select do
              fn option -> send_app_callback(on_select, option.id) end
            else
              nil
            end,
          on_highlight:
            if on_highlight do
              fn option -> send_app_callback(on_highlight, option.id) end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              options: mount_props.options,
              on_select: mount_props.on_select,
              on_highlight: mount_props.on_highlight,
              classes: classes
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              OptionList,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:label, text, opts} ->
        widget_id = ns_widget_id(opts, app_module, "label", id_counter)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        variant = Keyword.get(opts, :variant, :default)
        align = Keyword.get(opts, :align, :left)
        custom_style = Keyword.get(opts, :style, %{})

        mount_props = %{
          text: text,
          classes: classes,
          variant: variant,
          align: align,
          style: custom_style,
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              text: text,
              classes: classes,
              variant: variant,
              align: align,
              style: custom_style,
              app_module: app_module
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Label,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:box, children, opts} ->
        widget_id = ns_widget_id(opts, app_module, "box", id_counter)
        title = Keyword.get(opts, :title)
        border = Keyword.get(opts, :border, :rounded)
        padding = Keyword.get(opts, :padding, 1)
        custom_style = Keyword.get(opts, :style, %{})

        mount_props = %{
          title: title,
          border: border,
          padding: padding,
          style: custom_style,
          app_module: app_module
        }

        border_offset = if border == :none, do: 0, else: 1

        content_rect = %{
          x: rect.x + border_offset + padding,
          y: rect.y + border_offset + padding,
          width: max(1, rect.width - border_offset * 2 - padding * 2),
          height: max(1, rect.height - border_offset * 2 - padding * 2)
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              title: title,
              border: border,
              padding: padding,
              style: custom_style
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Box,
              mount_props,
              parent_id,
              rect
            )
          end

        {final_hierarchy, final_counter} =
          children
          |> List.wrap()
          |> Enum.reduce({new_hierarchy, id_counter + 1}, fn child, {h, c} ->
            render_component(h, child, content_rect, theme, app_state, widget_id, c, app_module)
          end)

        {final_hierarchy, final_counter}

      {:card, children, opts} ->
        widget_id = ns_widget_id(opts, app_module, "card", id_counter)
        title = Keyword.get(opts, :title)
        border = Keyword.get(opts, :border, :rounded)
        custom_style = Keyword.get(opts, :style, %{})
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

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

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              title: title,
              content: content_lines,
              border: border,
              style: custom_style,
              border_color: Keyword.get(opts, :border_color),
              background: Keyword.get(opts, :background),
              color: Keyword.get(opts, :color),
              classes: classes
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Card,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:digits, value, opts} ->
        widget_id = :"digits_#{id_counter}"
        text = to_string(value)
        custom_style = Keyword.get(opts, :style, %{})
        align = Keyword.get(opts, :align, :left)
        size = Keyword.get(opts, :size, :large)

        bg_data = Keyword.get(opts, :bg_data)
        color = Keyword.get(opts, :color, {0, 150, 255})
        bg_min = Keyword.get(opts, :bg_min, 0)
        bg_max = Keyword.get(opts, :bg_max)

        mount_props = %{
          text: text,
          style: custom_style,
          align: align,
          size: size,
          bg_data: bg_data,
          color: color,
          bg_min: bg_min,
          bg_max: bg_max
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{text: text, size: size, bg_data: bg_data, color: color, bg_min: bg_min, bg_max: bg_max})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Digits,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:markdown, content, opts} ->
        widget_id = :"markdown_#{id_counter}"
        custom_style = Keyword.get(opts, :style, %{})
        padding = Keyword.get(opts, :padding, 1)

        mount_props = %{
          content: content,
          style: custom_style,
          padding: padding
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{content: content})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Markdown,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:rule, opts} ->
        widget_id = ns_widget_id(opts, app_module, "rule", id_counter)

        mount_props = %{
          orientation: Keyword.get(opts, :orientation, :horizontal),
          title: Keyword.get(opts, :title),
          title_align: Keyword.get(opts, :title_align, :center),
          style: Keyword.get(opts, :style, %{}),
          line_style: Keyword.get(opts, :line_style, :solid),
          app_module: app_module
        }

        update_props = %{
          orientation: mount_props.orientation,
          title: mount_props.title,
          title_align: mount_props.title_align,
          style: mount_props.style,
          line_style: mount_props.line_style,
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, update_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Rule,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:placeholder, opts} ->
        widget_id = :"placeholder_#{id_counter}"
        text = Keyword.get(opts, :label, "Placeholder")
        custom_style = Keyword.get(opts, :style, %{})

        mount_props = %{
          text: text,
          style: custom_style
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{text: text})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Placeholder,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:static, content, opts} ->
        widget_id = :"static_#{id_counter}"
        custom_style = Keyword.get(opts, :style, %{})
        themed_style = %{fg: theme.text_primary, bg: theme.background}
        merged_style = Map.merge(themed_style, custom_style)

        mount_props = %{text: content, style: merged_style}

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{text: content, style: merged_style})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Label,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:radio_set, options, opts} ->
        widget_id = ns_widget_id(opts, app_module, "radio_set", id_counter)
        selected = Keyword.get(opts, :selected)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        on_change_fn = Binding.create_bound_callback(opts, :selected)

        mount_props = %{
          options: options,
          selected: selected,
          visible_height: rect.height,
          classes: classes,
          on_change: on_change_fn
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              options: options,
              selected: selected,
              on_change: on_change_fn,
              classes: classes
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              RadioSet,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:selection_list, options, opts} ->
        widget_id = ns_widget_id(opts, app_module, "selection_list", id_counter)
        on_change = Keyword.get(opts, :on_change)
        on_item_toggle = Keyword.get(opts, :on_item_toggle)
        selected = Keyword.get(opts, :selected, [])
        selection_mode = Keyword.get(opts, :selection_mode, :multiple)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          options: options,
          selected: selected,
          visible_height: rect.height,
          selection_mode: selection_mode,
          classes: classes,
          on_change:
            if on_change do
              fn values -> send_app_callback(on_change, values) end
            else
              nil
            end,
          on_item_toggle:
            if on_item_toggle do
              fn index, new_selected_state ->
                send_app_callback(on_item_toggle, {index, new_selected_state})
              end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              on_change: mount_props.on_change,
              on_item_toggle: mount_props.on_item_toggle,
              selection_mode: selection_mode,
              classes: classes
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              SelectionList,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:collapsible, title, content, opts} ->
        widget_id = ns_widget_id(opts, app_module, "collapsible", :erlang.phash2(title))
        expanded = Keyword.get(opts, :expanded, false)
        on_toggle = Keyword.get(opts, :on_toggle)
        content_height = Keyword.get(opts, :content_height)

        mount_props =
          %{
            title: title,
            content: content,
            expanded: expanded,
            on_toggle:
              if on_toggle do
                fn value -> send_app_callback(on_toggle, value) end
              else
                nil
              end
          }
          |> then(fn p -> if content_height, do: Map.put(p, :content_height, content_height), else: p end)

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            updated_props =
              %{content: content}
              |> then(fn p -> if content_height, do: Map.put(p, :content_height, content_height), else: p end)

            updated_props =
              if on_toggle do
                Map.put(updated_props, :on_toggle, mount_props.on_toggle)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)

            if map_size(updated_props) > 0 do
              WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
            else
              hierarchy
            end
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Collapsible,
              mount_props,
              parent_id,
              rect
            )
          end

        current_expanded =
          case WidgetHierarchy.get_widget_state(new_hierarchy, widget_id) do
            %{expanded: exp} -> exp
            _ -> expanded
          end

        if current_expanded and is_list(content) do
          effective_content_height = content_height || 10
          content_rect = %{
            x: rect.x,
            y: rect.y + 1,
            width: rect.width,
            height: min(effective_content_height, max(0, rect.height - 1))
          }

          {children_hierarchy, _} =
            render_layout(
              new_hierarchy,
              :vertical,
              content,
              content_rect,
              theme,
              app_state,
              widget_id,
              id_counter + 1,
              [],
              app_module
            )

          {children_hierarchy, id_counter + 1}
        else
          {new_hierarchy, id_counter + 1}
        end

      {:tabbed_content, tabs, opts} ->
        widget_id = ns_widget_id(opts, app_module, "tabbed_content", id_counter)
        active_tab = Keyword.get(opts, :active_tab, 0)
        title = Keyword.get(opts, :title)
        title_align = Keyword.get(opts, :title_align, :left)
        width = Keyword.get(opts, :width)
        on_tab_change = Keyword.get(opts, :on_tab_change)
        raw_classes = Keyword.get(opts, :class, [])
        raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]

        classes =
          Enum.map(raw_classes, fn
            c when is_binary(c) -> String.to_atom(c)
            c when is_atom(c) -> c
          end)

        mount_props = %{
          tabs: tabs,
          active_tab: active_tab,
          title: title,
          title_align: title_align,
          width: width,
          classes: classes,
          on_tab_change:
            if on_tab_change do
              fn value -> send_app_callback(on_tab_change, value) end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              tabs: tabs,
              title_align: title_align,
              width: width,
              classes: classes
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              TabbedContent,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:header, title, opts} ->
        widget_id = :"header_#{id_counter}"
        show_clock = Keyword.get(opts, :show_clock, true)
        clock_format = Keyword.get(opts, :clock_format, :time)

        mount_props = %{
          title: title,
          show_clock: show_clock,
          clock_format: clock_format,
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{title: title, app_module: app_module})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Header,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:footer, opts} ->
        widget_id = ns_widget_id(opts, app_module, "footer", id_counter)
        bindings = Keyword.get(opts, :bindings)

        mount_props = %{
          bindings: bindings,
          style: Keyword.get(opts, :style),
          key_style: Keyword.get(opts, :key_style),
          separator: Keyword.get(opts, :separator, " "),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              bindings: bindings,
              style: Keyword.get(opts, :style),
              key_style: Keyword.get(opts, :key_style),
              separator: Keyword.get(opts, :separator, " "),
              app_module: app_module
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Footer,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:loading_indicator, opts} ->
        widget_id = ns_widget_id(opts, app_module, "loading_indicator", id_counter)

        timestamp = System.monotonic_time(:millisecond)

        mount_props = %{
          text: Keyword.get(opts, :text, "Loading..."),
          spinner_type: Keyword.get(opts, :spinner_type, :default),
          running: Keyword.get(opts, :running, true),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module,
          _render_timestamp: timestamp
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{_render_timestamp: timestamp})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              LoadingIndicator,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:link, text, opts} ->
        widget_id = ns_widget_id(opts, app_module, "link", id_counter)

        mount_props = %{
          text: text,
          url: Keyword.get(opts, :url),
          tooltip: Keyword.get(opts, :tooltip),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              text: text,
              url: Keyword.get(opts, :url),
              app_module: app_module
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Link,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:log, opts} ->
        widget_id = ns_widget_id(opts, app_module, "log", id_counter)

        mount_props = %{
          lines: Keyword.get(opts, :lines, []),
          file_path: Keyword.get(opts, :file_path),
          max_lines: Keyword.get(opts, :max_lines, 1000),
          auto_scroll: Keyword.get(opts, :auto_scroll, true),
          wrap: Keyword.get(opts, :wrap, true),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              file_path: Keyword.get(opts, :file_path),
              lines: Keyword.get(opts, :lines),
              app_module: app_module
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Log,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:rich_log, opts} ->
        widget_id = ns_widget_id(opts, app_module, "rich_log", id_counter)

        mount_props = %{
          lines: Keyword.get(opts, :lines, []),
          max_lines: Keyword.get(opts, :max_lines, 1000),
          auto_scroll: Keyword.get(opts, :auto_scroll, true),
          wrap: Keyword.get(opts, :wrap, true),
          show_line_numbers: Keyword.get(opts, :show_line_numbers, false),
          reverse: Keyword.get(opts, :reverse, true),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              RichLog,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:pretty, data, opts} ->
        widget_id = ns_widget_id(opts, app_module, "pretty", id_counter)

        mount_props = %{
          data: data,
          expand: Keyword.get(opts, :expand, false),
          syntax_highlighting: Keyword.get(opts, :syntax_highlighting, true),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{data: data, app_module: app_module})
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Pretty,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:masked_input, opts} ->
        widget_id = ns_widget_id(opts, app_module, "masked_input", id_counter)
        raw_on_submit = Keyword.get(opts, :on_submit)

        mount_props = %{
          mask: Keyword.get(opts, :mask),
          value: Keyword.get(opts, :value, ""),
          placeholder: Keyword.get(opts, :placeholder, ""),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module,
          on_change: Keyword.get(opts, :on_change),
          on_submit:
            if raw_on_submit do
              fn value -> send_app_callback(raw_on_submit, value) end
            else
              nil
            end
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            existing_state = WidgetHierarchy.get_widget_state(hierarchy, widget_id)

            updated_props = %{
              on_change: mount_props.on_change,
              on_submit: mount_props.on_submit
            }

            updated_props =
              if existing_state.mask != mount_props.mask do
                Map.put(updated_props, :mask, mount_props.mask)
              else
                updated_props
              end

            updated_props =
              if existing_state.placeholder != mount_props.placeholder do
                Map.put(updated_props, :placeholder, mount_props.placeholder)
              else
                updated_props
              end

            hierarchy = WidgetHierarchy.update_widget_rect(hierarchy, widget_id, rect)

            if map_size(updated_props) > 0 do
              WidgetHierarchy.update_widget(hierarchy, widget_id, updated_props)
            else
              hierarchy
            end
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              MaskedInput,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:sparkline, data, opts} ->
        widget_id = ns_widget_id(opts, app_module, "sparkline", id_counter)

        mount_props = %{
          data: data,
          min_value: Keyword.get(opts, :min_value),
          max_value: Keyword.get(opts, :max_value),
          color: Keyword.get(opts, :color),
          min_color: Keyword.get(opts, :min_color),
          max_color: Keyword.get(opts, :max_color),
          summary: Keyword.get(opts, :summary, false),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              data: data,
              min_value: Keyword.get(opts, :min_value),
              max_value: Keyword.get(opts, :max_value),
              color: Keyword.get(opts, :color),
              min_color: Keyword.get(opts, :min_color),
              max_color: Keyword.get(opts, :max_color),
              summary: Keyword.get(opts, :summary, false),
              app_module: app_module
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Sparkline,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:gauge, opts} ->
        widget_id = ns_widget_id(opts, app_module, "gauge", id_counter)

        mount_props = %{
          value: Keyword.get(opts, :value, 0.0),
          label: Keyword.get(opts, :label),
          low_threshold: Keyword.get(opts, :low_threshold, 0.8),
          high_threshold: Keyword.get(opts, :high_threshold, 0.9),
          low_color: Keyword.get(opts, :low_color, {80, 200, 80}),
          mid_color: Keyword.get(opts, :mid_color, {220, 140, 0}),
          high_color: Keyword.get(opts, :high_color, {220, 60, 60}),
          track_color: Keyword.get(opts, :track_color, {55, 55, 55})
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              value: mount_props.value,
              label: mount_props.label
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Gauge,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:chart, data, opts} ->
        widget_id = ns_widget_id(opts, app_module, "chart", id_counter)

        mount_prop = %{
          data: data,
          chart_type: Keyword.get(opts, :chart_type, :line),
          marker: Keyword.get(opts, :marker, :braille),
          min_value: Keyword.get(opts, :min_value),
          max_value: Keyword.get(opts, :max_value),
          height: Keyword.get(opts, :height, 1),
          color: Keyword.get(opts, :color),
          colors: Keyword.get(opts, :colors, []),
          show_axes: Keyword.get(opts, :show_axes, false),
          show_labels: Keyword.get(opts, :show_labels, false),
          title: Keyword.get(opts, :title),
          x_labels: Keyword.get(opts, :x_labels, []),
          y_labels: Keyword.get(opts, :y_labels, []),
          animated: Keyword.get(opts, :animated, false),
          animation_speed: Keyword.get(opts, :animation_speed, 100),
          area_fill: Keyword.get(opts, :area_fill),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              data: data,
              chart_type: Keyword.get(opts, :chart_type, :line),
              marker: Keyword.get(opts, :marker, :braille),
              min_value: Keyword.get(opts, :min_value),
              max_value: Keyword.get(opts, :max_value),
              height: Keyword.get(opts, :height, 1),
              color: Keyword.get(opts, :color),
              colors: Keyword.get(opts, :colors, []),
              show_axes: Keyword.get(opts, :show_axes, false),
              show_labels: Keyword.get(opts, :show_labels, false),
              title: Keyword.get(opts, :title),
              animated: Keyword.get(opts, :animated, false),
              animation_speed: Keyword.get(opts, :animation_speed, 100),
              area_fill: Keyword.get(opts, :area_fill),
              _render_timestamp: Keyword.get(opts, :_render_timestamp, 0),
              app_module: app_module
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              Chart,
              mount_prop,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:directory_tree, opts} ->
        widget_id = ns_widget_id(opts, app_module, "directory_tree", id_counter)

        mount_props = %{
          path: Keyword.get(opts, :path, File.cwd!()),
          show_hidden: Keyword.get(opts, :show_hidden, false),
          style: Keyword.get(opts, :style),
          classes: Keyword.get(opts, :classes, []),
          app_module: app_module,
          on_select: Keyword.get(opts, :on_select),
          on_file_select:
            if cb = Keyword.get(opts, :on_file_select) do
              fn path -> send_app_callback(cb, path) end
            end,
          target: Keyword.get(opts, :target)
        }

        mount_props =
          if handles = Keyword.get(opts, :handles) do
            Map.put(mount_props, :handles, handles)
          else
            mount_props
          end

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            update_props = %{
              path: mount_props.path,
              show_hidden: mount_props.show_hidden,
              on_select: mount_props.on_select,
              on_file_select: mount_props.on_file_select,
              target: mount_props.target
            }

            update_props =
              if handles = Map.get(mount_props, :handles) do
                Map.put(update_props, :handles, handles)
              else
                update_props
              end

            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, update_props)
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              DirectoryTree,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      {:code_view, opts} ->
        alias Drafter.Widget.CodeView

        widget_id = ns_widget_id(opts, app_module, "code_view", id_counter)

        source = Keyword.get(opts, :source, Keyword.get(opts, :content, ""))
        path = Keyword.get(opts, :path)
        subscribe_to = Keyword.get(opts, :subscribe_to) || Keyword.get(opts, :id)

        hex_view = Keyword.get(opts, :hex_view, false)

        mount_props = %{
          source: source,
          path: path,
          language: Keyword.get(opts, :language, :text),
          show_line_numbers:
            Keyword.get(opts, :show_line_numbers, Keyword.get(opts, :line_numbers, true)),
          hex_view: hex_view,
          subscribe_to: subscribe_to
        }

        new_hierarchy =
          if Map.has_key?(hierarchy.widgets, widget_id) do
            hierarchy
            |> WidgetHierarchy.update_widget_parent(widget_id, parent_id)
            |> WidgetHierarchy.update_widget_rect(widget_id, rect)
            |> WidgetHierarchy.update_widget(widget_id, %{
              source: source,
              path: path,
              language: mount_props.language,
              hex_view: hex_view
            })
          else
            WidgetHierarchy.add_widget(
              hierarchy,
              widget_id,
              CodeView,
              mount_props,
              parent_id,
              rect
            )
          end

        {new_hierarchy, id_counter + 1}

      _ ->
        {hierarchy, id_counter}
    end
  end

  defp render_scrollable(
         hierarchy,
         children,
         rect,
         theme,
         app_state,
         parent_id,
         id_counter,
         opts,
         app_module
       ) do
    scroll_id = ns_widget_id(opts, app_module, "scrollable", id_counter)
    click_to_scroll = Keyword.get(opts, :click_to_scroll, false)
    scrollbar_width = 1
    content_rect = %{rect | width: rect.width - scrollbar_width}

    child_heights =
      Enum.map(children, fn child -> get_preferred_height(child, hierarchy) end)

    total_content_height = Enum.sum(child_heights)

    mount_props = %{
      id: scroll_id,
      content_height: total_content_height,
      content_width: content_rect.width,
      viewport_height: rect.height,
      viewport_width: content_rect.width,
      show_vertical_scrollbar: Keyword.get(opts, :show_vertical_scrollbar, :auto),
      show_horizontal_scrollbar: Keyword.get(opts, :show_horizontal_scrollbar, :never),
      click_to_scroll: click_to_scroll
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
          viewport_height: rect.height
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
      if footer_child == [], do: 0, else: get_preferred_height(hd(footer_child), hierarchy)

    scrollable_rect = %{content_rect | height: max(0, content_rect.height - footer_height)}

    scroll_offset_y =
      case WidgetHierarchy.get_widget_state(hierarchy, scroll_id) do
        nil -> 0
        state -> Map.get(state, :scroll_offset_y, 0)
      end

    viewport_height = scrollable_rect.height

    {updated_hierarchy, final_counter, _} =
      Enum.reduce(scrollable_children, {hierarchy, start_counter, 0}, fn child,
                                                                          {h, counter, virtual_y} ->
        child_height = get_preferred_height(child, h)

        below_viewport = virtual_y >= scroll_offset_y + viewport_height
        above_viewport = virtual_y + child_height <= scroll_offset_y

        if below_viewport or above_viewport do
          {h, counter + count_component_slots(child), virtual_y + child_height}
        else
          child_rect = %{
            x: scrollable_rect.x,
            y: scrollable_rect.y + virtual_y,
            width: scrollable_rect.width,
            height: child_height
          }

          {new_h, new_counter} =
            render_component(h, child, child_rect, theme, app_state, scroll_id, counter, app_module)

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

        render_component(
          updated_hierarchy,
          footer,
          footer_rect,
          theme,
          app_state,
          parent_id,
          final_counter,
          app_module
        )
      else
        {updated_hierarchy, final_counter}
      end

    final_hierarchy =
      Enum.reduce(updated_hierarchy.widgets, updated_hierarchy, fn {widget_id, widget_info}, h ->
        if widget_info.parent == scroll_id do
          WidgetHierarchy.set_widget_scroll_parent(h, widget_id, scroll_id)
        else
          h
        end
      end)

    {final_hierarchy, final_counter}
  end

  defp calculate_horizontal_layout_with_opts(children, rect, children_opts) do
    child_specs = Enum.zip(children, children_opts)

    {fixed_total, flexible_count, width_specs} =
      Enum.reduce(child_specs, {0, 0, []}, fn {_child_item, child_opts},
                                              {fixed_sum, flex_count, acc_specs} ->
        width = Keyword.get(child_opts, :width)
        flex = Keyword.get(child_opts, :flex, 0)

        cond do
          width ->
            {fixed_sum + width, flex_count, acc_specs ++ [{:fixed, width}]}

          flex > 0 ->
            {fixed_sum, flex_count + 1, acc_specs ++ [{:flex, flex}]}

          true ->
            {fixed_sum, flex_count + 1, acc_specs ++ [{:flex, 1}]}
        end
      end)

    available_for_flex = max(0, rect.width - fixed_total)

    {base_flex_width, remainder} =
      if flexible_count > 0 do
        {div(available_for_flex, flexible_count), rem(available_for_flex, flexible_count)}
      else
        {0, 0}
      end

    {final_widths, _} =
      Enum.reduce(width_specs, {[], remainder}, fn spec, {acc, remaining_pixels} ->
        case spec do
          {:fixed, w} ->
            {acc ++ [w], remaining_pixels}

          {:flex, _} ->
            extra = if remaining_pixels > 0, do: 1, else: 0
            {acc ++ [base_flex_width + extra], remaining_pixels - extra}
        end
      end)

    {sizes, _} =
      Enum.reduce(final_widths, {[], rect.x}, fn width, {acc, current_x} ->
        size = %{x: current_x, width: max(1, width)}
        {acc ++ [size], current_x + width}
      end)

    sizes
  end

  defp calculate_horizontal_layout(children, rect, opts) do
    children_opts = Keyword.get(opts, :children_opts, [])
    gap = Keyword.get(opts, :gap, 0)

    has_width_or_flex =
      Enum.any?(children_opts, fn child_opts ->
        Keyword.has_key?(child_opts, :width) or Keyword.has_key?(child_opts, :flex)
      end)

    if has_width_or_flex do
      calculate_horizontal_layout_with_opts(children, rect, children_opts)
    else
      calculate_horizontal_layout_no_opts(children, rect, gap)
    end
  end

  defp render_layout(
         hierarchy,
         :horizontal,
         children,
         rect,
         theme,
         app_state,
         parent_id,
         id_counter,
         opts,
         app_module
       ) do
    padding = get_padding(opts)
    content_rect = apply_padding(rect, padding)

    visible_children = Enum.filter(children, &component_visible?/1)

    children_opts =
      Enum.map(visible_children, fn
        {:layout, _direction, _child_children, child_opts} -> child_opts
        {_type, child_opts} when is_list(child_opts) -> child_opts
        {_type, _arg, child_opts} when is_list(child_opts) -> child_opts
        {_type, _arg1, _arg2, child_opts} when is_list(child_opts) -> child_opts
        _ -> []
      end)

    layout_opts = Keyword.put(opts, :children_opts, children_opts)

    child_sizes = calculate_horizontal_layout(visible_children, content_rect, layout_opts)

    {hierarchy, id_counter} =
      Enum.reduce(Enum.zip(visible_children, child_sizes), {hierarchy, id_counter}, fn {child,
                                                                                        child_size},
                                                                                       {acc_hierarchy,
                                                                                        acc_counter} ->
        child_rect = %{
          x: child_size.x,
          y: content_rect.y,
          width: child_size.width,
          height: content_rect.height
        }

        render_component(
          acc_hierarchy,
          child,
          child_rect,
          theme,
          app_state,
          parent_id,
          acc_counter,
          app_module
        )
      end)

    {hierarchy, id_counter}
  end

  defp render_layout(
         hierarchy,
         :vertical,
         children,
         rect,
         theme,
         app_state,
         parent_id,
         id_counter,
         opts,
         app_module
       ) do
    padding = get_padding(opts)
    content_rect = apply_padding(rect, padding)

    visible_children = Enum.filter(children, &component_visible?/1)

    child_width =
      case Keyword.get(opts, :width) do
        nil -> content_rect.width
        w when is_integer(w) -> min(w, content_rect.width)
        _ -> content_rect.width
      end

    {regular_children, footer_children} =
      Enum.split_with(visible_children, fn
        {:footer, _} -> false
        _ -> true
      end)

    footer_height =
      case footer_children do
        [] -> 0
        [footer_child | _] -> get_preferred_height(footer_child, hierarchy)
      end

    layout_rect = %{content_rect | height: max(0, content_rect.height - footer_height)}

    child_sizes = calculate_vertical_layout(regular_children, layout_rect, opts, hierarchy)

    {hierarchy, id_counter} =
      Enum.reduce(Enum.zip(regular_children, child_sizes), {hierarchy, id_counter}, fn {child,
                                                                                        child_size},
                                                                                       {acc_hierarchy,
                                                                                        acc_counter} ->
        child_rect = %{
          x: content_rect.x,
          y: child_size.y,
          width: child_width,
          height: child_size.height
        }

        render_component(
          acc_hierarchy,
          child,
          child_rect,
          theme,
          app_state,
          parent_id,
          acc_counter,
          app_module
        )
      end)

    {hierarchy, id_counter} =
      case footer_children do
        [] ->
          {hierarchy, id_counter}

        [footer_child | _] ->
          footer_rect = %{
            x: content_rect.x,
            y: rect.y + rect.height - footer_height,
            width: child_width,
            height: footer_height
          }

          render_component(
            hierarchy,
            footer_child,
            footer_rect,
            theme,
            app_state,
            parent_id,
            id_counter,
            app_module
          )
      end

    {hierarchy, id_counter}
  end

  defp calculate_vertical_layout(children, rect, opts, hierarchy) do
    gap = Keyword.get(opts, :gap, 0)
    num_children = length(children)
    total_gap = if num_children > 1, do: gap * (num_children - 1), else: 0

    child_specs =
      Enum.map(children, fn child ->
        {preferred, flex, has_flex} = get_child_vertical_spec(child, hierarchy)
        %{preferred: preferred, flex: flex, has_flex: has_flex}
      end)

    fixed_total =
      child_specs
      |> Enum.filter(fn spec -> not spec.has_flex end)
      |> Enum.map(fn spec -> spec.preferred end)
      |> Enum.sum()

    flex_children =
      child_specs
      |> Enum.with_index()
      |> Enum.filter(fn {spec, _idx} -> spec.has_flex end)

    total_flex =
      flex_children
      |> Enum.map(fn {spec, _idx} -> spec.flex end)
      |> Enum.sum()
      |> max(1)

    available_for_flex = max(0, rect.height - fixed_total - total_gap)

    actual_heights =
      Enum.map(child_specs, fn spec ->
        if spec.has_flex do
          flex_share = spec.flex / total_flex
          max(1, round(available_for_flex * flex_share))
        else
          spec.preferred
        end
      end)

    {sizes, _} =
      Enum.reduce(Enum.with_index(actual_heights), {[], rect.y}, fn {height, idx},
                                                                    {acc, current_y} ->
        size = %{y: current_y, height: height}
        next_y = current_y + height + if idx < num_children - 1, do: gap, else: 0
        {[size | acc], next_y}
      end)

    Enum.reverse(sizes)
  end

  defp get_child_vertical_spec(child, hierarchy) do
    case child do
      {:layout, _direction, _children, opts} ->
        flex = Keyword.get(opts, :flex, 0)
        height = Keyword.get(opts, :height)
        has_flex = flex > 0 or Keyword.has_key?(opts, :flex)

        preferred =
          cond do
            height -> height
            has_flex -> 1
            true -> get_preferred_height(child, hierarchy)
          end

        {preferred, max(flex, 1), has_flex}

      {:scrollable, _children, opts} ->
        flex = Keyword.get(opts, :flex, 0)
        height = Keyword.get(opts, :height)
        has_flex = flex > 0 or Keyword.has_key?(opts, :flex)

        preferred =
          cond do
            height -> height
            has_flex -> 1
            true -> get_preferred_height(child, hierarchy)
          end

        {preferred, max(flex, 1), has_flex}

      {:collapsible, title, content, opts} ->
        preferred =
          if hierarchy do
            collapsible_state = find_collapsible_state(hierarchy, title)

            case collapsible_state do
              %{expanded: true} ->
                estimate_collapsible_height(collapsible_state)

              nil ->
                if Keyword.get(opts, :expanded, false) do
                  estimate_collapsible_height(%{
                    content: content,
                    content_height: Keyword.get(opts, :content_height)
                  })
                else
                  1
                end

              _ ->
                1
            end
          else
            1
          end

        {preferred, 0, false}

      _ ->
        preferred = get_preferred_height(child, hierarchy)

        if preferred == :auto do
          {1, 1, true}
        else
          {preferred, 0, false}
        end
    end
  end

  defp calculate_horizontal_layout_no_opts(children, rect, gap) do
    child_colspans = Enum.map(children, &get_colspan/1)
    has_colspan = Enum.any?(child_colspans, &(&1 > 1))
    num_children = length(children)

    if has_colspan do
      total_cols = Enum.sum(child_colspans)
      total_virtual_gaps = total_cols - 1
      total_gap_space = gap * total_virtual_gaps
      available_width = rect.width - total_gap_space
      base_col_width = div(available_width, total_cols)
      remainder = rem(available_width, total_cols)

      {sizes, _, _} =
        Enum.reduce(Enum.with_index(child_colspans), {[], rect.x, remainder}, fn {colspan, idx},
                                                                                 {acc, current_x,
                                                                                  remaining_pixels} ->
          extra = min(colspan, remaining_pixels)
          cell_width = base_col_width * colspan + extra
          internal_gaps = gap * (colspan - 1)
          w = cell_width + internal_gaps
          next_x = current_x + w + if idx < num_children - 1, do: gap, else: 0
          {[%{x: current_x, width: w} | acc], next_x, remaining_pixels - extra}
        end)

      Enum.reverse(sizes)
    else
      total_gap = if num_children > 1, do: gap * (num_children - 1), else: 0
      available_width = rect.width - total_gap
      base_width = div(available_width, num_children)
      remainder = rem(available_width, num_children)

      {sizes, _, _} =
        Enum.reduce(Enum.with_index(children), {[], rect.x, remainder}, fn {_child, idx},
                                                                           {acc, current_x,
                                                                            remaining_pixels} ->
          extra = if remaining_pixels > 0, do: 1, else: 0
          w = base_width + extra
          next_x = current_x + w + if idx < num_children - 1, do: gap, else: 0
          {[%{x: current_x, width: w} | acc], next_x, remaining_pixels - extra}
        end)

      Enum.reverse(sizes)
    end
  end

  defp get_colspan(child) do
    opts =
      case child do
        {:layout, _, _, opts} -> opts
        {_, opts} when is_list(opts) -> opts
        {_, _, opts} when is_list(opts) -> opts
        {_, _, _, opts} when is_list(opts) -> opts
        _ -> []
      end

    Keyword.get(opts, :colspan, 1)
  end

  defp get_preferred_height(component, hierarchy \\ nil) do
    case component do
      {:label, _text, _opts} ->
        1

      {:button, _text, _opts} ->
        3

      {:checkbox, _label, _opts} ->
        1

      {:text_input, _opts} ->
        3

      {:text_area, opts} ->
        Keyword.get(opts, :height, 6)

      {:data_table, opts} ->
        Keyword.get(opts, :height, :auto)

      # Reasonable default for tree view
      {:tree, opts} ->
        Keyword.get(opts, :height, :auto)

      {:progress_bar, opts} ->
        orientation = Keyword.get(opts, :orientation, :horizontal)
        # Vertical needs more height
        if orientation == :vertical, do: 8, else: 3

      {:switch, _opts} ->
        3

      # Allow reasonable space for theme list
      {:theme_selector, _opts} ->
        10

      {:option_list, items, opts} ->
        Keyword.get(opts, :height, length(items))

      {:digits, _value, opts} ->
        size = Keyword.get(opts, :size, :large)
        if size == :small, do: 3, else: 5

      {:box, children, opts} ->
        border = Keyword.get(opts, :border, :rounded)
        padding = Keyword.get(opts, :padding, 1)
        border_height = if border == :none, do: 0, else: 2

        content_height =
          children |> List.wrap() |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()

        Keyword.get(opts, :height, border_height + padding * 2 + content_height)

      {:card, children, opts} ->
        padding = Keyword.get(opts, :padding, 1)

        content_height =
          children |> List.wrap() |> Enum.map(&get_preferred_height(&1, hierarchy)) |> Enum.sum()

        Keyword.get(opts, :height, padding * 2 + content_height)

      {:markdown, content, opts} ->
        lines = String.split(content, "\n") |> length()
        Keyword.get(opts, :height, max(lines, 3))

      {:rule, opts} ->
        Keyword.get(opts, :height, 1)

      {:placeholder, opts} ->
        Keyword.get(opts, :height, 3)

      {:static, _content, _opts} ->
        1

      {:loading_indicator, _opts} ->
        1

      {:chart, _data, opts} ->
        Keyword.get(opts, :height, 5)

      {:sparkline, _data, _opts} ->
        1

      {:gauge, opts} ->
        Keyword.get(opts, :height, 5)

      {:radio_set, options, opts} ->
        Keyword.get(opts, :height, length(options))

      {:selection_list, options, opts} ->
        Keyword.get(opts, :height, min(length(options), 5))

      {:collapsible, title, content, opts} ->
        if hierarchy do
          collapsible_state = find_collapsible_state(hierarchy, title)

          case collapsible_state do
            %{expanded: true} ->
              estimate_collapsible_height(collapsible_state)

            nil ->
              if Keyword.get(opts, :expanded, false) do
                estimate_collapsible_height(%{
                  content: content,
                  content_height: Keyword.get(opts, :content_height)
                })
              else
                1
              end

            _ ->
              1
          end
        else
          1
        end

      {:tabbed_content, _tabs, opts} ->
        Keyword.get(opts, :height, 8)

      {:header, _title, _opts} ->
        1

      {:footer, _opts} ->
        1

      {:link, _text, _opts} ->
        1

      {:log, opts} ->
        Keyword.get(opts, :height, 10)

      {:rich_log, opts} ->
        Keyword.get(opts, :height, 10)

      {:pretty, _data, opts} ->
        Keyword.get(opts, :height, 5)

      {:masked_input, _opts} ->
        3

      {:directory_tree, opts} ->
        Keyword.get(opts, :height, :auto)

      {:code_view, opts} ->
        Keyword.get(opts, :height, 20)

      {:layout, :horizontal, children, _opts} ->
        # Horizontal layouts take the max height of their children
        children
        |> Enum.map(&get_preferred_height/1)
        |> Enum.max(fn -> 1 end)

      {:layout, :vertical, children, _opts} ->
        children
        |> Enum.map(&get_preferred_height/1)
        |> Enum.sum()

      {:scrollable, children, opts} ->
        Keyword.get(
          opts,
          :height,
          children
          |> Enum.map(&get_preferred_height/1)
          |> Enum.sum()
        )

      _ ->
        1
    end
  end

  defp component_visible?(component) do
    case component do
      {_type, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
      {_type, _children, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
      {_type, _a, _b, opts} when is_list(opts) -> Keyword.get(opts, :visible, true)
      _ -> true
    end
  end

  defp get_padding(opts) do
    case Keyword.get(opts, :padding) do
      nil -> {0, 0, 0, 0}
      {top, right, bottom, left} -> {top, right, bottom, left}
      {vertical, horizontal} -> {vertical, horizontal, vertical, horizontal}
      n when is_integer(n) -> {n, n, n, n}
      _ -> {0, 0, 0, 0}
    end
  end

  defp apply_padding(rect, {top, right, bottom, left}) do
    %{
      x: rect.x + left,
      y: rect.y + top,
      width: max(1, rect.width - left - right),
      height: max(1, rect.height - top - bottom)
    }
  end

  defp find_collapsible_state(hierarchy, title) do
    hierarchy.widgets
    |> Enum.find_value(fn {_id, widget_info} ->
      case widget_info do
        %{module: Drafter.Widget.Collapsible, state: %{title: ^title} = state} -> state
        _ -> nil
      end
    end)
  end

  defp estimate_collapsible_height(%{content: content, content_height: content_height}) when is_list(content) do
    1 + (content_height || 10)
  end

  defp estimate_collapsible_height(%{content: content}) when is_binary(content) do
    lines = Drafter.Text.wrap(content, 80, :word)
    1 + length(lines)
  end

  defp estimate_collapsible_height(_state), do: 2

  defp count_component_slots({:layout, _dir, children, _opts}) do
    Enum.sum(Enum.map(children, &count_component_slots/1))
  end

  defp count_component_slots({:scrollable, children, _opts}) do
    1 + Enum.sum(Enum.map(children, &count_component_slots/1))
  end

  defp count_component_slots({:box, children, _opts}) do
    1 + Enum.sum(Enum.map(List.wrap(children), &count_component_slots/1))
  end

  defp count_component_slots({:card, children, _opts}) do
    1 + Enum.sum(Enum.map(List.wrap(children), &count_component_slots/1))
  end

  defp count_component_slots(_), do: 1
end
