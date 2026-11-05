-- Your monitor rules. Required after dms.outputs, so these override it per output.
-- ICC is applied by Hyprland's colour management here; the profile has no vcgt,
-- so don't also select it in Dux's display settings.

hl.monitor({
  output = "DP-4",
  mode = "5120x1440@144",
  position = "0x0",
  scale = 1.25,
  bitdepth = 10,
  cm = "srgb",
  icc = "/home/void/repos/.display/msi_mpg491cqp.icm",
  vrr = 2,
})
