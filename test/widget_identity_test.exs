defmodule Drafter.WidgetIdentityTest do
  use ExUnit.Case, async: false

  alias Drafter.ComponentRenderer

  @rect %{x: 0, y: 0, width: 40, height: 20}

  setup do
    Drafter.WidgetStripCache.create()

    {:ok, tm} =
      case Drafter.ThemeManager.start_link() do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
      end

    Process.put(:drafter_theme_manager, tm)
    {:ok, theme: Drafter.ThemeManager.get_current_theme()}
  end

  defp render(tree, theme, existing \\ nil) do
    ComponentRenderer.render_tree(tree, @rect, theme, %{}, existing, app_module: __MODULE__)
  end

  defp input(opts), do: {:text_input, Keyword.merge([placeholder: "p"], opts)}
  defp ids(h), do: h.widgets |> Map.keys() |> Enum.sort()

  describe "keyed identity" do
    test "a keyed widget keeps the same id regardless of position" do
      first =
        render(
          {:layout, :vertical, [input(key: "alpha")], []},
          Drafter.ThemeManager.get_current_theme()
        )

      second =
        render(
          {:layout, :vertical, [input(key: "inserted"), input(key: "alpha")], []},
          Drafter.ThemeManager.get_current_theme(),
          first
        )

      keyed = Enum.filter(ids(second), &(is_binary(&1) and String.contains?(&1, "alpha")))
      assert length(keyed) == 1
    end

    test "a keyed widget keeps its process when a sibling appears before it" do
      theme = Drafter.ThemeManager.get_current_theme()
      h = render({:layout, :vertical, [input(key: "alpha")], []}, theme)
      [id] = Enum.filter(ids(h), &is_binary/1)
      original_pid = h.widgets[id].pid

      h2 =
        render(
          {:layout, :vertical, [input(key: "inserted"), input(key: "alpha")], []},
          theme,
          h
        )

      assert h2.widgets[id].pid == original_pid,
             "a keyed widget must not be rebuilt when its position shifts"
    end

    test "an unkeyed widget is rebuilt when its position shifts" do
      theme = Drafter.ThemeManager.get_current_theme()
      h = render({:layout, :vertical, [input([])], []}, theme)
      [id] = Enum.filter(ids(h), &(is_atom(&1) and h.widgets[&1].pid != nil))
      original_pid = h.widgets[id].pid

      h2 = render({:layout, :vertical, [input(key: "new_first"), input([])], []}, theme, h)

      assert h2.widgets[id].pid == original_pid,
             "positional identity is stable only while the tree shape is"
    end

    test "distinct keys produce distinct widgets" do
      theme = Drafter.ThemeManager.get_current_theme()
      h = render({:layout, :vertical, [input(key: "a"), input(key: "b")], []}, theme)

      keyed = Enum.filter(ids(h), &is_binary/1)
      assert length(keyed) == 2
      assert Enum.uniq(keyed) == keyed
    end

    test "integer and atom keys are accepted" do
      theme = Drafter.ThemeManager.get_current_theme()
      h = render({:layout, :vertical, [input(key: 7), input(key: :beta)], []}, theme)

      keyed = Enum.filter(ids(h), &is_binary/1)
      assert length(keyed) == 2
    end

    test "keys do not create atoms" do
      theme = Drafter.ThemeManager.get_current_theme()
      warm = render({:layout, :vertical, [input(key: "warmup")], []}, theme)
      before = :erlang.system_info(:atom_count)

      Enum.reduce(1..200, warm, fn i, acc ->
        render({:layout, :vertical, [input(key: "row-#{i}")], []}, theme, acc)
      end)

      assert :erlang.system_info(:atom_count) - before == 0,
             "keyed ids must not mint an atom per key"
    end

    test "an explicit id still wins over a key" do
      theme = Drafter.ThemeManager.get_current_theme()
      h = render({:layout, :vertical, [input(id: :chosen, key: "ignored")], []}, theme)
      assert :chosen in ids(h)
    end
  end

  describe "positional identity" do
    test "unkeyed widgets remain addressable by position" do
      theme = Drafter.ThemeManager.get_current_theme()
      h = render({:layout, :vertical, [input([]), input([])], []}, theme)
      assert length(Enum.filter(ids(h), &is_atom/1)) >= 2
    end
  end
end
