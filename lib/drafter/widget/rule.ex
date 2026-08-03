defmodule Drafter.Widget.Rule do
  @moduledoc """
  Renders a horizontal or vertical divider line, optionally with an embedded title.

  ## Component tag

  Tag `:rule`, built by `Drafter.App` as `{:rule, opts}`:

      rule(opts)

  There is no positional argument; every prop comes from `opts`.

  ## Options

    * `:orientation` - `:horizontal | :vertical`. Default `:horizontal`. Any other
      value raises a `CaseClauseError` from `render/2`.
    * `:title` - `t:String.t/0` embedded in a horizontal rule, or `nil`. Default
      `nil`. Ignored when the orientation is `:vertical`. A title that is as wide
      as the rect, once padded with a space on each side, is truncated and no line
      characters are drawn.
    * `:title_align` - `:left | :center | :right`. Default `:center`. Only read
      when `:title` is set.
    * `:line_style` - `:solid | :double | :dashed | :thick`. Default `:solid`.
      Selects `─ ═ ╌ ━` horizontally and `│ ║ ╎ ┃` vertically. Any other value
      raises a `KeyError` from `render/2`.
    * `:style` - `t:map/0` of style overrides merged over the computed theme style.
      Default `%{}`.
    * `:height` - `t:pos_integer/0` read only by `preferred_height/2`, never by
      `mount/1`. Default `1`.

  Every option except `:height` is live-updatable: `update/2` folds each recognised
  key into the state and `update_props_from_mount/3` passes the full mount props
  through.

  ## Usage

      rule()
      rule(title: "Section", line_style: :double)
      rule(orientation: :vertical)
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @horizontal_chars %{solid: "─", double: "═", dashed: "╌", thick: "━"}
  @vertical_chars %{solid: "│", double: "║", dashed: "╎", thick: "┃"}

  defstruct orientation: :horizontal,
            title: nil,
            title_align: :center,
            style: %{},
            line_style: :solid,
            app_module: nil

  @type t :: %__MODULE__{
          orientation: :horizontal | :vertical,
          title: String.t() | nil,
          title_align: :left | :center | :right,
          style: map(),
          line_style: :solid | :double | :dashed | :thick,
          app_module: module() | nil
        }

  @doc """
  Builds the widget state from `props`.

  Reads `:orientation` (default `:horizontal`), `:title` (default `nil`),
  `:title_align` (default `:center`), `:style` (default `%{}`), `:line_style`
  (default `:solid`) and `:app_module` (default `nil`).

      iex> Drafter.Widget.Rule.mount(%{})
      %Drafter.Widget.Rule{orientation: :horizontal, title: nil, title_align: :center, style: %{}, line_style: :solid, app_module: nil}

      iex> Drafter.Widget.Rule.mount(%{title: "Section", line_style: :double}).line_style
      :double
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      orientation: Map.get(props, :orientation, :horizontal),
      title: Map.get(props, :title),
      title_align: Map.get(props, :title_align, :center),
      style: Map.get(props, :style, %{}),
      line_style: Map.get(props, :line_style, :solid),
      app_module: Map.get(props, :app_module)
    }
  end

  @doc """
  Folds `props` into `state`, one key at a time.

  Recognises `:orientation`, `:title`, `:title_align`, `:style`, `:line_style` and
  `:app_module`; any other key is ignored and leaves the state untouched. `props`
  may be a map or a keyword list.

      iex> state = Drafter.Widget.Rule.mount(%{})
      iex> Drafter.Widget.Rule.update(%{title: "New", unknown: 1}, state).title
      "New"
  """
  @spec update(Drafter.Widget.props() | keyword(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    Enum.reduce(props, state, fn {key, value}, acc ->
      case key do
        :orientation -> %{acc | orientation: value}
        :title -> %{acc | title: value}
        :title_align -> %{acc | title_align: value}
        :style -> %{acc | style: value}
        :line_style -> %{acc | line_style: value}
        :app_module -> %{acc | app_module: value}
        _ -> acc
      end
    end)
  end

  @doc """
  Draws the rule into `rect`.

  A horizontal rule returns `rect.height` strips with the line on row
  `div(rect.height, 2)` and blanks elsewhere. A vertical rule returns
  `rect.height` strips each holding the line character followed by
  `rect.width - 1` spaces, or `[]` when `rect.width` is not positive.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    computed_opts = [style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:rule, state, computed_opts)
    segment_style = Computed.to_segment_style(computed)

    case state.orientation do
      :horizontal -> render_horizontal(state, rect, segment_style)
      :vertical -> render_vertical(state, rect, segment_style)
    end
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`. The rule is not focusable.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  @impl Drafter.Widget
  def handle_event(_event, state) do
    {:noreply, state}
  end

  @doc """
  The number of rows the element asks for: `opts[:height]`, default `1`.

      iex> Drafter.Widget.Rule.preferred_height(nil, [])
      1

      iex> Drafter.Widget.Rule.preferred_height(nil, height: 3)
      3
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, opts), do: Keyword.get(opts, :height, 1)

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Rule.component_tag()
      :rule
  """
  @spec component_tag() :: :rule
  def component_tag, do: :rule

  @doc """
  Builds the props map for a `{:rule, opts}` element.

  The positional argument is ignored. `:__app_module__` becomes `:app_module`;
  every other option keeps its name and the default stated in the module doc.

      iex> Drafter.Widget.Rule.from_component_opts(nil, [])
      %{orientation: :horizontal, title: nil, title_align: :center, style: %{}, line_style: :solid, app_module: nil}

      iex> Drafter.Widget.Rule.from_component_opts(nil, title: "Section", title_align: :left).title_align
      :left
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(_args, opts) do
    %{
      orientation: Keyword.get(opts, :orientation, :horizontal),
      title: Keyword.get(opts, :title),
      title_align: Keyword.get(opts, :title_align, :center),
      style: Keyword.get(opts, :style, %{}),
      line_style: Keyword.get(opts, :line_style, :solid),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  @doc """
  Passes the mount props through unchanged, so every option is live-updatable
  through the component tree.

      iex> props = Drafter.Widget.Rule.from_component_opts(nil, title: "Section")
      iex> Drafter.Widget.Rule.update_props_from_mount(props, %{}, []) == props
      true
  """
  @spec update_props_from_mount(Drafter.Widget.props(), term(), keyword()) ::
          Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts), do: mount_props

  defp render_horizontal(state, rect, segment_style) do
    line_char = Map.fetch!(@horizontal_chars, state.line_style)
    mid_row = div(rect.height, 2)
    empty_segment = Segment.new(String.duplicate(" ", rect.width), segment_style)

    Enum.map(0..(rect.height - 1)//1, fn row ->
      if row == mid_row do
        strip_segment = build_horizontal_line(state, rect.width, line_char, segment_style)
        Strip.new([strip_segment])
      else
        Strip.new([empty_segment])
      end
    end)
  end

  defp build_horizontal_line(%{title: nil}, width, line_char, segment_style) do
    Segment.new(String.duplicate(line_char, width), segment_style)
  end

  defp build_horizontal_line(%{title: title, title_align: align}, width, line_char, segment_style) do
    embedded = " " <> title <> " "
    embedded_len = String.length(embedded)

    if embedded_len >= width do
      Segment.new(String.slice(embedded, 0, width), segment_style)
    else
      remaining = width - embedded_len

      {left_count, right_count} =
        case align do
          :left ->
            {0, remaining}

          :right ->
            {remaining, 0}

          :center ->
            left = div(remaining, 2)
            {left, remaining - left}
        end

      text =
        String.duplicate(line_char, left_count) <>
          embedded <>
          String.duplicate(line_char, right_count)

      Segment.new(text, segment_style)
    end
  end

  defp render_vertical(_state, %{width: width}, _segment_style) when width <= 0, do: []

  defp render_vertical(state, rect, segment_style) do
    line_char = Map.fetch!(@vertical_chars, state.line_style)
    padding = String.duplicate(" ", rect.width - 1)

    Enum.map(0..(rect.height - 1)//1, fn _row ->
      seg = Segment.new(line_char <> padding, segment_style)
      Strip.new([seg])
    end)
  end
end
