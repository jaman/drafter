defmodule Drafter.Regression.TabAfterClickOnUnfocusableTest do
  @moduledoc """
  Tab after clicking a widget that handles presses but is not focusable must not crash.

  The click leaves that widget as the hierarchy's focused widget, and its state has no
  `focused` or `trap_focus` field. Reading those as `nil` and asking `nil and ...` raised
  `BadBooleanError` in the event router and took the app down.
  """

  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip
  alias Drafter.Test, as: DT

  defmodule Pad do
    @moduledoc false
    use Drafter.Widget, handles: [:press]

    defstruct clicks: 0

    def component_tag, do: :click_pad
    def from_component_opts(_args, _opts), do: %{}

    @impl true
    def mount(_props), do: %__MODULE__{}

    @impl true
    def render(%__MODULE__{clicks: clicks}, rect) do
      List.duplicate(
        Strip.from_text(String.pad_trailing("clicks #{clicks}", rect.width)),
        rect.height
      )
    end

    @impl true
    def handle_press(_x, _y, %__MODULE__{} = state),
      do: {:ok, %{state | clicks: state.clicks + 1}}
  end

  defmodule App do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{tabs: 0}
    def render(_state), do: vertical([label("hud"), {:click_pad, [id: :pad, flex: 1]}])
    def handle_event({:key, :tab}, state), do: {:ok, %{state | tabs: state.tabs + 1}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    Drafter.Widget.Registry.register(Pad)
    :ok
  end

  test "tab still reaches the app after a click on the pad" do
    ctx = DT.start_headless(App, %{}, size: {20, 4})
    Process.sleep(100)
    DT.sync(ctx)

    DT.send_mouse(ctx, %{type: :mouse_down, x: 5, y: 2, button: :left})
    DT.sync(ctx)
    DT.send_key(ctx, :tab)
    DT.sync(ctx)

    assert DT.get_state(ctx).tabs == 1
    DT.stop(ctx)
  end
end
