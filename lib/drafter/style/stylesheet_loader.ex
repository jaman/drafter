defmodule Drafter.Style.StylesheetLoader do
  @moduledoc false

  use GenServer
  alias Drafter.Style.{CSSParser, Stylesheet, WidgetStyles}

  @type stylesheet_key :: {:app, module()} | {:file, String.t()}

  defstruct cache: %{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Load stylesheet for an app module.
  Combines CSS file (if specified) with inline styles.
  """
  def load_stylesheet(app_module) when is_atom(app_module) do
    GenServer.call(__MODULE__, {:load_stylesheet, app_module})
  end

  @doc """
  Load stylesheet from a file path.
  """
  def load_from_file(file_path) do
    GenServer.call(__MODULE__, {:load_from_file, file_path})
  end

  @doc """
  Parse inline styles from a map.
  """
  def load_inline(styles) when is_map(styles) do
    base = WidgetStyles.default_stylesheet()

    Enum.reduce(styles, base, fn {selector, properties}, acc ->
      Stylesheet.add_rule(acc, selector, properties)
    end)
  end

  @doc """
  Clear the stylesheet cache.
  """
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
    result = do_load_stylesheet(app_module, state.cache)
    {:reply, {:ok, result.stylesheet}, state}
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
