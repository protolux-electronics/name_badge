defmodule NameBadge.Battery do
  def voltage() do
    adc_raw =
      "/sys/bus/iio/devices/iio:device0/in_voltage0_raw"
      |> File.read!()
      |> String.trim()
      |> String.to_integer()

    # adc_raw / MAX_ADC_VALUE * ADC_REFERENCE_VOLTAGE * VOLTAGE_DIVIDER
    # On the PCB, the voltage divider is 453k and 51k resistors
    # So the value for the voltage divider is (453 + 51) / 51 = 9.8823529412
    # (the units cancel in this equation)

    adc_raw / 4095.0 * 1.8 * 9.8823529412
  end

  def charging?() do
    # consider the device charging when input voltage is 4.5V or
    # greater (as required by USB spec)
    voltage() > 4.5
  end
end
