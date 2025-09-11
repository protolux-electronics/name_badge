defmodule NameBadge.Screen.NameBadge do
  use NameBadge.Screen

  alias NameBadge.Socket

  require Logger

  @impl true
  def render(%{connected: false}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 16pt,
        text(size: 48pt, font: "New Amsterdam", "Not connected :(")
      )
    );
    """
  end

  def render(%{config: nil, qr_code: qr_code}) do
    """
    #place(center + horizon,
      stack(dir: ttb, spacing: 12pt,
        image(height: 80%, format: "svg", bytes("#{qr_code}")),
        v(8pt),
        text(size: 24pt, font: "New Amsterdam", "No configuration found"),
        text(size: 24pt, font: "New Amsterdam", "Scan to set up"),
      )
    );
    """
  end

  def render(%{config: config}) do
    greeting_element =
      case config["greeting"] do
        nil ->
          ""

        "" ->
          ""

        greeting when is_binary(greeting) ->
          "text(font: \"New Amsterdam\", size: #{config["greeting_size"]}pt)[#{greeting}],"
      end

    company_element =
      case config["company"] do
        nil ->
          ""

        "" ->
          ""

        company when is_binary(company) ->
          "text(font: \"New Amsterdam\", size: #{config["company_size"]}pt)[#{company}],"
      end

    """
    #place(center + horizon,
      stack(dir: ttb, spacing: #{config["spacing"]}pt,

        #{greeting_element}
        text(font: "New Amsterdam", size: #{config["name_size"]}pt, "#{config["first_name"]} #{config["last_name"]}"),
        #{company_element}
      )
    );
    """
  end

  @impl true
  def init(_args, screen) do
    config = NameBadge.Config.load_config()

    screen =
      cond do
        not is_nil(config) ->
          assign(screen, :config, config)

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

          screen
          |> assign(:qr_code, encode(qr_code_svg))
          |> assign(:token, token)
          |> assign(:config, nil)

        true ->
          assign(screen, :connected, false)
      end

    {:ok, assign(screen, :button_hints, %{a: "Next", b: "Back"})}
  end

  @impl true
  def handle_button(_, 0, screen) do
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
