defmodule NameBadge.Screen.PromotionalQRCode do
  use NameBadge.Screen

  @impl NameBadge.Screen
  def render(%{qr_code: qr_code}) do
    qr_element =
      case qr_code do
        qr when not is_nil(qr_code) ->
          """
          #align(center + horizon)[
              #image(height: 80%, format: "svg", bytes("#{qr_code}"))
              
              Scan to reach me !
          ]
          """

        _ ->
          """
          #align(center + horizon)[
              #text(font: \"New Amsterdam\", size: 24pt)[No QR code available]
          ]
          """
      end
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    qr_link = Application.get_env(:name_badge, :qr_link, "https://nervesmeetup.eu")
    qr_code = qr_code_for_url(String.trim(qr_link))

    {:ok, assign(screen, qr_code: qr_code, button_hints: %{b: "Back to badge"})}
  end

  @impl NameBadge.Screen
  def handle_button(:button_2, :single_press, screen) do
    {:noreply, navigate(screen, :back)}
  end

  def handle_button(_, _, screen), do: {:noreply, screen}

  defp qr_code_for_url(url) do
    with {:ok, _code} = result <- QRCode.create(url),
         {:ok, qr_code_svg} <- QRCode.render(result) do
      qr_code_svg
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
    else
      _ -> nil
    end
  end
end
