defmodule NameBadge.Screen.NameBadge do
  use NameBadge.Screen

  alias NameBadge.Socket

  require Logger

  def render(%{connected: false}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 16pt,
        text(size: 48pt, font: "New Amsterdam", "Not connected :(")
      )
    );
    """
  end

  def render(assigns) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 16pt,
        image(height: 80%, format: "svg", bytes("#{assigns.qr_code}")),
        v(8pt),
        text(size: 24pt, font: "New Amsterdam", "No configuration found"),
        text(size: 24pt, font: "New Amsterdam", "Scan QR code to set up"),
      )
    );
    """
  end

  def init(_args) do
    cond do
      Socket.connected?() ->
        token =
          :crypto.strong_rand_bytes(20)
          |> Base.url_encode64()

        Socket.join_config(token, %{first_name: "Gus", last_name: "Workman"})

        url = "https://#{base_url()}/device/#{token}/config"

        Logger.info("Generated QR code for: #{url}")

        {:ok, qr_code_svg} =
          url
          |> QRCode.create()
          |> QRCode.render()

        {:ok, %{qr_code: encode(qr_code_svg), token: token}}

      true ->
        {:ok, %{connected: false}}
    end
  end

  def handle_button(_, 0, screen) do
    Socket.leave_config(screen.assigns.token)

    {:render, navigate(screen, :back)}
  end

  def handle_button(_, _, screen) do
    {:norender, screen}
  end

  defp base_url(), do: Application.get_env(:name_badge, :base_url)

  defp encode(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
