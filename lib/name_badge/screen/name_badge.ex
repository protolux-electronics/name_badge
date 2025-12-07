defmodule NameBadge.Screen.NameBadge do
  use NameBadge.Screen

  require Logger

  @impl NameBadge.Screen
  def render(%{valid?: false}) do
    """
    #show heading: set text(font: "Silkscreen", size: 36pt, tracking: -4pt)

    = Error 

    Your name badge is not configured. Please connect to WiFi, then personalize
    your device via QR code.
    """
  end

  def render(%{config: config}) do
    Logger.info("name badge config is: #{inspect(config)}")

    greeting_element =
      case config["greeting"] do
        greeting when greeting == "" or is_nil(greeting) ->
          ""

        greeting when is_binary(greeting) ->
          "text(font: \"New Amsterdam\", size: #{config["greeting_size"] || 24}pt)[#{greeting}],"
      end

    company_element =
      case config["company"] do
        company when company == "" or is_nil(company) ->
          ""

        company when is_binary(company) ->
          "text(font: \"New Amsterdam\", size: #{config["company_size"] || 24}pt)[#{company}],"
      end

    """
    #place(center + horizon,
      stack(dir: ttb, spacing: #{config["spacing"] || 8}pt,

        #{greeting_element}
        text(font: "New Amsterdam", size: #{config["name_size"] || 36}pt, "#{config["first_name"]} #{config["last_name"]}"),
        #{company_element}
      )
    );
    """
  end

  @impl NameBadge.Screen
  def mount(_args, screen) do
    config = NameBadge.Config.load_config()

    case config do
      %{"first_name" => _first_name, "last_name" => _last_name} ->
        {:ok, assign(screen, config: config, valid?: true)}

      _config ->
        {:ok, assign(screen, valid?: false, button_hints: %{a: "Set up WiFi", b: "View QR code"})}
    end
  end

  @impl NameBadge.Screen
  def handle_button(:button_1, :single_press, screen) do
    {:noreply, navigate(screen, NameBadge.Screen.Settings.WiFi)}
  end

  def handle_button(:button_2, :single_press, screen) do
    {:noreply, navigate(screen, NameBadge.Screen.Settings.QrCode)}
  end

  def handle_button(_, _, screen), do: {:noreply, screen}
end
