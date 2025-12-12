# Nerves Name Badge

This is the Nerves software for the Goatmire EU 2025 digital name badge.

<img src="guides/assets/outside.jpg" width="600">
<img src="guides/assets/inside.jpg" width="600">

My conference talk about the badges is available on YouTube:

[<img src="https://img.youtube.com/vi/VFmlNZ_BQHQ/0.jpg" width="600">](https://youtu.be/VFmlNZ_BQHQ?si=QmM__-oR1jTcWF8w)

## Getting Started

If you already have a badge, you can get started by following these instructions
to load a firmware on your device. For those without the hardware, you can still
join in on the fun by using the simulator to create new screens. See more
information about the simulator below.

### Uploading pre-built firmware

If you have a device, it should already have usable firmware on it. That means,
you should be able to connect to it via SSH over a USB connection.

To test if this is the case, do the following:

1. Plug a USB-C cable from your computer to the badge
2. Turn off the device via the slide switch
3. Ensure the red or green LED immediately to the left of the USB port is on
4. Turn on the device via the slide switch
5. Wait for the device to boot
6. On your machine, run `ssh wisteria.local`
   - The default SSH password is `nerves`
   - If you are having trouble connecting to the device, please check your
     network settings and verify that a USB Ethernet device is attached to your
     machine.
   - If the issue still persists, reboot the device

Once you are connected, you can upload the latest firmware `.fw` file from the
releases section of this page. To upload, run:

`cat path/to/release.fw | ssh -s wisteria.local fwup`

The device will automatically reboot after uploading the firmware file

## Advanced

The getting started guide above shows how to load pre-built firmware on the
device. For advanced topics, please see the guides below:

- [Flashing a firmware file via FEL](guides/flashing-via-fel.md)
- [Build custom firmwware](guides/flashing-via-fel.md)
- [Create your first screen](guides/custom-screen.md)

## Simulator

Thanks to Matthias Männich for contributing the simulator! Here's what it looks
like:

![Simulator gif](guides/assets/simulator.gif)

To run the simulator, use the following command:

```bash
MIX_TARGET=host iex -S mix
```

This will start a Phoenix LiveView on `localhost:4000`. It should automatically
open your browser page on launch.

> [!TIP]
> When changing code while using the simulator, you can type `recompile` at the
> IEx prompt. The running code will be updated (you may need to navigate to a
> different screen or refresh the browser page to see the changes).

## Hardware Availability

The hardware was custom-made for Goatmire 2025, and there was only a limited
supply of devices. If you have an interest in using these devices for some other
event, please get in touch - I would consider making additional batches for the
right event.

For individuals, I am working on a new revision of the hardware design with some
nice upgrades - a 5.8" display, low power mode, additional sensors, and more.
Stay tuned for updates!

## Acknowledgments

Special thanks to Lars Wikman for encouraging this crazy idea at Goatmire 2025,
finding a sponsor to cover the cost of the hardware, brainstorming badge
features with me, and so much more.

Another huge shout out to Frank Hunleth, Benjamin Milde, and Flora and Tom
Petterson for helping me assemble the badges at midnight, 8 hours before the
conference started.

## Protolux Electronics

This is a project by [Protolux Electronics](https://protolux.io), the small
Nerves-focused consultancy that I run. We do custom hardware and software for
IoT, industrial automation, and more. If you have a project in mind, let's get
in touch!
