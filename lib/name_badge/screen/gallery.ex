defmodule NameBadge.Screen.Gallery do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(%{image: png} = _assigns) do
    # this is a unique case. When you return png-encoded binaries,
    # the system knows that it is a PNG based on the header bytes.
    # You could abuse this in your own application, if desired
    png
  end

  @impl NameBadge.Screen
  def render(_assigns) do
    """
    #set text(size: 24pt)
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)


    = Gallery

    #text(size: 18pt)[
      This page will automatically refresh when it receives images from the server.

      #text(weight: 800)[IMPORTANT]: To exit the gallery, long press the B button.
    ]
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    # wait for a couple of seconds so the user can read the information
    Process.send_after(self(), :join, :timer.seconds(3))

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_info({:gallery_image, png}, screen) do
    {:noreply, assign(screen, image: png)}
  end

  def handle_info(:join, screen) do
    NameBadge.Gallery.subscribe_to_gallery()

    {:noreply, screen}
  end

  defp base_url(), do: Application.get_env(:name_badge, :base_url)
end
