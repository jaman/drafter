defmodule Drafter.Widget.PrettyTest do
  use ExUnit.Case
  alias Drafter.Widget.Pretty

  setup :setup_session_pdict

  defdelegate setup_session_pdict(ctx), to: Drafter.Test.SessionSetup

  describe "mount/1" do
    test "mounts with basic data" do
      state = Pretty.mount(%{data: [1, 2, 3]})
      assert state.data == [1, 2, 3]
      assert state.syntax_highlighting == true
      assert state.expand == false
    end

    test "mounts with syntax highlighting disabled" do
      state = Pretty.mount(%{data: [1, 2, 3], syntax_highlighting: false})
      assert state.syntax_highlighting == false
    end

    test "mounts with expand enabled" do
      state = Pretty.mount(%{data: [1, 2, 3], expand: true})
      assert state.expand == true
    end

    test "mounts with nil data" do
      state = Pretty.mount(%{data: nil})
      assert state.data == nil
    end
  end

  describe "render/2" do
    test "renders nil" do
      state = Pretty.mount(%{data: nil})
      rect = %{width: 20, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders boolean with syntax highlighting" do
      state = Pretty.mount(%{data: true, syntax_highlighting: true})
      rect = %{width: 10, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders atom with syntax highlighting" do
      state = Pretty.mount(%{data: :test_atom, syntax_highlighting: true})
      rect = %{width: 20, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders integer with syntax highlighting" do
      state = Pretty.mount(%{data: 42, syntax_highlighting: true})
      rect = %{width: 10, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders float with syntax highlighting" do
      state = Pretty.mount(%{data: 3.14, syntax_highlighting: true})
      rect = %{width: 10, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders string with syntax highlighting" do
      state = Pretty.mount(%{data: "hello", syntax_highlighting: true})
      rect = %{width: 20, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders list with syntax highlighting" do
      state = Pretty.mount(%{data: [1, 2, 3], syntax_highlighting: true})
      rect = %{width: 20, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders map with syntax highlighting" do
      state = Pretty.mount(%{data: %{a: 1, b: 2}, syntax_highlighting: true})
      rect = %{width: 30, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders keyword list with syntax highlighting" do
      state = Pretty.mount(%{data: [a: 1, b: 2], syntax_highlighting: true})
      rect = %{width: 30, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders struct with syntax highlighting" do
      state = Pretty.mount(%{data: %URI{path: "/test"}, syntax_highlighting: true})
      rect = %{width: 40, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders without syntax highlighting" do
      state = Pretty.mount(%{data: [1, 2, 3], syntax_highlighting: false})
      rect = %{width: 20, height: 1}
      strips = Pretty.render(state, rect)
      assert length(strips) == 1
    end

    test "renders expanded format" do
      state = Pretty.mount(%{data: [1, 2, 3], expand: true})
      rect = %{width: 20, height: 5}
      strips = Pretty.render(state, rect)
      assert length(strips) > 1
    end

    test "handles complex nested structures" do
      data = %{
        users: [
          %{name: "Alice", age: 30},
          %{name: "Bob", age: 25}
        ],
        count: 2
      }

      state = Pretty.mount(%{data: data, syntax_highlighting: true})
      rect = %{width: 60, height: 10}
      strips = Pretty.render(state, rect)
      assert strips != ""
    end
  end

  describe "update/2" do
    test "updates data" do
      state = Pretty.mount(%{data: [1, 2, 3]})
      new_state = Pretty.update(%{data: [4, 5, 6]}, state)
      assert new_state.data == [4, 5, 6]
    end

    test "toggles syntax highlighting" do
      state = Pretty.mount(%{data: [1, 2, 3], syntax_highlighting: true})
      new_state = Pretty.update(%{syntax_highlighting: false}, state)
      assert new_state.syntax_highlighting == false
    end

    test "toggles expand" do
      state = Pretty.mount(%{data: [1, 2, 3], expand: false})
      new_state = Pretty.update(%{expand: true}, state)
      assert new_state.expand == true
    end

    test "preserves other fields when updating" do
      state = Pretty.mount(%{data: [1], syntax_highlighting: true, expand: false})
      new_state = Pretty.update(%{data: [2]}, state)
      assert new_state.syntax_highlighting == true
      assert new_state.expand == false
    end
  end

  describe "handle_event/2" do
    test "returns noreply for all events" do
      state = Pretty.mount(%{data: [1, 2, 3]})
      assert {:noreply, _} = Pretty.handle_event(:any_event, state)
    end
  end

  describe "format_pretty/3" do
    test "formats nil correctly" do
      output = Pretty.format_pretty(nil, true, false)
      assert output =~ "nil"
    end

    test "formats boolean correctly" do
      output = Pretty.format_pretty(true, true, false)
      assert output =~ "true"
    end

    test "formats atom correctly" do
      output = Pretty.format_pretty(:my_atom, true, false)
      assert output =~ ":my_atom"
    end

    test "formats integer correctly" do
      output = Pretty.format_pretty(42, true, false)
      assert output =~ "42"
    end

    test "formats float correctly" do
      output = Pretty.format_pretty(3.14, true, false)
      assert output =~ "3.14"
    end

    test "formats string correctly" do
      output = Pretty.format_pretty("hello", true, false)
      assert output =~ ~s("hello")
    end

    test "formats list correctly" do
      output = Pretty.format_pretty([1, 2, 3], true, false)
      assert output =~ "["
      assert output =~ "]"
    end

    test "formats map with atom keys correctly" do
      output = Pretty.format_pretty(%{a: 1, b: 2}, true, false)
      assert output =~ "%"
      assert output =~ "{"
      assert output =~ ":a"
      assert output =~ ":b"
    end

    test "formats keyword list correctly" do
      output = Pretty.format_pretty([a: 1, b: 2], true, false)
      assert output =~ "["
    end

    test "formats struct correctly" do
      output = Pretty.format_pretty(%URI{path: "/test"}, true, false)
      assert output =~ "%URI"
    end

    test "expands nested structures when expand is true" do
      output = Pretty.format_pretty([1, 2, 3], true, true)
      assert output =~ "\n"
    end
  end

  describe "syntax highlighting colors" do
    test "includes color markers when highlighting is enabled" do
      output = Pretty.format_pretty([1, 2, 3], true, false)
      assert output =~ ~r/§\{[a-z_]+\}/
    end

    test "does not include color markers when highlighting is disabled" do
      output = Pretty.format_pretty([1, 2, 3], false, false)
      refute output =~ ~r/§\{[a-z_]+\}/
    end

    test "colors nil values correctly" do
      output = Pretty.format_pretty(nil, true, false)
      assert output =~ "§{nil}"
    end

    test "colors boolean values correctly" do
      output = Pretty.format_pretty(true, true, false)
      assert output =~ "§{boolean}"
    end

    test "colors atoms correctly" do
      output = Pretty.format_pretty(:test, true, false)
      assert output =~ "§{atom}"
    end

    test "colors integers correctly" do
      output = Pretty.format_pretty(42, true, false)
      assert output =~ "§{integer}"
    end

    test "colors floats correctly" do
      output = Pretty.format_pretty(3.14, true, false)
      assert output =~ "§{float}"
    end

    test "colors strings correctly" do
      output = Pretty.format_pretty("test", true, false)
      assert output =~ "§{string}"
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

  describe "parse_color_spec/1" do
    test "parses nil color spec" do
      color = Pretty.parse_color_spec("{nil}")
      assert color == Pretty.syntax_colors().nil
    end

    test "parses boolean color spec" do
      color = Pretty.parse_color_spec("{boolean}")
      assert color == Pretty.syntax_colors().boolean
    end

    test "parses atom color spec" do
      color = Pretty.parse_color_spec("{atom}")
      assert color == Pretty.syntax_colors().atom
    end

    test "parses integer color spec" do
      color = Pretty.parse_color_spec("{integer}")
      assert color == Pretty.syntax_colors().integer
    end

    test "parses float color spec" do
      color = Pretty.parse_color_spec("{float}")
      assert color == Pretty.syntax_colors().float
    end

    test "parses string color spec" do
      color = Pretty.parse_color_spec("{string}")
      assert color == Pretty.syntax_colors().string
    end

    test "parses unknown color spec as default" do
      color = Pretty.parse_color_spec("{unknown}")
      assert color == Pretty.syntax_colors().default
    end
  end
end
