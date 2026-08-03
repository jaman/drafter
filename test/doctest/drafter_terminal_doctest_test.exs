defmodule Drafter.TerminalDoctestTest do
  use ExUnit.Case, async: true

  doctest Drafter.Terminal.ANSI
  doctest Drafter.Terminal.InputBuffer
  doctest Drafter.Terminal.SignalWatcher
end
