defmodule NameBadge.PubSub do
  @moduledoc """
  Helpers functions for broadcasting and subscribing to PubSub messages.
  """

  @pub_sub_name NameBadge.PubSub.Internal

  def broadcast!(topic, message) do
    Phoenix.PubSub.broadcast!(@pub_sub_name, topic, message)
  end

  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pub_sub_name, topic)
  end

  def name(), do: @pub_sub_name
end
