defmodule Drafter.ModuleComponentTest do
  @moduledoc """
  A `{Module, props}` component renders.

  That pair is the shape the public `Drafter.*` constructors return and the shape
  `guides/writing_widgets.md` teaches for publishing a widget library, so the
  renderer accepts it alongside `{tag, opts}` with a keyword `opts`. The component
  draws its text, appears in the hierarchy as a widget of its own, takes its id from
  an `:id` in the props, and has the props handed to its `mount/1`.
  """

  use ExUnit.Case, async: false

  defmodule LibraryWidget do
    @moduledoc false
    use Drafter.Widget, handles: []

    alias Drafter.Draw.{Segment, Strip}

    defstruct label: "none"

    def component_tag, do: :library_widget
    def from_component_opts(_args, opts), do: %{label: Keyword.get(opts, :label, "none")}
    def preferred_height(_args, _opts), do: 1

    @impl true
    def mount(props), do: %__MODULE__{label: Map.get(props, :label, "none")}

    @impl true
    def render(%__MODULE__{label: label}, _rect) do
      [Strip.new([Segment.new("LIB:#{label}", %{})])]
    end
  end

  defmodule ConstructorApp do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{}

    def render(_state) do
      vertical([
        Drafter.label("from constructor"),
        {LibraryWidget, %{label: "from library", id: :chosen_id}}
      ])
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    ctx = Drafter.Test.start_headless(ConstructorApp, %{}, width: 40, height: 6)
    Drafter.Test.sync(ctx)
    on_exit(fn -> Drafter.Test.stop(ctx) end)
    %{ctx: ctx}
  end

  defp widgets(ctx), do: ctx |> Drafter.Test.get_widget_hierarchy() |> Map.get(:widgets)

  defp await_text(ctx, text) do
    Drafter.Test.wait_for(ctx, fn c -> Drafter.Test.screen_text(c) =~ text end, timeout: 1000)
  end

  test "a Drafter.* constructor renders its text", %{ctx: ctx} do
    assert await_text(ctx, "from constructor") == :ok,
           "screen was: #{inspect(Drafter.Test.screen_text(ctx))}"
  end

  test "a third-party widget library's {Module, props} renders", %{ctx: ctx} do
    assert await_text(ctx, "LIB:from library") == :ok,
           "screen was: #{inspect(Drafter.Test.screen_text(ctx))}"
  end

  test "the module component appears in the hierarchy as its own widget", %{ctx: ctx} do
    modules = ctx |> widgets() |> Enum.map(fn {_id, info} -> info.module end)

    assert LibraryWidget in modules
    assert Drafter.Widget.Label in modules
  end

  test "an id in the props becomes the widget id", %{ctx: ctx} do
    assert :chosen_id in (ctx |> widgets() |> Map.keys())
  end

  test "the props reach the widget's mount", %{ctx: ctx} do
    {_id, info} = ctx |> widgets() |> Enum.find(fn {_id, i} -> i.module == LibraryWidget end)
    state = if is_pid(info.pid), do: Drafter.WidgetServer.get_state(info.pid), else: info.state

    assert state.label == "from library"
  end
end
