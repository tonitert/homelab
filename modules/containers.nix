# Podman as the OCI container runtime. Service modules turn this on and add
# their containers under `virtualisation.oci-containers.containers`.
{ config, lib, ... }:
let
  cfg = config.homelab.containers;
in
{
  options.homelab.containers = {
    enable = lib.mkEnableOption "podman for OCI containers";
    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `podman auto-update` daily. Containers labelled
        `io.containers.autoupdate=registry` are re-pulled and restarted when
        their tag (e.g. `latest`) points to a new image.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
        flags = [ "--all" ];
      };
    };
    virtualisation.oci-containers.backend = "podman";

    # podman ships podman-auto-update.{service,timer}; this just enables the timer.
    systemd.timers.podman-auto-update.wantedBy = lib.mkIf cfg.autoUpdate [ "timers.target" ];

    # If a container fails to start (e.g. the image can't be pulled because
    # the internet isn't up yet after a power cut), retry every 30 s for as
    # long as it takes. Otherwise systemd gives up for good after 5 failed
    # starts within 10 s.
    systemd.services = lib.mapAttrs' (
      _: c:
      lib.nameValuePair c.serviceName {
        startLimitIntervalSec = lib.mkDefault 0;
        serviceConfig.RestartSec = lib.mkDefault "30s";
      }
    ) config.virtualisation.oci-containers.containers;
  };
}
