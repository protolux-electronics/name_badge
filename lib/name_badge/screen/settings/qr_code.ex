defmodule NameBadge.Screen.Settings.QrCode do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(%{connected?: true} = assigns) do
    """
    #align(center + horizon)[
        #image(height: 80%, format: "svg", bytes("#{assigns.qr_code}"))
        
        Scan to configure device settings
    ]
    """
  end

  @impl NameBadge.Screen
  def render(_assigns) do
    """
    #align(center + horizon)[
      Unable to connect to server :(

      Please check device WiFi settings
    ]
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    token = generate_token()
    qr_code = qr_code_for_token(token)
    connected = NameBadge.Socket.connected?()

    if connected do
      current_config = NameBadge.Config.load_config()
      NameBadge.Socket.join_config(token, current_config)
    else
      NervesTime.restart_ntpd()
    end

    screen = assign(screen, qr_code: qr_code, token: token, connected?: connected)

    {:ok, screen}
  end

  @impl NameBadge.Screen
  def handle_button(_which_button, _press_type, screen) do
    {:noreply, screen}
  end

  @impl NameBadge.Screen
  def terminate(_reason, screen) do
    NameBadge.Socket.leave_config(screen.assigns.token)

    screen
  end

  defp qr_code_for_token(token) do
    url = "https://#{base_url()}/device/#{token}/config"

    {:ok, qr_code_svg} =
      url
      |> QRCode.create()
      |> QRCode.render()

    qr_code_svg
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp base_url(), do: Application.get_env(:name_badge, :base_url)

  defp generate_token do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16()
  end
end
