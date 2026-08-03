defmodule Drafter.Widget.Markdown do
  @moduledoc """
  Renders a subset of Markdown to the terminal with themed styling.

  Supported syntax: `#` and `##` headings, `**bold**`, `*italic*`, and
  `` `inline code` ``. Block elements are styled via the theme system using
  the `:h1`, `:h2`, and `:text` theme parts. A configurable horizontal
  padding is applied inside the widget boundaries.

  ## Component tag

  Tag `:markdown`, built by `Drafter.App` as `{:markdown, content, opts}`:

      markdown(content, opts)

  The positional argument becomes `:content`, falling back to `opts[:content]`
  when `nil`.

  ## Options

    * `:content` - `t:String.t/0`, the Markdown to render. Default `""`. Supplied
      positionally through the `markdown/2` element; the positional argument wins
      unless it is `nil`.
    * `:padding` - `t:non_neg_integer/0`, left and right padding in columns.
      Default `1`. A rect narrower than `2 * padding` renders nothing.
    * `:style` - `t:map/0` of base style attributes merged under the computed theme
      styles. Default `%{}`.
    * `:height` - `t:pos_integer/0` read only by `preferred_height/2`, never by
      `mount/1`. Default is the line count of the content, at least `3`.

  Every option is live-updatable: `update/2` merges the props map straight into the
  state. `update_props_from_mount/3` narrows a re-render to `:content` alone, so a
  `:padding` or `:style` change made after mount through the component tree is not
  picked up.

  ## Usage

      markdown(content: "# Title\\n\\nSome **bold** and *italic* text with `code`.")
      markdown(content: readme_text, padding: 2)
  """

  @behaviour Drafter.Widget

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  @type t :: %{
          content: String.t(),
          style: map(),
          padding: non_neg_integer()
        }

  @doc """
  Builds the widget state from `props`.

  Reads `:content` (default `""`), `:style` (default `%{}`) and `:padding`
  (default `1`).

      iex> Drafter.Widget.Markdown.mount(%{})
      %{content: "", padding: 1, style: %{}}

      iex> Drafter.Widget.Markdown.mount(%{content: "# Title", padding: 2})
      %{content: "# Title", padding: 2, style: %{}}
  """
  @spec mount(Drafter.Widget.props()) :: t()
  def mount(props) do
    %{
      content: Map.get(props, :content, ""),
      style: Map.get(props, :style, %{}),
      padding: Map.get(props, :padding, 1)
    }
  end

  @doc """
  Renders the parsed Markdown into `rect`, one `Drafter.Draw.Strip` per source line.

  Headings are styled through the `:h1` and `:h2` theme parts and every other line
  through `:text`. Returns `[]` when `rect.width` leaves no room after padding.
  """
  @spec render(t(), Drafter.Widget.rect()) :: [Strip.t()]
  def render(state, rect) do
    render_markdown(state, rect)
  end

  @doc """
  Merges `props` into `state` and returns the result.

  Any key present in `props` replaces the one in the state, so `:content`,
  `:padding` and `:style` are all live-updatable.

      iex> state = Drafter.Widget.Markdown.mount(%{content: "a"})
      iex> Drafter.Widget.Markdown.update(%{content: "b"}, state)
      %{content: "b", padding: 1, style: %{}}
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
  def update(props, state) do
    Map.merge(state, props)
  end

  @doc """
  Ignores every event and returns `{:noreply, state}`. The widget is not focusable
  and never consumes input.
  """
  @spec handle_event(Drafter.Event.t(), t()) :: {:noreply, t()}
  def handle_event(_event, state) do
    {:noreply, state}
  end

  defp render_markdown(state, rect) do
    padding = state.padding
    content_width = rect.width - padding * 2

    if content_width <= 0 do
      []
    else
      lines = parse_markdown(state.content, content_width)

      Enum.map(lines, fn {segments_spec, base_part} ->
        render_markdown_line(segments_spec, base_part, state, padding)
      end)
    end
  end

  @doc """
  The number of rows the element asks for.

  `args` is the positional content string, or `nil`. Returns `opts[:height]` when
  given, otherwise the line count of `args` with a floor of `3`.

      iex> Drafter.Widget.Markdown.preferred_height("# Title", [])
      3

      iex> Drafter.Widget.Markdown.preferred_height("a\\nb\\nc\\nd", [])
      4

      iex> Drafter.Widget.Markdown.preferred_height(nil, height: 10)
      10
  """
  @spec preferred_height(String.t() | nil, keyword()) :: pos_integer()
  def preferred_height(args, opts) do
    lines = String.split(args || "", "\n") |> length()
    Keyword.get(opts, :height, max(lines, 3))
  end

  @doc """
  The component tag this widget registers under.

      iex> Drafter.Widget.Markdown.component_tag()
      :markdown
  """
  @spec component_tag() :: :markdown
  def component_tag, do: :markdown

  @doc """
  Builds the props map for a `{:markdown, content, opts}` element.

  `content` is the positional argument; when it is `nil`, `opts[:content]` is used
  instead, defaulting to `""`. Also reads `:style` (default `%{}`) and `:padding`
  (default `1`).

      iex> Drafter.Widget.Markdown.from_component_opts("# Title", padding: 0)
      %{content: "# Title", padding: 0, style: %{}}

      iex> Drafter.Widget.Markdown.from_component_opts(nil, content: "fallback")
      %{content: "fallback", padding: 1, style: %{}}
  """
  @spec from_component_opts(String.t() | nil, keyword()) :: t()
  def from_component_opts(content, opts) do
    %{
      content: content || Keyword.get(opts, :content, ""),
      style: Keyword.get(opts, :style, %{}),
      padding: Keyword.get(opts, :padding, 1)
    }
  end

  @doc """
  Narrows a re-render to the props that may change after mount.

  Only `:content` is carried over, so a `:padding` or `:style` change made through
  the component tree after the first mount is not picked up.

      iex> props = Drafter.Widget.Markdown.from_component_opts("# New", padding: 4)
      iex> Drafter.Widget.Markdown.update_props_from_mount(props, %{}, [])
      %{content: "# New"}
  """
  @spec update_props_from_mount(t(), term(), keyword()) :: %{content: String.t()}
  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{content: mount_props.content}
  end

  defp render_markdown_line(text, base_part, state, padding) when is_binary(text) do
    base_computed = Computed.for_part(:markdown, state, base_part)
    base_style = Map.merge(state.style, Computed.to_segment_style(base_computed))
    segments = [Segment.new(text, base_style)]
    wrap_with_padding(segments, padding, base_style)
  end

  defp render_markdown_line(specs, base_part, state, padding) when is_list(specs) do
    base_computed = Computed.for_part(:markdown, state, base_part)
    base_style = Map.merge(state.style, Computed.to_segment_style(base_computed))

    segments =
      Enum.map(specs, fn {text, inline_style} ->
        Segment.new(text, apply_inline_style(base_style, inline_style))
      end)

    wrap_with_padding(segments, padding, base_style)
  end

  defp wrap_with_padding(segments, 0, _style), do: Strip.new(segments)

  defp wrap_with_padding(segments, padding, style) do
    padding_segment = Segment.new(String.duplicate(" ", padding), style)
    Strip.new([padding_segment] ++ segments ++ [padding_segment])
  end

  defp apply_inline_style(base_style, :bold), do: Map.put(base_style, :bold, true)
  defp apply_inline_style(base_style, :italic), do: Map.put(base_style, :italic, true)

  defp apply_inline_style(base_style, :code),
    do: Map.merge(base_style, %{bg: {60, 60, 60}, fg: {200, 200, 100}})

  defp apply_inline_style(base_style, :normal), do: base_style

  defp parse_markdown(content, width) do
    content
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      parse_line(line, width)
    end)
  end

  defp parse_line("## " <> heading, _width) do
    segments = parse_inline_formatting(heading)
    [{segments, :h2}]
  end

  defp parse_line("# " <> heading, _width) do
    segments = parse_inline_formatting(heading)
    [{segments, :h1}]
  end

  defp parse_line("", _width) do
    [{[{"", :normal}], :text}]
  end

  defp parse_line(line, _width) do
    segments = parse_inline_formatting(line)
    [{segments, :text}]
  end

  defp parse_inline_formatting(text) do
    pattern = ~r/(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/

    parts = Regex.split(pattern, text, include_captures: true)

    Enum.flat_map(parts, fn part ->
      cond do
        part == "" ->
          []

        String.starts_with?(part, "**") and String.ends_with?(part, "**") ->
          inner = String.slice(part, 2..-3//1)
          [{inner, :bold}]

        String.starts_with?(part, "*") and String.ends_with?(part, "*") ->
          inner = String.slice(part, 1..-2//1)
          [{inner, :italic}]

        String.starts_with?(part, "`") and String.ends_with?(part, "`") ->
          inner = String.slice(part, 1..-2//1)
          [{inner, :code}]

        true ->
          [{part, :normal}]
      end
    end)
  end
end
