defmodule Drafter.Widget.Label do
  @moduledoc """
  Renders a single line or multi-line string of styled text.

  Supports semantic variants that apply theme colors automatically, and accepts
  an explicit style map for full control over foreground and background colors.

  ## Component tag

  Tag `:label`, built by `Drafter.App` as `{:label, text, opts}`:

      label(text, opts)

  The positional argument becomes `:text`. All other props come from `opts`.

  ## Options

    * `:text` - `t:String.t/0` to render. Default `""`. Supplied positionally
      through the `label/2` element. A `"\\n"` splits it into one strip per line
    * `:style` - `t:map/0` of style properties, e.g. `%{fg: {255, 100, 0},
      bold: true}`. Default `%{}`
    * `:align` - text alignment: `:left` (default), `:center`, `:right`
    * `:variant` - semantic colour: `:default` (default), `:primary`, `:success`,
      `:warning`, `:error`, `:muted`. Anything other than `:default` is also added
      as a theme class while rendering
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:app_module` - module supplying a per-app theme, passed by the renderer as
      `:__app_module__`. Default `nil`

  `update/2` accepts `:text`, `:style`, `:align`, `:variant`, `:classes` and
  `:app_module`, and silently drops any other key. All of them are live-updatable
  through the component tree.

  ## Widget value

  `Drafter.get_widget_value/1` returns the label's `:text` as a `t:String.t/0`,
  because the value extractor reads the `:text` field.

  ## Usage

      label("Hello world", style: %{fg: {100, 200, 255}, bold: true})
      label("Warning!", variant: :warning)
      label("Centered", align: :center)
  """

  use Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct text: "",
            style: %{},
            align: :left,
            variant: :default,
            classes: [],
            app_module: nil

  @type align :: :left | :center | :right

  @type variant :: :default | :primary | :success | :warning | :error | :muted

  @type t :: %__MODULE__{
          text: String.t(),
          style: map(),
          align: align(),
          variant: variant(),
          classes: [atom()],
          app_module: module() | nil
        }

  @doc """
  Builds a label struct directly from `text` and `opts`.

  Reads `:style` (default `%{}`), `:align` (default `:left`) and `:variant`
  (default `:default`). `:classes` and `:app_module` are not read here and stay at
  their struct defaults; use `mount/1` to set them.

      iex> l = Drafter.Widget.Label.new("Hello", align: :center)
      iex> {l.text, l.align, l.variant, l.classes}
      {"Hello", :center, :default, []}
  """
  @spec new(String.t(), keyword()) :: t()
  def new(text, opts \\ []) do
    %__MODULE__{
      text: text,
      style: Keyword.get(opts, :style, %{}),
      align: Keyword.get(opts, :align, :left),
      variant: Keyword.get(opts, :variant, :default)
    }
  end

  @doc """
  Builds the label state from `props`.

      iex> l = Drafter.Widget.Label.mount(%{text: "Hi", variant: :warning})
      iex> {l.text, l.variant, l.align}
      {"Hi", :warning, :left}

      iex> l = Drafter.Widget.Label.mount(%{})
      iex> {l.text, l.style, l.align, l.variant, l.classes, l.app_module}
      {"", %{}, :left, :default, [], nil}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      text: Map.get(props, :text, ""),
      style: Map.get(props, :style, %{}),
      align: Map.get(props, :align, :left),
      variant: Map.get(props, :variant, :default),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module)
    }
  end

  @doc """
  Draws the text into `rect`, one strip per newline-separated line.

  Empty text yields a single blank strip. Each line is padded to `rect.width`
  according to `:align`, or cropped to it when it is longer. `rect.height` is not
  consulted, so a label with more lines than rows overflows.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  @impl Drafter.Widget
  def render(state, rect) do
    variant_classes = if state.variant != :default, do: [state.variant], else: []
    classes = variant_classes ++ (state.classes || [])
    computed_opts = [classes: classes, style: state.style]

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    computed = Computed.for_widget(:label, state, computed_opts)
    segment_style = Computed.to_segment_style(computed)

    bg_style = %{fg: segment_style[:fg], bg: segment_style[:bg]}

    if String.length(state.text) == 0 do
      [Strip.new([Segment.new(String.duplicate(" ", rect.width), bg_style)])]
    else
      state.text
      |> String.split("\n")
      |> Enum.map(&render_label_line(&1, segment_style, bg_style, state.align, rect.width))
    end
  end

  @doc """
  Folds fresh props into `state`.

  Only `:text`, `:style`, `:align`, `:variant`, `:classes` and `:app_module` are
  applied; any other key in `props` is dropped without error.

      iex> l = Drafter.Widget.Label.mount(%{text: "Hi"})
      iex> updated = Drafter.Widget.Label.update(%{text: "Bye", nonsense: 1}, l)
      iex> {updated.text, updated.align}
      {"Bye", :left}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  @impl Drafter.Widget
  def update(props, state) do
    Enum.reduce(props, state, fn {key, value}, acc ->
      case key do
        :text -> %{acc | text: value}
        :style -> %{acc | style: value}
        :align -> %{acc | align: value}
        :variant -> %{acc | variant: value}
        :classes -> %{acc | classes: value}
        :app_module -> %{acc | app_module: value}
        _ -> acc
      end
    end)
  end

  @doc """
  Always `1`, whatever the text contains — a multi-line label still reserves a
  single row.
  """
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Label.component_tag()
      :label
  """
  @spec component_tag() :: :label
  def component_tag, do: :label

  @doc """
  Turns the `{:label, text, opts}` element into a props map for `mount/1`.

  `text` is the positional argument. `:class` is normalised into `:classes` and
  `:__app_module__` becomes `:app_module`.

      iex> Drafter.Widget.Label.from_component_opts("Hi", align: :right)
      %{text: "Hi", style: %{}, align: :right, variant: :default, classes: [], app_module: nil}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(text, opts) do
    classes = Drafter.Util.normalize_classes(Keyword.get(opts, :class, []))

    %{
      text: text,
      style: Keyword.get(opts, :style, %{}),
      align: Keyword.get(opts, :align, :left),
      variant: Keyword.get(opts, :variant, :default),
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

  defp render_label_line("", _segment_style, bg_style, _align, width) do
    Strip.new([Segment.new(String.duplicate(" ", width), bg_style)])
  end

  defp render_label_line(line, segment_style, bg_style, align, width) do
    strip = Strip.new([Segment.new(line, segment_style)])
    align_strip(strip, align, width, bg_style)
  end

  defp align_strip(strip, :left, width, bg_style) do
    strip_width = Strip.width(strip)

    if strip_width >= width do
      Strip.crop(strip, width)
    else
      padding_width = width - strip_width
      padding = Segment.new(String.duplicate(" ", padding_width), bg_style)
      Strip.new(strip.segments ++ [padding])
    end
  end

  defp align_strip(strip, :center, width, bg_style) do
    strip_width = Strip.width(strip)

    if strip_width >= width do
      Strip.crop(strip, width)
    else
      total_padding = width - strip_width
      left_padding = div(total_padding, 2)
      right_padding = total_padding - left_padding
      left_seg = Segment.new(String.duplicate(" ", left_padding), bg_style)
      right_seg = Segment.new(String.duplicate(" ", right_padding), bg_style)
      Strip.new([left_seg] ++ strip.segments ++ [right_seg])
    end
  end

  defp align_strip(strip, :right, width, bg_style) do
    strip_width = Strip.width(strip)

    if strip_width >= width do
      Strip.crop(strip, width)
    else
      padding_width = width - strip_width
      padding = Segment.new(String.duplicate(" ", padding_width), bg_style)
      Strip.new([padding] ++ strip.segments)
    end
  end
end
