defmodule Drafter.Widget.Link do
  @moduledoc """
  An inline hyperlink widget that opens a URL in the system browser when activated.

  Renders as underlined text. When focused or hovered the text is wrapped in square
  brackets (`[label]`) for visibility. Activating via Enter or mouse click invokes the
  platform's default browser opener (`open` on macOS, `xdg-open` on Linux,
  `cmd /c start` on Windows).

  ## Options

    * `:text` - display text; when omitted the `:url` is used as the label
    * `:url` - URL string to open (required for the link to function)
    * `:tooltip` - reserved for future tooltip display
    * `:style` - map of style overrides
    * `:classes` - list of theme class atoms

  ## Usage

      link("Elixir website", url: "https://elixir-lang.org")
  """

  use Drafter.Widget,
    traits: [:focusable],
    handles: [:keyboard, :click]

  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Style.Computed

  defstruct [
    :text,
    :url,
    :style,
    :classes,
    :app_module,
    :focused,
    :hovered,
    :tooltip
  ]

  @impl Drafter.Widget
  def mount(props) do
    %__MODULE__{
      text: Map.get(props, :text),
      url: Map.get(props, :url),
      style: Map.get(props, :style, %{}),
      classes: Map.get(props, :classes, []),
      app_module: Map.get(props, :app_module),
      focused: false,
      hovered: false,
      tooltip: Map.get(props, :tooltip)
    }
  end

  @impl Drafter.Widget
  def render(state, _rect) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)
    computed = compute_link_style(state)

    link_style = %{
      fg: computed[:color] || {100, 150, 255},
      bg: computed[:background] || {30, 30, 30},
      underline: computed[:underline] != false,
      bold: computed[:bold] || false
    }

    display_text = state.text || state.url
    link_text = if state.focused or state.hovered, do: "[#{display_text}]", else: display_text

    [Strip.new([Segment.new(link_text, link_style)])]
  end

  defp compute_link_style(state) do
    classes = state.classes
    classes = if state.hovered, do: classes ++ [:hover], else: classes
    classes = if state.focused, do: classes ++ [:focus], else: classes
    computed_opts = [classes: classes, style: state.style]
    computed_opts = if state.app_module, do: Keyword.put(computed_opts, :app_module, state.app_module), else: computed_opts
    Computed.for_widget(:link, state, computed_opts)
  end

  @impl Drafter.Widget
  def handle_event(event, state) do
    state = if is_struct(state, __MODULE__), do: state, else: mount(state)

    case event do
      {:key, :enter} ->
        open_link(state)
        {:ok, state}

      {:mouse, %{type: :mouse_up}} ->
        open_link(state)
        {:ok, state}

      {:focus} ->
        {:ok, %{state | focused: true, hovered: true}}

      {:blur} ->
        {:ok, %{state | focused: false, hovered: false}}

      :hover ->
        {:ok, %{state | hovered: true}}

      :unhover ->
        {:ok, %{state | hovered: false}}

      _ ->
        {:noreply, state}
    end
  end

  @impl Drafter.Widget
  def update(props, state) do
    %{
      state
      | text: Map.get(props, :text, state.text),
        url: Map.get(props, :url, state.url),
        style: Map.get(props, :style, state.style),
        classes: Map.get(props, :classes, state.classes),
        app_module: Map.get(props, :app_module, state.app_module),
        tooltip: Map.get(props, :tooltip, state.tooltip)
    }
  end

  def preferred_height(_args, _opts), do: 1

  def component_tag, do: :link

  def from_component_opts(text, opts) do
    raw_classes = Keyword.get(opts, :class, [])
    raw_classes = if is_list(raw_classes), do: raw_classes, else: [raw_classes]
    classes = Enum.map(raw_classes, fn
      c when is_binary(c) -> String.to_atom(c)
      c when is_atom(c) -> c
    end)
    %{
      text: text || Keyword.get(opts, :text),
      url: Keyword.get(opts, :url),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      tooltip: Keyword.get(opts, :tooltip),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      text: mount_props.text,
      url: mount_props.url,
      app_module: mount_props.app_module
    }
  end

  defp open_link(%{url: url}) when is_binary(url) do

    command = case :os.type() do
      {:unix, :darwin} -> ["open", url]
      {:unix, _} -> ["xdg-open", url]
      {:win32, _} -> ["cmd", "/c", "start", "", url]
    end

    {output, exit_code} = System.cmd(List.first(command), Enum.drop(command, 1), stderr_to_stdout: true)

    _output = output

    if exit_code != 0 do
    end

    :ok
  end

  defp open_link(_state) do
    :ok
  end
end
