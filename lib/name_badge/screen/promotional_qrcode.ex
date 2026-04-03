defmodule NameBadge.Screen.PromotionalQRCode do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(%{qr_code: qr_code}) do
    case qr_code do
      nil ->
        """
        #align(center + horizon)[
            #text(font: \"New Amsterdam\", size: 24pt)[No QR code available]
        ]
        """

      qr ->
        """
        #align(center + horizon)[
            #image(height: 80%, format: "svg", bytes("#{qr}"))
            
            Scan to reach me !
        ]
        """
    end
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    qr_code =
      Application.get_env(:name_badge, :qr_link)
      |> qr_code_for_url()

    {:ok, assign(screen, qr_code: qr_code, button_hints: %{b: "Back to badge"})}
  end

  @impl NameBadge.Screen
  def handle_button(:button_2, :single_press, screen) do
    {:noreply, navigate(screen, :back)}
  end

  def handle_button(_, _, screen), do: {:noreply, screen}

  defp qr_code_for_url(nil), do: nil

  defp qr_code_for_url(url) do
    with {:ok, _code} = result <- QRCode.create(url),
         {:ok, qr_code_svg} <- QRCode.render(result) do
      qr_code_svg
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
    end
  end
end
