defmodule Drafter.Widget.Trait.PipelineTest do
  use ExUnit.Case, async: true

  alias Drafter.Widget.Trait.Pipeline

  defmodule PassTrait do
    @behaviour Drafter.Widget.Trait

    def name, do: :pass_trait
    def default_state, do: %{_pass_count: 0}
    def handles, do: [:keyboard]

    def handle_event(_event, trait_state, _ws) do
      {:pass, trait_state}
    end
  end

  defmodule CounterTrait do
    @behaviour Drafter.Widget.Trait

    def name, do: :counter
    def default_state, do: %{_counter: 0}
    def handles, do: [:keyboard]

    def handle_event({:key, :up}, trait_state, _ws) do
      {:ok, %{trait_state | _counter: trait_state._counter + 1}}
    end

    def handle_event(_event, trait_state, _ws) do
      {:pass, trait_state}
    end
  end

  defmodule ConsumerTrait do
    @behaviour Drafter.Widget.Trait

    def name, do: :consumer
    def default_state, do: %{_consumed: false}
    def handles, do: [:keyboard]

    def handle_event({:key, :up}, trait_state, _ws) do
      {:consume, %{trait_state | _consumed: true}}
    end

    def handle_event(_event, trait_state, _ws) do
      {:pass, trait_state}
    end
  end

  describe "run_traits/3" do
    test "pass does not modify state" do
      state = %{_pass_count: 0}
      {new_state, consumed?} = Pipeline.run_traits([PassTrait], {:key, :up}, state)

      assert new_state._pass_count == 0
      refute consumed?
    end

    test "ok updates trait state" do
      state = %{_counter: 0}
      {new_state, consumed?} = Pipeline.run_traits([CounterTrait], {:key, :up}, state)

      assert new_state._counter == 1
      refute consumed?
    end

    test "consume stops pipeline and sets consumed flag" do
      state = %{_consumed: false, _counter: 0}
      {new_state, consumed?} = Pipeline.run_traits([ConsumerTrait, CounterTrait], {:key, :up}, state)

      assert new_state._consumed == true
      assert new_state._counter == 0
      assert consumed?
    end

    test "traits process in declaration order" do
      state = %{_counter: 0, _consumed: false}
      {new_state, consumed?} = Pipeline.run_traits([CounterTrait, ConsumerTrait], {:key, :up}, state)

      assert new_state._counter == 1
      assert new_state._consumed == true
      assert consumed?
    end

    test "events not handled by any trait pass through" do
      state = %{_counter: 0}
      {new_state, consumed?} = Pipeline.run_traits([CounterTrait], {:key, :down}, state)

      assert new_state._counter == 0
      refute consumed?
    end
  end

  describe "extract_trait_state/2" do
    test "extracts only trait-owned keys" do
      widget_state = %{focused: true, _counter: 5, items: ["a", "b"]}
      trait_state = Pipeline.extract_trait_state(widget_state, CounterTrait)

      assert trait_state == %{_counter: 5}
    end
  end

  describe "merge_trait_state/3" do
    test "merges trait state back into widget state" do
      widget_state = %{focused: true, _counter: 0, items: ["a"]}
      new_trait_state = %{_counter: 10}

      result = Pipeline.merge_trait_state(widget_state, CounterTrait, new_trait_state)

      assert result._counter == 10
      assert result.focused == true
      assert result.items == ["a"]
    end
  end

  describe "apply_pre_render/3" do
    test "returns unchanged state and rect with no traits" do
      state = %{foo: 1}
      rect = %{x: 0, y: 0, width: 80, height: 40}

      {new_state, new_rect} = Pipeline.apply_pre_render([], state, rect)

      assert new_state == state
      assert new_rect == rect
    end
  end

  describe "apply_post_render/4" do
    test "returns unchanged strips with no traits" do
      strips = [:strip1, :strip2]
      result = Pipeline.apply_post_render([], strips, %{}, %{})
      assert result == strips
    end
  end
end
