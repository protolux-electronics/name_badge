# Nerves Name Badge

This is the Nerves software for the Goatmire/NervesConf EU 2025 digital name
badge.

If you were at the event and have a device which you want to start building
custom screens for, please be aware of the following:

- A firmware update was pushed out during the last day of the event, which
  allows for ssh authentication via username/password. You can tell if you have
  the update by checking out the `Settings` screen, and verifying that one of
  the partitions contains firmware v0.2.0.
- If you do not have the firmware update, but would like to access the device
  via ssh, the original ssh key was published in the Goatmire discord at the end
  of the event. Use this key, along with the following or similar configuration
  in your `~/.ssh/config` file to access the board:

```
Host wisteria*.local
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  IdentityFile ~/.ssh/id_goatmire
```

- If you didn't get the update, you can also create a WiFi hotspot from your
  phone to allow the device to download the latest version of the software. The
  device knows how to connect to a hotspot with SSID `nervesconf` and password
  `nervesconf`. Wait for the device to download the update and reboot (this may
  take some time)
- Finally, you could also re-flash the board using the firmware file in the
  latest release of this repo. This is slightly more advanced - you will need to
  install `sunxi-tools` and download the flashing script from the
  [`usb_fel_loaders`](https://github.com/gworkman/usb_fel_loaders). Installation
  instructions for both are available in the README. Use the precompiled assets
  in the releases to save yourself a compilation step. Once you have the tools
  installed, you need to do the following:
  - Turn off the device, with the case open
  - Connect your computer via USB
  - Press the button labeled `FEL`
  - Run `./launch.sh trellis` from the `release` dir of the `usb_fel_loaders`
    assets
  - The board will reboot and appear as a USB media device (on Mac, your
    computer may say "Device was uninitialized". Just press "ignore").
  - Finally, run
    `NERVES_WIFI_SSID="..." NERVES_WIFI_PASSPHRASE="..." fwup name_badge.fw`,
    which will upload the firmware to the device and automatically reboot

## Connecting via SSH

The default hostname of the device is `wisteria.local`. If you see an SSH
username/password prompt, both values are `nerves`.

## Building the firmware

- `export MIX_TARGET=trellis`
- `mix deps.get`
- `mix firmware`
- Put the device in FEL mode, as described above
- `mix burn`

Afterwards, firmware can be uploaded over ssh via `mix upload`.

More docs coming soon. Thanks for joining Goatmire 2025!
