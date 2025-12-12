# Build Custom Firmware

This project uses Elixir version 1.18.3 and OTP 27.3.4. Please install these
versions before proceeding.

To build a firmware from source, you also need to
[install Nerves](https://hexdocs.pm/nerves/installation.html), following the
instructions for your machine.

Once everything is installed, in this root directory of the repo, run:

```sh
export MIX_TARGET=trellis
mix deps.get
mix firmware
```

To upload via the network, you can run `mix upload wisteria.local`. This
requires that either the device is already running a valid firmware, and is
accessible over your local network.

This means that it is connected to the same WiFi network, or that it is directly
connected to your computer via USB cable.

## Flashing via FEL

If the device is not running a valid firmware or is inaccessible via the
network, you may flash it via FEL mode as described in the
[Flashing via FEL](/guides/flashing-via-fel.md) guide.

After the device connects as a USB storage device, run `mix burn`
