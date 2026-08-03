defmodule Drafter.Style.StylesheetLoader do
  @moduledoc """
  Loads and caches the stylesheet an app renders against.

  A singleton `GenServer` registered under this module's name. It assembles an
  app's stylesheet from the built-in widget defaults, the app's CSS file and the
  app's inline rules, and holds the result so that later renders do not re-read the
  file.

  ## How an app declares its styles

  An app module may export either or both of:

    * `__css_path__/0` — path to a CSS file, parsed by `Drafter.Style.CSSParser`.
      Returning `nil` contributes nothing.
    * `__inline_styles__/0` — map of `%{selector => style}` added rule by rule.

  A file is layered over the defaults and inline rules over the file, so an inline
  rule wins a specificity tie against a rule from the CSS file. An app exporting
  only `__inline_styles__/0` skips the file step entirely.

  ## Caching

  Results are cached per app module and per file path, and only `clear_cache/0`
  discards them. Editing a CSS file after it has been loaded has no effect until the
  cache is cleared.

  `load_inline/1` neither reads the cache nor writes to it.
  """

  use GenServer
  alias Drafter.Style.{CSSParser, Stylesheet, WidgetStyles}

  @typedoc "Cache key: an app module's assembled sheet, or one parsed CSS file."
  @type stylesheet_key :: {:app, module()} | {:file, String.t()}

  defstruct cache: %{}

  @doc """
  Start the loader, registered under this module's name.

  `opts` are passed to `init/1`, which ignores them. Starting a second one fails
  with `{:error, {:already_started, pid}}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  The stylesheet for `app_module`, as `{:ok, stylesheet}`.

  Built from `Drafter.Style.WidgetStyles.default_stylesheet/0`, then the CSS file
  named by the app's `__css_path__/0` if it exports one, then the rules of its
  `__inline_styles__/0` if it exports one, each layer added after the last. An app
  exporting neither gets the default stylesheet alone.

  A CSS file that cannot be read or parsed contributes nothing. The result is
  cached per app module until `clear_cache/0`, so later edits to the CSS file are
  not picked up.

  Never returns an error: an app that cannot be loaded from still yields the
  default stylesheet.
  """
  @spec load_stylesheet(module()) :: {:ok, Stylesheet.t()}
  def load_stylesheet(app_module) when is_atom(app_module) do
    GenServer.call(__MODULE__, {:load_stylesheet, app_module})
  end

  @doc """
  Parse the CSS file at `file_path` on its own, with no default rules merged in.

  Returns `{:ok, stylesheet}`, or `{:error, reason}` when the file cannot be read
  or parsed. Successful results are cached per path until `clear_cache/0`; a
  failure is not cached and is retried on the next call.
  """
  @spec load_from_file(Path.t()) :: {:ok, Stylesheet.t()} | {:error, String.t()}
  def load_from_file(file_path) do
    GenServer.call(__MODULE__, {:load_from_file, file_path})
  end

  @doc """
  The default stylesheet with `styles` added on top.

  `styles` maps a selector — a string such as `"button:focus"`, or a widget-type
  atom — to a map of style properties. Rules are added in map iteration order and
  the result is not cached. Runs in the calling process, so the loader need not be
  running.

  Returns the stylesheet itself, not an `{:ok, _}` tuple.
  """
  @spec load_inline(map()) :: Stylesheet.t()
  def load_inline(styles) when is_map(styles) do
    base = WidgetStyles.default_stylesheet()

    Enum.reduce(styles, base, fn {selector, properties}, acc ->
      Stylesheet.add_rule(acc, selector, properties)
    end)
  end

  @doc """
  Discard every cached stylesheet, so the next load re-reads and re-parses.

  Clears both the per-app and the per-file entries. Does not clear the built-in
  defaults, which `Drafter.Style.WidgetStyles.clear_cache/0` handles.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{cache: %{}}
    {:ok, state}
  end

  @impl true
  def handle_call({:load_stylesheet, app_module}, _from, state) do
    case Map.fetch(state.cache, {:app, app_module}) do
      {:ok, stylesheet} ->
        {:reply, {:ok, stylesheet}, state}

      :error ->
        result = do_load_stylesheet(app_module, state.cache)
        cache = Map.put(state.cache, {:app, app_module}, result.stylesheet)
        {:reply, {:ok, result.stylesheet}, %{state | cache: cache}}
    end
  end

  @impl true
  def handle_call({:load_from_file, file_path}, _from, state) do
    case Map.fetch(state.cache, {:file, file_path}) do
      {:ok, stylesheet} ->
        {:reply, {:ok, stylesheet}, state}

      :error ->
        case CSSParser.parse_file(file_path) do
          {:ok, stylesheet} ->
            new_state = put_in(state.cache[{:file, file_path}], stylesheet)
            {:reply, {:ok, stylesheet}, new_state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call(:clear_cache, _from, state) do
    {:reply, :ok, %{state | cache: %{}}}
  end

  defp do_load_stylesheet(app_module, cache) do
    base = WidgetStyles.default_stylesheet()

    stylesheet =
      cond do
        function_exported?(app_module, :__css_path__, 0) ->
          file_stylesheet = load_file_stylesheet(app_module.__css_path__(), cache)
          inline_styles = get_inline_styles(app_module)

          base
          |> Stylesheet.merge(file_stylesheet)
          |> then(&merge_inline(&1, inline_styles))

        function_exported?(app_module, :__inline_styles__, 0) ->
          inline_styles = app_module.__inline_styles__()
          merge_inline(base, inline_styles)

        true ->
          base
      end

    %{stylesheet: stylesheet}
  end

  defp load_file_stylesheet(nil, _cache), do: Stylesheet.new()

  defp load_file_stylesheet(css_path, cache) do
    case Map.fetch(cache, {:file, css_path}) do
      {:ok, cached} -> cached
      :error -> parse_css_file(css_path)
    end
  end

  defp parse_css_file(css_path) do
    case CSSParser.parse_file(css_path) do
      {:ok, parsed} -> parsed
      {:error, _} -> Stylesheet.new()
    end
  end

  defp get_inline_styles(app_module) do
    if function_exported?(app_module, :__inline_styles__, 0) do
      app_module.__inline_styles__()
    else
      %{}
    end
  end

  defp merge_inline(base, inline) when is_map(inline) do
    Enum.reduce(inline, base, fn {selector, properties}, acc ->
      Stylesheet.add_rule(acc, selector, properties)
    end)
  end
end
