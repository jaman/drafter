defmodule Drafter.PubSub do
  @moduledoc false

  @pubsub_name Drafter.PubSub

  @doc """
  Subscribe the current process to a topic.
  """
  @spec subscribe(atom() | String.t()) :: :ok | {:error, term()}
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic_to_string(topic))
  end

  @doc """
  Unsubscribe the current process from a topic.
  """
  @spec unsubscribe(atom() | String.t()) :: :ok
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, topic_to_string(topic))
  end

  @doc """
  Broadcast a message to all subscribers of a topic.
  """
  @spec broadcast(atom() | String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub_name, topic_to_string(topic), message)
  end

  @doc """
  Broadcast file content to a topic (convenience function for code viewers).
  """
  @spec broadcast_file(atom() | String.t(), String.t(), String.t(), atom() | nil) ::
          :ok | {:error, term()}
  def broadcast_file(topic, path, content, language \\ nil) do
    broadcast(topic, {:file_content, path, content, language})
  end

  @doc """
  Broadcast a clear/reset message to a topic.
  """
  @spec broadcast_clear(atom() | String.t()) :: :ok | {:error, term()}
  def broadcast_clear(topic) do
    broadcast(topic, :clear)
  end

  defp topic_to_string(topic) when is_atom(topic), do: Atom.to_string(topic)
  defp topic_to_string(topic) when is_binary(topic), do: topic
end
