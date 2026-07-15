defmodule NameBadge.Calibration do
  @moduledoc """
  Persisted 4-level grayscale calibration for the UC8276 panel.

  The panel renders exactly 4 levels: pure black and pure white are fixed
  anchors, and the two middle grays are the only thing tunable. This module
  stores where those two mids sit (as whiten-frame counts on the 150Hz scale)
  and pushes them to the chip via the eink runtime waveform-override API
  (`EInk.set_waveform/2`).

  The value survives reboots in `/data/display_calibration.json`; the EInk
  GenServer forgets the override on restart, so `apply_saved!/0` re-applies it
  at boot (called from `NameBadge.Application`).

  `EInk.set_waveform/2` only exists on the eink `waveform-override-api` branch
  (protolux-electronics/eink#12). Every hardware call is guarded, so this
  compiles on the host simulator and on an older eink pin — it just no-ops
  until that API is available.
  """

  require Logger

  # Fixed anchors — the calibrated baseline is `[0, 5, 10, 54]` on the 0..63
  # whiten-frame scale (black, dark mid, light mid, white).
  @black 0
  @white 54
  @default_dark 5
  @default_light 10

  @doc "Baseline mids the calibration ships with: `{dark, light}`."
  def defaults, do: {@default_dark, @default_light}

  @doc "Fixed black/white anchor counts the mids sit between."
  def anchors, do: {@black, @white}

  @doc """
  Load the persisted `{dark, light}` counts, falling back to `defaults/0`.

  ## Example

      Calibration.load()  # {5, 10}
  """
  def load do
    with {:ok, json} <- File.read(store_file()),
         %{"dark" => d, "light" => l} when is_integer(d) and is_integer(l) <- :json.decode(json) do
      clamp(d, l)
    else
      _ -> defaults()
    end
  rescue
    _ -> defaults()
  end

  @doc """
  Persist `{dark, light}` (clamped) to disk. Returns the clamped tuple.

  ## Example

      Calibration.save(3, 11)  # {3, 11}
  """
  def save(dark, light) do
    {dark, light} = clamp(dark, light)
    File.write(store_file(), :json.encode(%{"dark" => dark, "light" => light}))
    {dark, light}
  end

  @doc """
  Push `{dark, light}` to the panel for all later `mode: :grayscale` draws.

  Clamps to a valid, monotonic range and returns the applied tuple. Costs one
  panel re-init (~1s) on the *next* grayscale draw — the caller must trigger a
  redraw for the change to show.

  ## Example

      Calibration.set(4, 12)  # {4, 12}, override now live
  """
  def set(dark, light) do
    {dark, light} = clamp(dark, light)

    if eink_ready?() do
      try do
        lut = build_lut(dark, light)
        Kernel.apply(EInk, :set_waveform, [:grayscale, [lut: lut]])
      rescue
        e -> Logger.warning("Calibration.apply/2 failed: #{inspect(e)}")
      end
    else
      Logger.debug("Calibration.apply/2: EInk.set_waveform unavailable; skipping (host or old eink pin)")
    end

    {dark, light}
  end

  @doc """
  Re-apply the persisted calibration at boot, only if it differs from the
  baseline (baseline == packaged default LUT, so no override needed).
  """
  def apply_saved! do
    {dark, light} = load()

    # Baseline == the packaged default LUT, so an override is only needed when
    # the saved value has been moved off it.
    if {dark, light} != defaults() do
      set(dark, light)
    end

    :ok
  rescue
    _ -> :ok
  end

  @doc "Clamp to `0 ≤ dark ≤ light ≤ white`, each on the 0..63 count scale."
  def clamp(dark, light) do
    dark = dark |> min(@white) |> max(@black)
    light = light |> min(@white) |> max(dark)
    {dark, light}
  end

  # Build the 5 grayscale LUT registers from the two mids. Uses the library
  # builder on the new eink branch; guarded so it's only reached on target.
  defp build_lut(dark, light) do
    Kernel.apply(EInk.Driver.UC8276.Settings, :grayscale_lut, [[@black, dark, light, @white]])
  end

  defp eink_ready? do
    Code.ensure_loaded?(EInk) and function_exported?(EInk, :set_waveform, 2)
  end

  if Mix.target() == :host do
    defp store_file, do: Path.join(System.tmp_dir!(), "display_calibration.json")
  else
    defp store_file, do: "/data/display_calibration.json"
  end
end
