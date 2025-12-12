# Flashing firmware images via FEL

FEL mode is the USB bootloader programmed into the ROM of the T113-S4 chip. You
must have the `sunxi-tools` package installed to successfully program flash the
board while in FEL mode. See the dependency installation below for instructions.

This process is required for virgin or corrupted boards. Under normal
circumstances, you should use the normal Nerves firmware upgrade tooling.

## Dependencies

The following are required:

- [`fwup`](https://github.com/fwup-home/fwup). If you have Nerves already
  installed, you likely already have this one. The recommended installation path
  is via `asdf` or `mise`. It is also available in HomeBrew.
- [`sunxi-tools`](https://github.com/linux-sunxi/sunxi-tools). Required for
  flashing via FEL mode. Summarized installation instructions:

  - Ubuntu:
    ```sh
    sudo apt install sunxi-tools
    ```
  - MacOS:
    ```sh
    brew install libusb dtc

    git clone https://github.com/linux-sunxi/sunxi-tools
    CFLAGS="-I$(brew --prefix dtc)/include" LDFLAGS="-L$(brew --prefix dtc)/lib" make -C sunxi-tools
    ```

    You need to add the resulting binaries to your `PATH`. Most important is the
    `sunxi-fel` binary.

## Entering FEL mode

To flash a firmware image to a virgin or corrupted board (one where the flash
storage is empty), you need to put the board in FEL mode.

1. Open your name badge, connect a USB cable to your computer
2. On the right side, press and hold the FEL button
3. Press and release the RESET button (to the left of FEL button). This must be
   done while holding the FEL button!
4. Release the FEL button
5. Your badge should now be in FEL mode

## USB FEL loaders

To flash a firmware, there is a two-step process. First, we flash a small binary
to RAM which initializes USB and the onboard flash storage. The board will show
up as an external storage device, exactly like a micro SD card. The scripts to
flash this binary are in the
[`usb_fel_loaders`](https://github.com/gworkman/usb_fel_loaders) project. Do the
following:

1. Download the
   [latest release](https://github.com/gworkman/usb_fel_loaders/releases/latest)
2. Unzip the archive
3. `cd` into the extracted archive
4. Run `./launch.sh trellis`

The device will reboot as a USB storage device. If you are on MacOS, you may get
a warning that says the storage device was not initialized. Press "ignore".

## Flash firmware

Once your device shows up as a USB flash storage device, you can use `fwup` to
flash the firmware file.

```sh
fwup path/to/firmware.fw
```

Alternatively, if you customize the firmware, you can flash it using standard
Nerves tooling:

```sh
mix firmware
mix burn
```

More information is available in the
[Build Custom Firmware](/guides/build-custom-firmware.md) guide
