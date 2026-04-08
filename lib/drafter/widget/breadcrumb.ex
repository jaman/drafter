defmodule Drafter.Widget.Breadcrumb do
  @moduledoc """
  Renders a horizontal breadcrumb trail with keyboard and mouse navigation.

  Items are displayed as a single line separated by a configurable separator
  string. The last item is highlighted as the active/current crumb using the
  theme's primary colour and bold weight. When items exceed the available
  width, the leftmost crumbs are replaced with an ellipsis (`...`).

  ## Options

    * `:items` - list of `{label, id}` tuples or plain strings
    * `:separator` - separator between items (default `" › "`)
    * `:on_click` - callback fired with the item's id when selected
    * `:active` - whether to highlight the last item (default `true`)
    * `:style` - map of style overrides
    * `:classes` - list of theme class atoms

  ## Usage

      breadcrumb([{"Home", :home}, {"Products", :products}, "Details"])
      breadcrumb([{"Home", :home}, {"Settings", :settings}], separator: " / ", on_click: :crumb_clicked)
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:mouse_up, :keyboard]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed
  alias Drafter.Widget.Callback

  defstruct items: [],
            separator: " › ",
            on_click: nil,
            active: true,
            style: %{},
            classes: [],
            app_module: nil,
            focused: false,
            focused_index: 0

  @impl Drafter.Widget
  def mount(props) do
    items = normalize_items(Map.get(props, :items, []))

    %__MODULE__{
      items: items,
      separator: Map.get(props, :separator, " › "),
      on_click: Map.get(props, :on_click),
      active: Map.get(props, :active, true),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      focused: Map.get(props, :focused, false),
      focused_index: 0
    }
  end

  @impl Drafter.Widget
  def render(state, rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    computed_opts = [classes: state.classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:breadcrumb, state, computed_opts)

    bg = computed[:background] || {30, 30, 30}
    fg = computed[:color] || {200, 200, 200}
    primary = resolve_primary(state)
    muted = resolve_muted(state)

    segments = build_segments(state, rect.width, fg, bg, primary, muted)
    strip = Strip.new(segments)
    strip_width = Strip.width(strip)

    strip =
      if strip_width < rect.width do
        padding = Segment.new(String.duplicate(" ", rect.width - strip_width), %{fg: fg, bg: bg})
        Strip.new(strip.segments ++ [padding])
      else
        strip
      end

    [strip]
  end

  @impl Drafter.Widget
  def handle_key(:left, state) do
    new_index = max(0, state.focused_index - 1)
    {:ok, %{state | focused_index: new_index}}
  end

  def handle_key(:right, state) do
    max_index = max(0, length(state.items) - 1)
    new_index = min(max_index, state.focused_index + 1)
    {:ok, %{state | focused_index: new_index}}
  end

  def handle_key(key, state) when key in [:enter, :" "] do
    trigger_selection(state, state.focused_index)
  end

  def handle_key(_key, state) do
    {:bubble, state}
  end

  @impl Drafter.Widget
  def handle_mouse_up(x, _y, state) do
    case item_index_at(state, x) do
      nil -> {:ok, state}
      index -> trigger_selection(state, index)
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    items =
      if Map.has_key?(props, :items),
        do: normalize_items(Map.get(props, :items)),
        else: state.items

    max_index = max(0, length(items) - 1)

    %{
      state
      | items: items,
        separator: Map.get(props, :separator, state.separator),
        on_click: Map.get(props, :on_click, state.on_click),
        active: Map.get(props, :active, state.active),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module),
        focused_index: min(Map.get(props, :focused_index, state.focused_index), max_index)
    }
  end

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :breadcrumb

  def from_component_opts(items, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))
    on_click = Callback.wrap_1(Keyword.get(opts, :on_click))

    %{
      items: items,
      separator: Keyword.get(opts, :separator, " › "),
      on_click: on_click,
      active: Keyword.get(opts, :active, true),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp normalize_items(items) do
    Enum.map(items, fn
      {label, id} when is_binary(label) -> {label, id}
      label when is_binary(label) -> {label, label}
    end)
  end

  defp build_segments(state, width, fg, bg, primary, muted) do
    ctx = %{
      state: state,
      separator: state.separator,
      last_index: length(state.items) - 1,
      fg: fg,
      bg: bg,
      primary: primary,
      muted: muted
    }

    full_segments = build_item_segments(state.items, ctx)
    full_width = segments_width(full_segments)

    if full_width <= width do
      full_segments
    else
      truncate_from_left(state.items, ctx, width)
    end
  end

  defp build_item_segments(items, ctx) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn {{label, _id}, index} ->
      sep_segments =
        if index > 0,
          do: [Segment.new(ctx.separator, %{fg: ctx.muted, bg: ctx.bg})],
          else: []

      style = item_style(index, ctx)
      sep_segments ++ [Segment.new(label, style)]
    end)
  end

  defp item_style(index, ctx) do
    cond do
      ctx.state.focused and index == ctx.state.focused_index ->
        %{fg: ctx.bg, bg: ctx.primary, bold: true}

      ctx.state.active and index == ctx.last_index ->
        %{fg: ctx.primary, bg: ctx.bg, bold: true}

      true ->
        %{fg: ctx.muted, bg: ctx.bg}
    end
  end

  defp truncate_from_left(items, ctx, width) do
    ellipsis = "..."
    ellipsis_seg = Segment.new(ellipsis, %{fg: ctx.muted, bg: ctx.bg})
    available = width - String.length(ellipsis)
    sep_width = String.length(ctx.separator)

    items
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, &accumulate_truncated_item(&1, &2, ctx, sep_width, available))
    |> elem(0)
    |> then(fn segs -> [ellipsis_seg | segs] end)
  end

  defp accumulate_truncated_item({{label, _id}, index}, {acc, used}, ctx, sep_width, available) do
    label_width = String.length(label)
    needed = if acc == [], do: label_width, else: label_width + sep_width
    new_used = used + needed

    if new_used > available do
      {:halt, {acc, used}}
    else
      style = item_style(index, ctx)
      sep = if acc == [], do: [], else: [Segment.new(ctx.separator, %{fg: ctx.muted, bg: ctx.bg})]
      {:cont, {[Segment.new(label, style)] ++ sep ++ acc, new_used}}
    end
  end

  defp segments_width(segments) do
    Enum.reduce(segments, 0, fn seg, acc -> acc + String.length(seg.text) end)
  end

  defp item_index_at(state, x) do
    separator = state.separator
    sep_len = String.length(separator)

    state.items
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {{label, _id}, index}, offset ->
      label_len = String.length(label)
      item_start = if index > 0, do: offset + sep_len, else: offset
      item_end = item_start + label_len

      if x >= item_start and x < item_end do
        {:halt, {:found, index}}
      else
        {:cont, item_end}
      end
    end)
    |> case do
      {:found, index} -> index
      _ -> nil
    end
  end

  defp trigger_selection(state, index) do
    case Enum.at(state.items, index) do
      {_label, id} ->
        actions = fire_callback(state, id)
        {:ok, %{state | focused_index: index}, actions}

      nil ->
        {:ok, state}
    end
  end

  defp fire_callback(%{on_click: nil}, _id), do: []

  defp fire_callback(%{on_click: on_click}, id) when is_function(on_click, 1) do
    case on_click.(id) do
      {:app_callback, _, _} = app_callback -> [app_callback]
      _ -> []
    end
  end

  defp fire_callback(%{on_click: on_click}, _id) when is_function(on_click, 0) do
    case on_click.() do
      {:app_callback, _, _} = app_callback -> [app_callback]
      _ -> []
    end
  end

  defp fire_callback(_state, _id), do: []

  defp resolve_primary(state) do
    theme = Drafter.ThemeManager.get_current_theme()

    if state.app_module && function_exported?(state.app_module, :__theme__, 1) do
      app_theme = state.app_module.__theme__(:get)
      Map.get(app_theme, :primary, theme.primary)
    else
      theme.primary
    end
  end

  defp resolve_muted(state) do
    theme = Drafter.ThemeManager.get_current_theme()

    if state.app_module && function_exported?(state.app_module, :__theme__, 1) do
      app_theme = state.app_module.__theme__(:get)
      Map.get(app_theme, :text_muted, theme.text_muted)
    else
      theme.text_muted
    end
  end
end
