# Tailscale: reach the machine from your own devices wherever they are,
# e.g. `ssh toni@blackout` over the tailnet.
#
# Log in once after install: `sudo tailscale up` prints a link to open in a
# browser. The login is kept in /var/lib/tailscale, so it survives reboots
# and rebuilds. Tailscale settings that should live in Git go in
# `services.tailscale.extraSetFlags` (e.g. [ "--ssh" ]).
{ config, lib, ... }:
let
  cfg = config.services.tailscale;
in
{
  options.homelab.tailscale.enable = lib.mkEnableOption "the Tailscale client";

  config = lib.mkIf config.homelab.tailscale.enable {
    services.tailscale = {
      enable = true;
      openFirewall = true; # UDP 41641, so peers can connect directly instead of through a relay
    };

    # tailscaled-set runs `tailscale set <extraSetFlags>` once and exits.
    # Staying "active" makes a rebuild with changed flags restart it, so the
    # change applies right away instead of at the next boot.
    systemd.services.tailscaled-set = lib.mkIf (cfg.extraSetFlags != [ ]) {
      serviceConfig.RemainAfterExit = true;
    };
  };
}
