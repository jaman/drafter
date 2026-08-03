defmodule Drafter.Widget.Breadcrumb do
  @moduledoc """
  Renders a horizontal breadcrumb trail with keyboard and mouse navigation.

  Items are displayed as a single line separated by a configurable separator
  string. The last item is highlighted as the active/current crumb using the
  theme's primary colour and bold weight. When items exceed the available
  width, the leftmost crumbs are replaced with an ellipsis (`...`).

  ## Component tag

  Tag `:breadcrumb`, built by `Drafter.App` as `{:breadcrumb, items, opts}`:

      breadcrumb(items, opts)

  The positional argument becomes `:items`. `from_component_opts/2` wraps
  `:on_click` with `Drafter.Widget.Callback`, so it may be given as an atom event
  name.

  ## Options

    * `:items` - `[{String.t(), term()} | String.t()]`. Default `[]`. Supplied
      positionally through the `breadcrumb/2` element. A plain string is used as
      both label and id. A label that is not a binary raises `FunctionClauseError`
    * `:separator` - `t:String.t/0` drawn between items. Default `" › "`
    * `:on_click` - atom event name, or a function of arity 1 receiving the clicked
      item's id, or of arity 0. Default `nil`
    * `:active` - `t:boolean/0`, highlight the last item as the current crumb.
      Default `true`
    * `:style` - `t:map/0` of style overrides. Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:focused` - `t:boolean/0` initial focus flag, read by `mount/1` only.
      Default `false`
    * `:app_module` - module supplying a per-app theme, passed by the renderer as
      `:__app_module__`. Default `nil`

  `update/2` re-reads `:items`, `:separator`, `:on_click`, `:active`, `:style`,
  `:classes`, `:app_module` and `:focused_index`, so all of those are live. It does
  not re-read `:focused`, which is owned by the focus system after mount.

  ## Widget value

  `Drafter.get_widget_value/1` is not implemented for this widget; the selected
  crumb is reported through `:on_click` instead.

  ## Key bindings

  Handled when focused: `:left` and `:right` move `:focused_index` within the item
  range, `:enter` and `:" "` fire `:on_click` for the focused crumb. Every other key
  bubbles. A mouse release inside a crumb's label selects that crumb.

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

  @type item :: {String.t(), term()}

  @type t :: %__MODULE__{
          items: [item()],
          separator: String.t(),
          on_click: (term() -> any()) | (-> any()) | nil,
          active: boolean(),
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          focused: boolean(),
          focused_index: non_neg_integer()
        }

  defstruct items: [],
            separator: " › ",
            on_click: nil,
            active: true,
            style: %{},
            classes: [],
            app_module: nil,
            focused: false,
            focused_index: 0

  @doc """
  Builds the breadcrumb state from `props`, normalising `:items` so that every entry
  is a `{label, id}` tuple.

  `:focused_index` always starts at `0`, whatever `props` contains.

      iex> crumbs = Drafter.Widget.Breadcrumb.mount(%{items: [{"Home", :home}, "Details"]})
      iex> crumbs.items
      [{"Home", :home}, {"Details", "Details"}]

      iex> crumbs = Drafter.Widget.Breadcrumb.mount(%{})
      iex> {crumbs.items, crumbs.separator, crumbs.active, crumbs.focused_index}
      {[], " › ", true, 0}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Draws the trail as a single strip padded to `rect.width`.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. When the
  crumbs do not fit, the leftmost ones are dropped and replaced with `"..."`.
  Always returns exactly one strip.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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

  @doc """
  Moves the focus between crumbs and activates the focused one.

  `:left` and `:right` clamp `:focused_index` to `0..length(items) - 1` and return
  `{:ok, state}`. `:enter` and `:" "` return `{:ok, state, actions}` where `actions`
  holds an `{:app_callback, name, data}` tuple when `:on_click` produced one, and is
  `[]` otherwise. Any other key returns `{:bubble, state}` unchanged.

      iex> crumbs = Drafter.Widget.Breadcrumb.mount(%{items: ["a", "b", "c"]})
      iex> {:ok, moved} = Drafter.Widget.Breadcrumb.handle_key(:right, crumbs)
      iex> moved.focused_index
      1

      iex> crumbs = Drafter.Widget.Breadcrumb.mount(%{items: ["a"]})
      iex> {:ok, same} = Drafter.Widget.Breadcrumb.handle_key(:left, crumbs)
      iex> same.focused_index
      0

      iex> crumbs = Drafter.Widget.Breadcrumb.mount(%{items: ["a"]})
      iex> Drafter.Widget.Breadcrumb.handle_key(:escape, crumbs) |> elem(0)
      :bubble
  """
  @spec handle_key(Drafter.Widget.key(), t()) ::
          {:ok, t()} | {:ok, t(), [tuple()]} | {:bubble, t()}
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

  @doc """
  Selects the crumb whose label spans column `x`, counted from the left edge of the
  widget.

  Returns `{:ok, state, actions}` for a hit and `{:ok, state}` when `x` falls on a
  separator or past the last crumb, so the event is consumed either way. The column
  map is computed from the untruncated item list.
  """
  @spec handle_mouse_up(integer(), integer(), t()) :: {:ok, t()} | {:ok, t(), [tuple()]}
  @impl Drafter.Widget
  def handle_mouse_up(x, _y, state) do
    case item_index_at(state, x) do
      nil -> {:ok, state}
      index -> trigger_selection(state, index)
    end
  end

  @doc """
  Folds fresh props into `state`.

  Re-reads `:items`, `:separator`, `:on_click`, `:active`, `:style`, `:classes`,
  `:app_module` and `:focused_index`; `:focused` is left alone. `:focused_index` is
  clamped to the new item count.

      iex> crumbs = Drafter.Widget.Breadcrumb.mount(%{items: ["a", "b", "c"]})
      iex> {:ok, crumbs} = Drafter.Widget.Breadcrumb.handle_key(:right, crumbs)
      iex> Drafter.Widget.Breadcrumb.update(%{items: ["a"]}, crumbs).focused_index
      0
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc "Always `1`: the trail occupies a single row whatever the item count."
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Breadcrumb.component_tag()
      :breadcrumb
  """
  @spec component_tag() :: :breadcrumb
  def component_tag, do: :breadcrumb

  @doc """
  Turns the `{:breadcrumb, items, opts}` element into a props map for `mount/1`.

  `items` is the positional argument. `:class` is normalised into `:classes`,
  `:on_click` is wrapped by `Drafter.Widget.Callback.wrap_1/1`, and
  `:__app_module__` becomes `:app_module`.

      iex> props = Drafter.Widget.Breadcrumb.from_component_opts(["Home"], separator: " / ")
      iex> {props.items, props.separator, props.on_click, props.classes, props.active}
      {["Home"], " / ", nil, [], true}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(items, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))
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

  @doc """
  Returns `mount_props` unchanged, so a re-render passes every option through to
  `update/2`.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
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
