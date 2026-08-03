defmodule Drafter.AppDoctestTest do
  use ExUnit.Case, async: true

  import Drafter.App

  doctest Drafter.App, import: true
end
