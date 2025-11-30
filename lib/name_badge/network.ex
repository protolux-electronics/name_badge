defmodule NameBadge.Network do
  if Mix.target() == :host do
    def subscribe(_wlan_property) do
      :noop
    end
  else
    def subscribe(wlan_property) do
      VintageNet.subscribe(wlan_property)
    end
  end

  if Mix.target() == :host do
    def connected?(_wlan_property) do
      :noop
    end
  else
    def connected?(wlan_property) do
      VintageNet.get(wlan_property) == :internet
    end
  end

  if Mix.target() == :host do
    def current_ap() do
      "MOCKED"
    end
  else
    def current_ap() do
      case VintageNet.get(["interface", "wlan0", "wifi", "current_ap"]) do
        %{ssid: ssid} -> ssid
        _ -> nil
      end
    end
  end

  if Mix.target() == :host do
    def wlan_ip() do
      "MOCKED"
    end
  else
    def current_ap() do
      case VintageNet.get(["interface", "wlan0", "addresses"]) do
        addrs when is_list(addrs) ->
          case Enum.find(addrs, &(&1.family == :inet)) do
            %{address: {a1, a2, a3, a4}} ->
              "#{a1}.#{a2}.#{a3}.#{a4}"

            _other ->
              "Not connected"
          end

        _ ->
          "Not connected"
      end
    end
  end

  if Mix.target() == :host do
    def usb_ip() do
      "MOCKED"
    end
  else
    def usb_ip() do
      case VintageNet.get(["interface", "usb0", "addresses"]) do
        addrs when is_list(addrs) ->
          case Enum.find(addrs, &(&1.family == :inet)) do
            %{address: {a1, a2, a3, a4}} ->
              "#{a1}.#{a2}.#{a3}.#{a4}"

            _other ->
              "Not connected"
          end

        _ ->
          "Not connected"
      end
    end
  end
end
