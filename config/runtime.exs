import Config

# Register the live system monitor TUI as a `nerves_ssh` subsystem so
# you can drop into a full-color dashboard from your laptop without
# disturbing the badge's e-ink screen:
#
#     ssh -t nerves@wisteria.local -s Elixir.NameBadge.ExRatatui.SystemMonitorTui
#
# Plain `ssh nerves@wisteria.local` still gives you the regular IEx
# prompt — the subsystem only kicks in when you pass `-s`.
#
# This config lives in `runtime.exs` on purpose: `ExRatatui.SSH.subsystem/1`
# is a normal function call, and on a fresh `MIX_TARGET=trellis mix
# compile` the compile-time config files (`config.exs`, `target.exs`)
# run before Mix has compiled deps for the target — `ExRatatui.SSH`
# isn't on the code path yet, so calling it there crashes with
# `module ExRatatui.SSH is not available`.
#
# `runtime.exs` is evaluated on device boot, after every beam file in
# the release is loaded but before the OTP application controller
# starts `:nerves_ssh`, so the config it writes is in place by the
# time the daemon reads it. Standard Elixir release pattern for any
# config that can't be a pure data literal.
#
# On host builds (`MIX_TARGET=host mix run`, tests, etc.) this file
# still runs but it's harmless: `:nerves_ssh` isn't a host dep, so no
# one ever reads the env key we're writing.
if Application.spec(:nerves_ssh) do
  config :nerves_ssh,
    subsystems: [
      :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
      ExRatatui.SSH.subsystem(NameBadge.ExRatatui.SystemMonitorTui)
    ]
end
