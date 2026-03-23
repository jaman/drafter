defmodule Drafter.Syntax.TreeSitterHighlighter do
  @moduledoc false

  @behaviour Drafter.Syntax.Highlighter

  alias Drafter.Syntax.TreeSitter

  @impl true
  @spec highlight(String.t(), atom()) :: [Drafter.Syntax.Highlighter.capture()]
  def highlight(source, language) do
    TreeSitter.highlight(source, language)
  end
end
