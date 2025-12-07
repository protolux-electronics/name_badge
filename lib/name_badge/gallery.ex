defmodule NameBadge.Gallery do
  require Logger

  def push_gallery_image(url) do
    {:ok, %{body: png}} = Req.get(url)

    Registry.dispatch(NameBadge.Registry, :gallery, fn pids ->
      for {pid, _value} <- pids, do: send(pid, {:gallery_image, png})
    end)

    :ok
  end

  def subscribe_to_gallery() do
    NameBadge.Socket.join_gallery()
    Registry.register(NameBadge.Registry, :gallery, nil)
  end

  def unsubscribe_to_gallery() do
    NameBadge.Socket.leave_gallery()
    Registry.unregister(NameBadge.Registry, :gallery)
  end
end
