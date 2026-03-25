defmodule Drafter.Widget.Trait.AnimatableTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Animatable

  describe "metadata" do
    test "name is :animatable" do
      assert :animatable = Animatable.name()
    end

    test "no dependencies" do
      assert [] = Animatable.dependencies()
    end

    test "no handles (passive trait)" do
      assert [] = Animatable.handles()
    end

    test "is layout static" do
      assert Animatable.layout_static?()
    end

    test "render affecting fields include _render_timestamp" do
      assert [:_render_timestamp] = Animatable.render_affecting_fields()
    end
  end

  describe "default_state/0" do
    test "initializes timestamp to zero" do
      state = Animatable.default_state()
      assert state._render_timestamp == 0
    end
  end
end
