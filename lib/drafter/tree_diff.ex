defmodule Drafter.TreeDiff do
  @moduledoc """
  Component tree fingerprinting and diffing for render optimization.

  Produces structural fingerprints of component trees so the renderer
  can skip unchanged subtrees across frames.
  """

  @spec fingerprint(term()) :: non_neg_integer()
  def fingerprint({tag, opts}) when is_atom(tag) do
    :erlang.phash2({tag, Keyword.get(opts, :id), fingerprint_opts(opts)})
  end

  def fingerprint({tag, opts, children}) when is_atom(tag) and is_list(children) do
    child_fps = Enum.map(children, &fingerprint/1)
    :erlang.phash2({tag, Keyword.get(opts, :id), fingerprint_opts(opts), child_fps})
  end

  def fingerprint(list) when is_list(list) do
    :erlang.phash2(Enum.map(list, &fingerprint/1))
  end

  def fingerprint(other), do: :erlang.phash2(other)

  @spec diff_children([term()], [term()]) :: [{:keep | :add | :remove | :update, non_neg_integer(), term()}]
  def diff_children(prev, current) do
    prev_fps = Enum.map(prev, &{fingerprint(&1), &1})
    prev_fp_set = MapSet.new(prev_fps, fn {fp, _} -> fp end)
    curr_fps = Enum.map(current, &{fingerprint(&1), &1})
    curr_fp_set = MapSet.new(curr_fps, fn {fp, _} -> fp end)

    current_ops =
      curr_fps
      |> Enum.with_index()
      |> Enum.map(fn {{fp, node}, idx} ->
        if MapSet.member?(prev_fp_set, fp) do
          {:keep, idx, node}
        else
          {:add, idx, node}
        end
      end)

    remove_ops =
      prev_fps
      |> Enum.with_index()
      |> Enum.reject(fn {{fp, _}, _} -> MapSet.member?(curr_fp_set, fp) end)
      |> Enum.map(fn {{_, node}, idx} -> {:remove, idx, node} end)

    current_ops ++ remove_ops
  end

  defp fingerprint_opts(opts) do
    opts
    |> Keyword.drop([:id])
    |> Enum.sort()
    |> :erlang.phash2()
  end
end
