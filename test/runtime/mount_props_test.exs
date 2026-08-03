defmodule Drafter.Runtime.MountPropsTest do
  @moduledoc """
  `Drafter.Runtime.mount_props/1` is the single contract for the props an app is
  mounted with, whichever entry point started it.

  It reads the props out of an option list, yields `%{}` when none were given, never
  leaks the surrounding options into the props, and never nests them under a `:props`
  key. Every entry point — a local run, a pushed nested session, an ssh or telnet
  transport — resolves props through it and so mounts an app with the same map.

  Coverage stops at that function. `Drafter.Test.Harness` mounts the app itself rather
  than going through `Drafter.Runtime.AppLoop.run/2`, so a call site that resolves
  props some other way than `mount_props/1` still passes this file.
  """

  use ExUnit.Case, async: true

  alias Drafter.Runtime

  describe "mount_props/1" do
    test "reads the props out of an option list" do
      assert Runtime.mount_props(props: %{cwd: "/tmp", history_file: "h"}) == %{
               cwd: "/tmp",
               history_file: "h"
             }
    end

    test "is empty when no props were given" do
      assert Runtime.mount_props([]) == %{}
      assert Runtime.mount_props(mode: :isolated, halt_on_exit: false) == %{}
    end

    test "never leaks the surrounding options into the props" do
      opts = [props: %{cwd: "/tmp"}, mode: :shared, halt_on_exit: false, refresh_rate: 60]

      assert Runtime.mount_props(opts) == %{cwd: "/tmp"}
    end

    test "does not nest the props under a :props key" do
      props = Runtime.mount_props(props: %{hello: "world"})

      refute Map.has_key?(props, :props)
      assert props.hello == "world"
    end

    test "accepts a keyword list of props" do
      assert Runtime.mount_props(props: [cwd: "/tmp"]) == %{cwd: "/tmp"}
    end

    test "passes a bare map straight through, for callers that already hold props" do
      assert Runtime.mount_props(%{cwd: "/tmp"}) == %{cwd: "/tmp"}
    end
  end
end
