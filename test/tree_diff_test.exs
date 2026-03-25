defmodule Drafter.TreeDiffTest do
  use ExUnit.Case, async: true

  alias Drafter.TreeDiff

  describe "fingerprint/1" do
    test "identical trees produce same fingerprint" do
      tree = {:vertical, [], [{:label, [text: "hello"]}, {:button, [text: "ok"]}]}
      assert TreeDiff.fingerprint(tree) == TreeDiff.fingerprint(tree)
    end

    test "different trees produce different fingerprints" do
      tree1 = {:vertical, [], [{:label, [text: "hello"]}]}
      tree2 = {:vertical, [], [{:label, [text: "world"]}]}
      refute TreeDiff.fingerprint(tree1) == TreeDiff.fingerprint(tree2)
    end

    test "structural change detected" do
      tree1 = {:vertical, [], [{:label, [text: "a"]}, {:label, [text: "b"]}]}
      tree2 = {:vertical, [], [{:label, [text: "a"]}]}
      refute TreeDiff.fingerprint(tree1) == TreeDiff.fingerprint(tree2)
    end

    test "same tag different opts produce different fingerprints" do
      tree1 = {:button, [text: "ok"]}
      tree2 = {:button, [text: "cancel"]}
      refute TreeDiff.fingerprint(tree1) == TreeDiff.fingerprint(tree2)
    end

    test "id is included in fingerprint" do
      tree1 = {:button, [id: :btn1, text: "ok"]}
      tree2 = {:button, [id: :btn2, text: "ok"]}
      refute TreeDiff.fingerprint(tree1) == TreeDiff.fingerprint(tree2)
    end

    test "handles plain values" do
      assert is_integer(TreeDiff.fingerprint("hello"))
      assert is_integer(TreeDiff.fingerprint(42))
    end

    test "handles lists" do
      list = [{:label, [text: "a"]}, {:label, [text: "b"]}]
      assert is_integer(TreeDiff.fingerprint(list))
    end
  end

  describe "diff_children/2" do
    test "all kept when identical" do
      children = [{:label, [text: "a"]}, {:label, [text: "b"]}]
      ops = TreeDiff.diff_children(children, children)

      assert Enum.all?(ops, fn {action, _, _} -> action == :keep end)
    end

    test "detects added children" do
      prev = [{:label, [text: "a"]}]
      current = [{:label, [text: "a"]}, {:label, [text: "b"]}]
      ops = TreeDiff.diff_children(prev, current)

      adds = Enum.filter(ops, fn {action, _, _} -> action == :add end)
      assert length(adds) == 1
    end

    test "detects removed children" do
      prev = [{:label, [text: "a"]}, {:label, [text: "b"]}]
      current = [{:label, [text: "a"]}]
      ops = TreeDiff.diff_children(prev, current)

      removes = Enum.filter(ops, fn {action, _, _} -> action == :remove end)
      assert length(removes) == 1
    end

    test "handles empty lists" do
      assert TreeDiff.diff_children([], []) == []
    end

    test "all adds when prev empty" do
      current = [{:label, [text: "a"]}]
      ops = TreeDiff.diff_children([], current)
      assert [{:add, 0, _}] = ops
    end
  end
end
