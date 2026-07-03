defmodule Drafter.Terminal.DriverEventTest do
  use ExUnit.Case, async: true

  defp start_driver do
    {:ok, driver} = GenServer.start_link(Drafter.Terminal.Driver, [event_manager: self()], [])
    driver
  end

  defp assert_event(expected) do
    assert_receive {:"$gen_cast", {:event, ^expected}}, 500
  end

  test "assembled CSI F-key chunks become key events" do
    driver = start_driver()

    send(driver, {:stdin, "\e[12~"})
    assert_event({:key, :f2})

    send(driver, {:stdin, "\e[13~"})
    assert_event({:key, :f3})

    send(driver, {:stdin, "\e[15~"})
    assert_event({:key, :f5})
  end

  test "assembled SS3 F-key chunks become key events" do
    driver = start_driver()

    send(driver, {:stdin, "\eOQ"})
    assert_event({:key, :f2})

    send(driver, {:stdin, "\eOS"})
    assert_event({:key, :f4})
  end

  test "SGR mouse chunks become mouse events" do
    driver = start_driver()
    send(driver, {:stdin, "\e[<0;12;5M"})

    assert_receive {:"$gen_cast", {:event, {:mouse, %{type: :mouse_down, x: 11, y: 4}}}}, 500
  end

  test "a bare escape chunk becomes the escape key" do
    driver = start_driver()
    send(driver, {:stdin, "\e"})
    assert_event({:key, :escape})
  end

  test "split multi-byte UTF-8 chunks reassemble into one char event" do
    driver = start_driver()
    <<first, rest::binary>> = "好"

    send(driver, {:stdin, <<first>>})
    send(driver, {:stdin, rest})

    <<codepoint::utf8>> = "好"
    assert_event({:char, codepoint})
  end
end
