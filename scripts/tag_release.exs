#!/usr/bin/env elixir

# Reads the version from mix.exs and, if the matching `vX.Y.Z` tag does not
# already exist, creates an annotated tag on HEAD and pushes it to origin.
#
# Idempotent: re-running when the tag already exists is a no-op. Refuses to run
# if the working-copy version is not the one committed at HEAD, so the tag can
# never point at a commit that lacks that version.
#
#   elixir scripts/tag_release.exs
#   ./scripts/tag_release.exs       # (it is executable)

defmodule TagRelease do
  def run do
    root = "rev-parse" |> git!(["--show-toplevel"]) |> String.trim()
    mix_exs = Path.join(root, "mix.exs")

    working = mix_exs |> File.read!() |> version_in()
    committed = "show" |> git!(["HEAD:mix.exs"]) |> version_in()
    tag = "v" <> committed

    cond do
      readme_stale?(root, committed) ->
        abort("""
        README.md does not name the requirement #{inspect(committed)} implies.
        Run `mix drafter.readme`, commit the change, then re-run.
        """)

      working != committed ->
        abort("""
        mix.exs version #{inspect(working)} is not committed yet (HEAD has #{inspect(committed)}).
        Commit the version bump first, then re-run.
        """)

      tag_exists?(tag) ->
        IO.puts("#{tag} already exists — nothing to tag.")

      true ->
        git!("tag", ["-a", tag, "-m", "Release #{committed}"])
        git!("push", ["origin", tag])
        IO.puts("Tagged HEAD as #{tag} and pushed to origin.")
    end
  end

  defp version_in(contents) do
    case Regex.run(~r/version:\s*"([^"]+)"/, contents) do
      [_, v] -> v
      _ -> abort(~s(no `version: "..."` found in mix.exs))
    end
  end

  defp readme_stale?(root, version) do
    %Version{major: major, minor: minor} = Version.parse!(version)
    expected = "~> #{major}.#{minor}"

    readme = root |> Path.join("README.md") |> File.read!()

    case Regex.run(~r/\{:drafter,\s*"([^"]+)"\}/, readme) do
      [_, ^expected] -> false
      _ -> true
    end
  end

  defp tag_exists?(tag), do: "tag" |> git!(["--list", tag]) |> String.trim() != ""

  defp git!(subcommand, args \\ []) do
    case System.cmd("git", [subcommand | args], stderr_to_stdout: true) do
      {out, 0} -> out
      {out, code} -> abort("`git #{subcommand} #{Enum.join(args, " ")}` failed (exit #{code}):\n#{out}")
    end
  end

  defp abort(msg) do
    IO.puts(:stderr, "tag_release: " <> msg)
    System.halt(1)
  end
end

TagRelease.run()
