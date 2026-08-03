defmodule Drafter.Widget.Link do
  @moduledoc """
  An inline hyperlink widget that opens a URL in the system browser when activated.

  Renders as underlined text. When focused or hovered the text is wrapped in square
  brackets (`[label]`) for visibility. Activating via Enter or mouse click invokes the
  platform's default browser opener (`open` on macOS, `xdg-open` on Linux,
  `cmd /c start` on Windows).

  ## Component tag

  Tag `:link`, built by `Drafter.App` as `{:link, text, opts}`:

      link(text, opts)
      link(text, url)

  The positional argument becomes `:text`, falling back to `opts[:text]` when
  `nil`. Passing a binary second argument is shorthand for `[url: binary]`.

  ## Options

    * `:text` - `t:String.t/0` display text. Default `nil`, in which case the `:url`
      is used as the label. Supplied positionally through the `link/2` element,
      falling back to `opts[:text]` when the positional value is `nil`
    * `:url` - `t:String.t/0` to open. Default `nil`; without it, activating the
      link does nothing
    * `:tooltip` - stored on the widget state; never rendered. Default `nil`
    * `:style` - `t:map/0` of style overrides. Default `%{}`
    * `:class` - theme class atom or list of them, reaching `mount/1` as
      `:classes`. Default `[]`
    * `:app_module` - module supplying a per-app theme, passed by the renderer as
      `:__app_module__`. Default `nil`

  `mount/1` always starts `:focused` and `:hovered` at `false` and ignores props of
  those names. `update/2` re-reads every option, but through the component tree only
  `:text`, `:url` and `:app_module` are re-applied on a re-render, making `:style`,
  `:classes` and `:tooltip` effectively mount-only there.

  ## Widget value

  `Drafter.get_widget_value/1` returns the link's `:text`, which is `nil` when the
  label falls back to the URL.

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

  @type t :: %__MODULE__{
          text: String.t() | nil,
          url: String.t() | nil,
          style: map(),
          classes: [atom()],
          app_module: module() | nil,
          focused: boolean(),
          hovered: boolean(),
          tooltip: String.t() | nil
        }

  @doc """
  Builds the link state from `props`.

      iex> l = Drafter.Widget.Link.mount(%{text: "Elixir", url: "https://elixir-lang.org"})
      iex> {l.text, l.url, l.focused, l.hovered}
      {"Elixir", "https://elixir-lang.org", false, false}

      iex> l = Drafter.Widget.Link.mount(%{})
      iex> {l.text, l.url, l.style, l.classes, l.tooltip}
      {nil, nil, %{}, [], nil}
  """
  @spec mount(Drafter.Widget.props()) :: t()
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

  @doc """
  Draws the link as a single underlined strip.

  Accepts either a `t:t/0` or a raw props map, which is mounted first. The label is
  `:text`, falling back to `:url`, and is wrapped in square brackets while focused
  or hovered. `rect` is not consulted, so a label wider than the rect is neither
  cropped nor padded. While hovered a `:hover` class and while focused a `:focus`
  class are added to the computed style.
  """
  @spec render(t() | Drafter.Widget.props(), Drafter.Widget.rect()) :: [Strip.t()]
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

    computed_opts =
      if state.app_module,
        do: Keyword.put(computed_opts, :app_module, state.app_module),
        else: computed_opts

    Computed.for_widget(:link, state, computed_opts)
  end

  @doc """
  Handles events directly instead of going through `Drafter.Widget.EventRouter`.

  `{:key, :enter}` and a mouse release run the platform browser opener for `:url`
  and return `{:ok, state}` unchanged; with no `:url` nothing is run. `{:focus}`
  sets both `:focused` and `:hovered`, `{:blur}` clears both, and
  `:hover`/`:unhover` move `:hovered` alone. Everything else, including `Space`,
  returns `{:noreply, state}`.

      iex> l = Drafter.Widget.Link.mount(%{text: "Elixir", url: "https://elixir-lang.org"})
      iex> {:ok, focused} = Drafter.Widget.Link.handle_event({:focus}, l)
      iex> {focused.focused, focused.hovered}
      {true, true}

      iex> l = Drafter.Widget.Link.mount(%{text: "Elixir"})
      iex> Drafter.Widget.Link.handle_event({:key, :" "}, l) |> elem(0)
      :noreply
  """
  @spec handle_event(Drafter.Event.t() | atom(), t() | Drafter.Widget.props()) ::
          {:ok, t()} | {:noreply, t()}
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

  @doc """
  Folds fresh props into `state`, re-reading `:text`, `:url`, `:style`, `:classes`,
  `:app_module` and `:tooltip`. `:focused` and `:hovered` are left alone.

      iex> l = Drafter.Widget.Link.mount(%{text: "Old", url: "https://a.example"})
      iex> Drafter.Widget.Link.update(%{text: "New"}, l).url
      "https://a.example"
  """
  @spec update(Drafter.Widget.props(), t()) :: t()
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

  @doc "Always `1`: the link occupies a single row."
  @spec preferred_height(term(), keyword()) :: pos_integer()
  def preferred_height(_args, _opts), do: 1

  @doc """
  The registry tag for this widget.

      iex> Drafter.Widget.Link.component_tag()
      :link
  """
  @spec component_tag() :: :link
  def component_tag, do: :link

  @doc """
  Turns the `{:link, text, opts}` element into a props map for `mount/1`.

  A `nil` positional `text` falls back to `opts[:text]`. `:class` is normalised into
  `:classes` and `:__app_module__` becomes `:app_module`.

      iex> Drafter.Widget.Link.from_component_opts("Elixir", url: "https://elixir-lang.org")
      %{text: "Elixir", url: "https://elixir-lang.org", style: %{}, classes: [], tooltip: nil, app_module: nil}
  """
  @spec from_component_opts(term(), keyword()) :: Drafter.Widget.props()
  def from_component_opts(text, opts) do
    classes = Drafter.Style.normalize_classes(Keyword.get(opts, :class, []))

    %{
      text: text || Keyword.get(opts, :text),
      url: Keyword.get(opts, :url),
      style: Keyword.get(opts, :style, %{}),
      classes: classes,
      tooltip: Keyword.get(opts, :tooltip),
      app_module: Keyword.get(opts, :__app_module__)
    }
  end

  @doc """
  Narrows the props a re-render feeds to `update/2` to `:text`, `:url` and
  `:app_module`, so `:style`, `:classes` and `:tooltip` stay as mounted.
  """
  @spec update_props_from_mount(Drafter.Widget.props(), t(), keyword()) :: Drafter.Widget.props()
  def update_props_from_mount(mount_props, _existing_state, _opts) do
    %{
      text: mount_props.text,
      url: mount_props.url,
      app_module: mount_props.app_module
    }
  end

  defp open_link(%{url: url}) when is_binary(url) do
    command =
      case :os.type() do
        {:unix, :darwin} -> ["open", url]
        {:unix, _} -> ["xdg-open", url]
        {:win32, _} -> ["cmd", "/c", "start", "", url]
      end

    {output, exit_code} =
      System.cmd(List.first(command), Enum.drop(command, 1), stderr_to_stdout: true)

    _output = output

    if exit_code != 0 do
    end

    :ok
  end

  defp open_link(_state) do
    :ok
  end
end
