defmodule Drafter.Widget.Label do
  @moduledoc """
  Renders a single line or multi-line string of styled text.

  Supports semantic variants that apply theme colors automatically, and accepts
  an explicit style map for full control over foreground and background colors.

  ## Options

    * `:style` - map of style properties, e.g. `%{fg: {255, 100, 0}, bold: true}`
    * `:align` - text alignment: `:left` (default), `:center`, `:right`
    * `:variant` - semantic color: `:default` (default), `:primary`, `:success`, `:warning`, `:error`, `:muted`
    * `:classes` - list of CSS-like theme class atoms

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

  @type t :: %__MODULE__{
          text: String.t(),
          style: map(),
          align: :left | :center | :right,
          variant: :default | :primary | :success | :warning | :error | :muted
        }

  @doc "Create a new label with text"
  @spec new(String.t(), keyword()) :: t()
  def new(text, opts \\ []) do
    %__MODULE__{
      text: text,
      style: Keyword.get(opts, :style, %{}),
      align: Keyword.get(opts, :align, :left),
      variant: Keyword.get(opts, :variant, :default)
    }
  end

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

  @impl Drafter.Widget
  def render(state, rect) do
    variant_classes = if state.variant != :default, do: [state.variant], else: []
    classes = variant_classes ++ (state.classes || [])
    computed_opts = [classes: classes, style: state.style]
    computed_opts = if state.app_module, do: Keyword.put(computed_opts, :app_module, state.app_module), else: computed_opts
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

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :label

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
