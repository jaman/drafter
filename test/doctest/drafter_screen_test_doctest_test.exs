defmodule Drafter.ScreenTestDoctestTest do
  @moduledoc """
  Runs the doctests of `Drafter.Screen`, `Drafter.Test`, and `Drafter.Widget`.
  """

  use ExUnit.Case, async: true

  doctest Drafter.Screen
  doctest Drafter.Widget
end
