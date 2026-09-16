defmodule Drafter.Transport.SSHDriverTest do
  use ExUnit.Case, async: false

  alias Drafter.Transport.SSHDriver

  test "the driver shuts the session down when its input ends, as a dropped connection does" do
    {:ok, driver} = SSHDriver.start_link(group_leader: Process.group_leader(), session: self())
    send(driver, :stdin_closed)
    assert_receive :shutdown, 500
    GenServer.stop(driver)
  end
end
