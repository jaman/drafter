defmodule Drafter.CharacterWidthConformanceTest do
  use ExUnit.Case, async: true

  @implementations [Drafter.CharacterWidth.Default, Drafter.CharacterWidth]

  defp each_implementation(assertion), do: Enum.each(@implementations, assertion)

  describe "ASCII" do
    test "printable_ascii? agrees with the width it implies" do
      each_implementation(fn module ->
        for text <- ["hello", "", "a b c", "~!@#"] do
          assert module.printable_ascii?(text)
          assert module.string(text) == byte_size(text)
        end
      end)
    end

    test "printable_ascii? rejects anything whose width is not its byte count" do
      each_implementation(fn module ->
        for text <- ["日本", "café", "a\tb", "\e[31m", "👍"] do
          refute module.printable_ascii?(text),
                 "#{inspect(module)} called #{inspect(text)} printable ASCII"
        end
      end)
    end
  end
end
