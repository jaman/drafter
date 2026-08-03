defmodule Drafter.Widget.Trait do
  @moduledoc """
  Behaviour for composable widget traits.

  Traits are reusable capabilities that can be composed onto widgets.
  Each trait manages its own slice of state, handles specific events,
  and can decorate rendering via pre/post render hooks.

  A widget opts into traits with `use Drafter.Widget, traits: [...]`; the functions
  here are what that macro calls to turn the trait list into handles, default state,
  a capability bitmap, and the scroll configuration.

  ## Built-in trait names

  `resolve_module/1` maps these atoms to modules; any other atom is taken to be a
  module name already.

    * `:focusable` - `Drafter.Widget.Trait.Focusable`
    * `:scrollable` - `Drafter.Widget.Trait.Scrollable`
    * `:selectable` - `Drafter.Widget.Trait.Selectable`
    * `:editable` - `Drafter.Widget.Trait.Editable`
    * `:collapsible` - `Drafter.Widget.Trait.Collapsible`
    * `:resizable` - `Drafter.Widget.Trait.Resizable`
    * `:draggable` - `Drafter.Widget.Trait.Draggable`
    * `:animatable` - `Drafter.Widget.Trait.Animatable`

  ## Optional callbacks and their defaults

  A trait that omits an optional callback is treated as follows:

    * `c:dependencies/0` - no dependencies
    * `c:handles/0` - handles nothing
    * `c:render_affecting_fields/0` - every key of `c:default_state/0`
    * `c:layout_static?/0` - `true`
  """

  alias Drafter.Draw.Strip

  @type trait_name :: atom()
  @type trait_state :: map()
  @type event_result ::
          {:ok, trait_state()}
          | {:pass, trait_state()}
          | {:consume, trait_state()}

  @callback name() :: trait_name()
  @callback default_state() :: trait_state()
  @callback dependencies() :: [trait_name()]
  @callback handles() :: [atom()]
  @callback render_affecting_fields() :: [atom()]
  @callback layout_static?() :: boolean()

  @callback handle_event(term(), trait_state(), widget_state :: map()) :: event_result()
  @callback pre_render(trait_state(), widget_state :: map(), rect :: map()) ::
              {trait_state(), map()}
  @callback post_render([Strip.t()], trait_state(), widget_state :: map(), rect :: map()) ::
              [Strip.t()]

  @optional_callbacks [
    dependencies: 0,
    handles: 0,
    render_affecting_fields: 0,
    layout_static?: 0,
    handle_event: 3,
    pre_render: 3,
    post_render: 4
  ]

  @builtin_traits %{
    focusable: Drafter.Widget.Trait.Focusable,
    scrollable: Drafter.Widget.Trait.Scrollable,
    selectable: Drafter.Widget.Trait.Selectable,
    editable: Drafter.Widget.Trait.Editable,
    collapsible: Drafter.Widget.Trait.Collapsible,
    resizable: Drafter.Widget.Trait.Resizable,
    draggable: Drafter.Widget.Trait.Draggable,
    animatable: Drafter.Widget.Trait.Animatable
  }

  @handle_bits %{
    scroll: 0b000001,
    keyboard: 0b000010,
    char: 0b000100,
    click: 0b001000,
    drag: 0b010000,
    hover: 0b100000,
    press: 0b1000000,
    mouse_up: 0b10000000,
    focus: 0b100000000,
    blur: 0b100000000
  }

  @doc """
  The module behind a trait name.

  Returns the built-in module for one of the names listed in the module doc, and
  `name` itself for anything else — no check is made that the result is a module.

      iex> Drafter.Widget.Trait.resolve_module(:focusable)
      Drafter.Widget.Trait.Focusable

      iex> Drafter.Widget.Trait.resolve_module(:not_a_trait)
      :not_a_trait
  """
  @spec resolve_module(atom() | module()) :: module()
  def resolve_module(name) when is_atom(name) do
    Map.get(@builtin_traits, name) || name
  end

  @doc """
  Expands trait specs into the full deduplicated list of trait modules.

  Each spec is a trait name, a module, or a `{name, opts}` pair whose options are
  discarded. Every trait's `c:dependencies/0` are pulled in transitively and appear
  before the trait that asked for them. The `opts` argument is ignored.

      iex> Drafter.Widget.Trait.resolve_all([:focusable, :scrollable], [])
      [Drafter.Widget.Trait.Focusable, Drafter.Widget.Trait.Scrollable]

      iex> Drafter.Widget.Trait.resolve_all([{:focusable, step: 2}, :focusable], [])
      [Drafter.Widget.Trait.Focusable]
  """
  @spec resolve_all([atom() | {atom(), keyword()} | module()], keyword()) :: [module()]
  def resolve_all(trait_specs, _opts) do
    trait_specs
    |> Enum.map(&normalize_spec/1)
    |> resolve_dependencies()
    |> Enum.uniq()
  end

  @doc """
  The deduplicated union of every trait's `c:handles/0`, in trait order.

  A trait that does not export `c:handles/0` contributes nothing.

      iex> Drafter.Widget.Trait.collect_handles([Drafter.Widget.Trait.Focusable])
      [:focus, :blur]

      iex> Drafter.Widget.Trait.collect_handles([])
      []
  """
  @spec collect_handles([module()]) :: [atom()]
  def collect_handles(trait_modules) do
    trait_modules
    |> Enum.flat_map(&get_handles/1)
    |> Enum.uniq()
  end

  @doc """
  Whether any trait reports the name `:focusable`, which is what makes the widget
  take part in tab order.

      iex> Drafter.Widget.Trait.any_focusable?([Drafter.Widget.Trait.Focusable])
      true

      iex> Drafter.Widget.Trait.any_focusable?([Drafter.Widget.Trait.Scrollable])
      false
  """
  @spec any_focusable?([module()]) :: boolean()
  def any_focusable?(trait_modules) do
    Enum.any?(trait_modules, fn mod ->
      ensure_loaded!(mod)
      mod.name() == :focusable
    end)
  end

  @doc """
  Every trait's `c:default_state/0` merged left to right, so a later trait wins a
  key clash.

      iex> Drafter.Widget.Trait.merge_default_states([Drafter.Widget.Trait.Focusable])
      %{focused: false}

      iex> Drafter.Widget.Trait.merge_default_states([])
      %{}
  """
  @spec merge_default_states([module()]) :: map()
  def merge_default_states(trait_modules) do
    Enum.reduce(trait_modules, %{}, fn mod, acc ->
      ensure_loaded!(mod)
      Map.merge(acc, mod.default_state())
    end)
  end

  @doc """
  The scroll configuration for a trait-mode widget, or `nil` when
  `Drafter.Widget.Trait.Scrollable` is not among its traits.

  Reads `opts[:scroll]`, itself defaulting to `[]`:

    * `:direction` - `:vertical | :horizontal`. Default `:vertical`.
    * `:step` - `t:pos_integer/0` rows per wheel notch. Default `1`.
    * `:show_scrollbar` - `:auto | true | false`. Default `:auto`.

  These differ from the handles-mode `:scroll` defaults documented on
  `Drafter.Widget`, which are `:horizontal` and a step of `5`.

      iex> Drafter.Widget.Trait.scroll_config([Drafter.Widget.Trait.Scrollable], [])
      %{direction: :vertical, step: 1, show_scrollbar: :auto}

      iex> Drafter.Widget.Trait.scroll_config([Drafter.Widget.Trait.Scrollable], scroll: [step: 4])
      %{direction: :vertical, step: 4, show_scrollbar: :auto}

      iex> Drafter.Widget.Trait.scroll_config([Drafter.Widget.Trait.Focusable], [])
      nil
  """
  @spec scroll_config([module()], keyword()) :: map() | nil
  def scroll_config(trait_modules, opts) do
    scrollable_mod = resolve_module(:scrollable)

    if scrollable_mod in trait_modules do
      scroll_opts = Keyword.get(opts, :scroll, [])

      %{
        direction: Keyword.get(scroll_opts, :direction, :vertical),
        step: Keyword.get(scroll_opts, :step, 1),
        show_scrollbar: Keyword.get(scroll_opts, :show_scrollbar, :auto)
      }
    else
      nil
    end
  end

  @doc """
  The deduplicated union of every trait's `c:render_affecting_fields/0`, in trait
  order.

  A trait that does not export it contributes the keys of its
  `c:default_state/0` instead.

      iex> Drafter.Widget.Trait.collect_render_affecting_fields([Drafter.Widget.Trait.Focusable])
      [:focused]
  """
  @spec collect_render_affecting_fields([module()]) :: [atom()]
  def collect_render_affecting_fields(trait_modules) do
    trait_modules
    |> Enum.flat_map(&get_render_affecting_fields/1)
    |> Enum.uniq()
  end

  @doc """
  Whether every trait reports `c:layout_static?/0` as `true`, treating a trait that
  does not export it as `true`. An empty list is static.

      iex> Drafter.Widget.Trait.all_layout_static?([Drafter.Widget.Trait.Focusable])
      true

      iex> Drafter.Widget.Trait.all_layout_static?([])
      true
  """
  @spec all_layout_static?([module()]) :: boolean()
  def all_layout_static?(trait_modules) do
    Enum.all?(trait_modules, &get_layout_static?/1)
  end

  import Bitwise

  @doc """
  The capability bitmap for a trait list, for use with `handles_event?/2`.

  Ors together the bit of every handle the traits collect, plus the focus bit when
  any trait is focusable. A handle with no bit assigned contributes nothing.

      iex> Drafter.Widget.Trait.build_bitmap([])
      0

      iex> bitmap = Drafter.Widget.Trait.build_bitmap([Drafter.Widget.Trait.Scrollable])
      iex> {Drafter.Widget.Trait.handles_event?(bitmap, :scroll), Drafter.Widget.Trait.handles_event?(bitmap, :drag)}
      {true, false}
  """
  @spec build_bitmap([module()]) :: non_neg_integer()
  def build_bitmap(trait_modules) do
    handles_bitmap =
      trait_modules
      |> collect_handles()
      |> Enum.reduce(0, fn handle, acc -> acc ||| Map.get(@handle_bits, handle, 0) end)

    if any_focusable?(trait_modules) do
      handles_bitmap ||| @handle_bits.focus
    else
      handles_bitmap
    end
  end

  @doc """
  Whether a bitmap built by `build_bitmap/1` carries the bit for `event_type`.

  Recognised event types are `:scroll`, `:keyboard`, `:char`, `:click`, `:drag`,
  `:hover`, `:press`, `:mouse_up`, `:focus` and `:blur`. `:focus` and `:blur` share
  one bit, so a bitmap that answers `true` for either answers `true` for both. Any
  other atom is always `false`.

      iex> bitmap = Drafter.Widget.Trait.build_bitmap([Drafter.Widget.Trait.Focusable])
      iex> {Drafter.Widget.Trait.handles_event?(bitmap, :focus), Drafter.Widget.Trait.handles_event?(bitmap, :blur)}
      {true, true}

      iex> Drafter.Widget.Trait.handles_event?(0, :keyboard)
      false

      iex> Drafter.Widget.Trait.handles_event?(0xFFFF, :unknown_event)
      false
  """
  @spec handles_event?(non_neg_integer(), atom()) :: boolean()
  def handles_event?(bitmap, event_type) do
    bit = Map.get(@handle_bits, event_type, 0)
    (bitmap &&& bit) != 0
  end

  defp normalize_spec({name, _opts}) when is_atom(name), do: resolve_module(name)
  defp normalize_spec(name) when is_atom(name), do: resolve_module(name)

  defp get_handles(mod) do
    ensure_loaded!(mod)
    if function_exported?(mod, :handles, 0), do: mod.handles(), else: []
  end

  defp get_render_affecting_fields(mod) do
    ensure_loaded!(mod)

    if function_exported?(mod, :render_affecting_fields, 0),
      do: mod.render_affecting_fields(),
      else: Map.keys(mod.default_state())
  end

  defp get_layout_static?(mod) do
    ensure_loaded!(mod)
    if function_exported?(mod, :layout_static?, 0), do: mod.layout_static?(), else: true
  end

  defp resolve_dependencies(modules) do
    resolve_dependencies(modules, MapSet.new(), [])
  end

  defp resolve_dependencies([], _seen, acc), do: Enum.reverse(acc)

  defp resolve_dependencies([mod | rest], seen, acc) do
    if MapSet.member?(seen, mod) do
      resolve_dependencies(rest, seen, acc)
    else
      deps = get_unseen_deps(mod, seen)

      {new_seen, new_acc} =
        Enum.reduce(deps, {MapSet.put(seen, mod), acc}, &add_dep_with_transitive/2)

      resolve_dependencies(rest, new_seen, [mod | new_acc])
    end
  end

  defp add_dep_with_transitive(dep, {seen, acc}) do
    if MapSet.member?(seen, dep) do
      {seen, acc}
    else
      transitive = get_unseen_deps(dep, seen)
      {seen2, acc2} = collect_transitive(transitive, MapSet.put(seen, dep), acc)
      {seen2, [dep | acc2]}
    end
  end

  defp collect_transitive(deps, seen, acc) do
    Enum.reduce(deps, {seen, acc}, fn dd, {ss, aa} ->
      if MapSet.member?(ss, dd), do: {ss, aa}, else: {MapSet.put(ss, dd), [dd | aa]}
    end)
  end

  defp get_unseen_deps(mod, seen) do
    ensure_loaded!(mod)

    if function_exported?(mod, :dependencies, 0) do
      mod.dependencies()
      |> Enum.map(&resolve_module/1)
      |> Enum.reject(&MapSet.member?(seen, &1))
    else
      []
    end
  end

  defp ensure_loaded!(mod) do
    case Code.ensure_compiled(mod) do
      {:module, _} -> :ok
      {:error, reason} -> raise "Failed to load trait module #{inspect(mod)}: #{inspect(reason)}"
    end
  end
end
