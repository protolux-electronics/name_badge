defmodule NameBadge.Screen.Settings do
  use NameBadge.Screen

  alias NameBadge.Battery
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

  def render(%{show_stats: true}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 16pt,
        text(size: 48pt, font: "New Amsterdam", "Stats for Nerds!!!")
      )
    );
    """
  end

  def render(assigns) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 12pt,
        image(height: 80%, format: "svg", bytes("#{assigns.qr_code}")),
        v(8pt),
        text(size: 24pt, font: "New Amsterdam", "Scan to modify settings"),
      )
    );
    """
  end

  def init(_args) do
    cond do
      Socket.connected?() ->
        token =
          :crypto.strong_rand_bytes(16)
          |> Base.encode16()

        Socket.join_config(token, %{})

        url = "https://#{base_url()}/device/#{token}/config"

        Logger.info("Generated QR code for: #{url}")

        {:ok, qr_code_svg} =
          url
          |> QRCode.create()
          |> QRCode.render()

        {:ok,
         %{
           qr_code: encode(qr_code_svg),
           token: token,
           show_stats: false,
           button_hints: %{a: "Stats for nerds", b: "Back"}
         }}

      true ->
        {:ok, %{connected: false}}
    end
  end

  def handle_button("BTN_1", 0, screen) do
    screen = assign(screen, :show_stats, not screen.assigns.show_stats)

    {:render, screen}
  end

  def handle_button("BTN_2", 0, screen) do
    if screen.assigns[:token], do: Socket.leave_config(screen.assigns.token)

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
