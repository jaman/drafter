defmodule Drafter.ReadmeVersionTest do
  use ExUnit.Case, async: true

  alias Drafter.Dev.ReadmeVersion

  doctest ReadmeVersion

  @readme Path.join(__DIR__, "../README.md")

  test "the README installation snippet names the current requirement" do
    assert ReadmeVersion.current?(@readme),
           """
           README.md names #{inspect(ReadmeVersion.current(File.read!(@readme)))} \
           but mix.exs implies #{inspect(ReadmeVersion.requirement())}.

           Run `mix drafter.readme`.
           """
  end

  test "the project version satisfies the requirement the README names" do
    requirement = File.read!(@readme) |> ReadmeVersion.current()

    assert Version.match?(Mix.Project.config()[:version], requirement)
  end

  describe "render/2" do
    test "rewrites an existing snippet" do
      readme = """
      ## Installation

      Add `drafter` to your `mix.exs`:

      ```elixir
      def deps do
        [
          {:drafter, "~> 0.1"}
        ]
      end
      ```

      ## Quick Start
      """

      rendered = ReadmeVersion.render(readme, "~> 9.4")

      assert rendered =~ ~s({:drafter, "~> 9.4"})
      refute rendered =~ ~s({:drafter, "~> 0.1"})
      assert rendered =~ "Add `drafter` to your `mix.exs`:"
      assert rendered =~ "## Quick Start"
    end

    test "raises when there is no installation snippet" do
      assert_raise RuntimeError, fn ->
        ReadmeVersion.render("# Drafter\n\nNo installation section.\n", "~> 9.4")
      end
    end
  end
end
