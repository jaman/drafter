defmodule Drafter.Style.SelectorMatchingTest do
  @moduledoc """
  A selector matches what it names, or nothing — never everything.

  A token a selector cannot resolve narrows the match to nothing rather than widening
  it to every widget, because both matchers read a `nil` token as "no constraint".
  Two token shapes must therefore still parse into a real value: a capitalised type
  name such as `"Button"`, and an id or class whose atom does not exist yet.
  """

  use ExUnit.Case, async: true

  alias Drafter.Style.Selector
  alias Drafter.WidgetHierarchy.Query

  defp parse(string), do: string |> Selector.parse() |> List.first()

  describe "parsing a widget type" do
    test "accepts the lowercase form" do
      assert parse("button").widget_type == :button
    end

    test "accepts the capitalised form the query docs teach" do
      assert Selector.same_name?(parse("Button").widget_type, :button)
    end

    test "underscores a multi-word capitalised name to match the module's type name" do
      assert Selector.same_name?(parse("TextInput").widget_type, :text_input)
    end

    test "keeps a name whose atom does not exist rather than dropping it" do
      parsed = parse("nosuchwidgettype")

      refute parsed.widget_type == nil
      assert Selector.same_name?(parsed.widget_type, "nosuchwidgettype")
    end
  end

  describe "matching a widget type" do
    test "a capitalised selector matches only that type" do
      assert Query.matches_type?(Drafter.Widget.Button, parse("Button").widget_type)
      refute Query.matches_type?(Drafter.Widget.Label, parse("Button").widget_type)
    end

    test "a lowercase selector matches only that type" do
      assert Query.matches_type?(Drafter.Widget.Button, parse("button").widget_type)
      refute Query.matches_type?(Drafter.Widget.Label, parse("button").widget_type)
    end

    test "a type nobody defines matches nothing at all" do
      unknown = parse("nosuchwidgettype").widget_type

      refute Query.matches_type?(Drafter.Widget.Button, unknown)
      refute Query.matches_type?(Drafter.Widget.Label, unknown)
    end

    test "an absent type is still no constraint" do
      assert Query.matches_type?(Drafter.Widget.Button, nil)
    end
  end

  describe "matching an id" do
    test "an id matches only the widget that carries it" do
      id = parse("#save_button").id

      assert Query.matches_id?(:save_button, id)
      refute Query.matches_id?(:cancel_button, id)
    end

    test "the capitalised ids the renderer generates are parsed" do
      id = parse("#Charts_chart_12").id

      assert Query.matches_id?(:Charts_chart_12, id)
      refute Query.matches_id?(:Charts_chart_11, id)
    end

    test "an id belonging to nothing rendered yet matches nothing" do
      id = parse("#never_rendered_widget_id").id

      refute id == nil
      refute Query.matches_id?(:some_other_widget, id)
    end
  end

  describe "matching classes" do
    test "a class narrows to widgets carrying it" do
      classes = parse("button.primary").classes

      assert Query.matches_classes?(%{classes: [:primary]}, classes)
      refute Query.matches_classes?(%{classes: [:secondary]}, classes)
    end

    test "a class nobody uses matches nothing rather than being dropped" do
      classes = parse(".nosuchclassanywhere").classes

      assert length(classes) == 1
      refute Query.matches_classes?(%{classes: [:primary]}, classes)
      refute Query.matches_classes?(%{classes: []}, classes)
    end

    test "a capitalised selector still carries its class" do
      classes = parse("Button.primary").classes

      assert Query.matches_classes?(%{classes: [:primary]}, classes)
    end
  end

  describe "the style engine agrees with the query engine" do
    test "a capitalised selector matches only its type" do
      selector = parse("Button")

      assert Selector.matches?(selector, %{widget_type: :button, classes: []})
      refute Selector.matches?(selector, %{widget_type: :label, classes: []})
    end

    test "an unresolvable type matches nothing" do
      selector = parse("nosuchwidgettype")

      refute Selector.matches?(selector, %{widget_type: :button, classes: []})
    end
  end
end
