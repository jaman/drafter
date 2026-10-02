defmodule Drafter.Widget.PrettyTest do
  use ExUnit.Case
  alias Drafter.Widget.Pretty

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "render/2" do
    test "renders expanded format" do
      state = Pretty.mount(%{data: [1, 2, 3], expand: true})
      rect = %{width: 20, height: 5}
      strips = Pretty.render(state, rect)
      assert length(strips) > 1
    end
  end

  describe "syntax highlighting colors" do
    test "does not include color markers when highlighting is disabled" do
      output = Pretty.format_pretty([1, 2, 3], false, false)
      refute output =~ ~r/§\{[a-z_]+\}/
    end

    test "colors keyword keys correctly" do
      output = Pretty.format_pretty([a: 1], true, false)
      assert output =~ "§{keyword_key}"
    end

    test "colors map keys correctly" do
      output = Pretty.format_pretty(%{"key" => "value"}, true, false)
      assert output =~ "§{map_key}"
    end

    test "colors struct names correctly" do
      output = Pretty.format_pretty(%URI{}, true, false)
      assert output =~ "§{struct_name}"
    end

    test "colors separators correctly" do
      output = Pretty.format_pretty([1, 2], true, false)
      assert output =~ "§{separator}"
    end
  end
end
