defmodule Drafter.Widget.ImageActiveTest do
  @moduledoc """
  A widget only costs anything on the image path while it is actually painting one.

  `Drafter.Widget.image_active?/2` is the single question the renderer asks before
  placing an image and the widget server asks before generating one, so a widget
  drawing characters must answer `false` for both to skip it.
  """

  use ExUnit.Case, async: false

  alias Drafter.Widget
  alias Drafter.Widget.{Chart, Digits, Gauge, Label, PieChart, Slider}

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  defmodule AlwaysPainting do
    @moduledoc false
    use Drafter.Widget

    def image(_state, _rect, _id), do: {"paint", "clear", %{dx: 0, dy: 0, cols: 1, rows: 1}}
  end

  describe "a widget that cannot paint an image" do
    test "is never active" do
      refute Widget.image_active?(Label, %{})
    end
  end

  describe "a widget that paints unconditionally" do
    test "is active, having no predicate of its own" do
      assert Widget.image_active?(AlwaysPainting, %{})
    end
  end

  describe "slider" do
    test "is inactive while drawing characters" do
      refute Widget.image_active?(Slider, Slider.mount(%{renderer: :text}))
      refute Widget.image_active?(Slider, Slider.mount(%{renderer: :braille}))
    end

    test "is active while drawing a picture" do
      assert Widget.image_active?(Slider, Slider.mount(%{renderer: :kitty}))
    end
  end

  describe "chart" do
    test "is inactive while drawing cells" do
      refute Widget.image_active?(Chart, Chart.mount(%{data: [1, 2, 3], renderer: :text}))
      refute Widget.image_active?(Chart, Chart.mount(%{data: [1, 2, 3], renderer: :braille}))
    end

    test "is active while drawing a picture" do
      assert Widget.image_active?(Chart, Chart.mount(%{data: [1, 2, 3], renderer: :kitty}))
    end
  end

  describe "gauge" do
    test "is inactive while drawing braille" do
      refute Widget.image_active?(Gauge, Gauge.mount(%{value: 0.5}))
    end

    test "is active while drawing a picture" do
      assert Widget.image_active?(Gauge, Gauge.mount(%{value: 0.5, renderer: :kitty}))
    end
  end

  describe "pie chart" do
    test "is inactive while drawing cells" do
      refute Widget.image_active?(PieChart, PieChart.mount(%{data: [1, 2]}))
    end

    test "is active while drawing a picture" do
      assert Widget.image_active?(PieChart, PieChart.mount(%{data: [1, 2], renderer: :kitty}))
    end
  end

  describe "digits" do
    test "is inactive while drawing cells" do
      refute Widget.image_active?(Digits, Digits.mount(%{text: "42"}))
    end

    test "is active while drawing a picture" do
      assert Widget.image_active?(Digits, Digits.mount(%{text: "42", renderer: :kitty}))
    end
  end
end
