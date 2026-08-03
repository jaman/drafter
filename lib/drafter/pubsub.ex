defmodule Drafter.PubSub do
  @moduledoc false

  @pubsub_name Drafter.PubSub

  @doc """
  Subscribe the calling process to `topic`.

  `topic` is an atom or a string; an atom is converted to its name, so `:logs` and
  `"logs"` are the same topic. Broadcasts arrive as plain messages in the mailbox.
  """
  @spec subscribe(atom() | String.t()) :: :ok | {:error, term()}
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic_to_string(topic))
  end

  @doc "Unsubscribe the calling process from `topic`. Always returns `:ok`, even if it was not subscribed."
  @spec unsubscribe(atom() | String.t()) :: :ok
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, topic_to_string(topic))
  end

  @doc "Send `message` to every process subscribed to `topic`, including the caller if it is one."
  @spec broadcast(atom() | String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub_name, topic_to_string(topic), message)
  end

  @doc """
  Broadcast `{:file_content, path, content, language}` to `topic`.

  `language` is a syntax-highlighting language atom, or `nil` to let the receiver
  infer one from `path`.
  """
  @spec broadcast_file(atom() | String.t(), String.t(), String.t(), atom() | nil) ::
          :ok | {:error, term()}
  def broadcast_file(topic, path, content, language \\ nil) do
    broadcast(topic, {:file_content, path, content, language})
  end

  @doc "Broadcast the bare message `:clear` to `topic`."
  @spec broadcast_clear(atom() | String.t()) :: :ok | {:error, term()}
  def broadcast_clear(topic) do
    broadcast(topic, :clear)
  end

  defp topic_to_string(topic) when is_atom(topic), do: Atom.to_string(topic)
  defp topic_to_string(topic) when is_binary(topic), do: topic
end
