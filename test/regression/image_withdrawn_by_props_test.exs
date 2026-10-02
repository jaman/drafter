defmodule Drafter.Regression.ImageWithdrawnByPropsTest do
  @moduledoc """
  A widget switched from a picture to glyphs by its props must show the glyphs.

  The widget server holds the widget's true state and withdraws the image when a
  render turns it off, but the renderer decides placement from the hierarchy's copy
  of the state, which a props update does not refresh. Judging from that copy, the
  renderer placed the withdrawn image straight back, and the rows under it were never
  drawn again.
  """

  use ExUnit.Case, async: false

  alias Drafter.Draw.Strip
  alias Drafter.Test, as: DT

  defmodule PictureOrText do
    @moduledoc false
    use Drafter.Widget, handles: []

    defstruct picture: true

    def component_tag, do: :picture_or_text
    def from_component_opts(_args, opts), do: %{picture: Keyword.get(opts, :picture, true)}

    @impl true
    def mount(props), do: %__MODULE__{picture: Map.get(props, :picture, true)}

    @impl true
    def update(props, state), do: %{state | picture: Map.get(props, :picture, state.picture)}

    @impl true
    def image_active?(%__MODULE__{picture: picture}), do: picture

    def image(%__MODULE__{picture: true}, rect, _id),
      do: {"IMG", "", %{dx: 0, dy: 0, cols: rect.width, rows: rect.height}}

    def image(_state, _rect, _id), do: nil

    @impl true
    def render(%__MODULE__{picture: picture}, rect) do
      glyph = if picture, do: " ", else: "#"
      List.duplicate(Strip.from_text(String.duplicate(glyph, rect.width)), rect.height)
    end
  end

  defmodule App do
    @moduledoc false
    use Drafter.App

    def mount(_props), do: %{picture: true}

    def render(state),
      do:
        vertical([
          label("hud"),
          {:picture_or_text, [id: :scene, picture: state.picture, flex: 1]}
        ])

    def handle_event({:key, :t}, state), do: {:ok, %{state | picture: not state.picture}}
    def handle_event(_event, state), do: {:noreply, state}
  end

  setup do
    Drafter.Widget.Registry.register(PictureOrText)
    :ok
  end

  test "glyphs replace the image once the props turn the picture off" do
    ctx = DT.start_headless(App, %{}, size: {20, 4})
    Process.sleep(100)
    DT.sync(ctx)

    DT.send_key(ctx, :t)
    assert :ok == DT.wait_for(ctx, &glyph_rows?/1)

    Process.sleep(200)
    DT.sync(ctx)
    assert glyph_rows?(ctx)

    DT.send_key(ctx, :t)
    assert :ok == DT.wait_for(ctx, &(not glyph_rows?(&1)))

    DT.stop(ctx)
  end

  defp glyph_rows?(ctx) do
    ctx |> DT.screen_lines() |> Enum.drop(1) |> Enum.all?(&String.starts_with?(&1, "####"))
  end
end
