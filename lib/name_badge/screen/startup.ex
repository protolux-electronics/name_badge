defmodule NameBadge.Screen.Startup do
  use NameBadge.Screen

  @startup_duration :timer.seconds(5)

  def mount(_params, screen) do
    Process.send_after(self(), :done, @startup_duration)

    {:ok, screen}
  end

  def render(_assigns) do
    """
    #set page(width: 400pt, height: 300pt)
    #place(center + horizon, image("images/logos.svg", width: 196pt))
    """
  end

  def handle_info(:done, screen) do
    NameBadge.Device.navigate(NameBadge.Screen.TopLevel, %{})
    {:noreply, screen}
  end
end
