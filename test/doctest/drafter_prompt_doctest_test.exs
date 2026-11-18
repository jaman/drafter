defmodule Drafter.PromptDoctestTest do
  use ExUnit.Case, async: true

  doctest Drafter.Prompt.Choice
  doctest Drafter.Prompt.Completion
  doctest Drafter.Prompt.Editor
  doctest Drafter.Prompt.Frame
  doctest Drafter.Prompt.Window
end
