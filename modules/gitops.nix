# Pull-based deploys: the machine follows its configuration on GitHub.
#
# Every 5 minutes `nixos-upgrade.service` asks GitHub for the newest commit
# of `homelab.gitops.flake`. If the machine isn't already running that
# commit, it runs `nixos-rebuild switch --flake <flake>#<hostname>`. The
# commit's flake.lock pins nixpkgs, so the machine only gets what you pushed.
#
#   systemctl list-timers nixos-upgrade    when the next check runs
#   journalctl -u nixos-upgrade            what the checks and rebuilds did
#   nixos-version --configuration-revision the commit that is running now
#   sudo systemctl start nixos-upgrade     check right now
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.gitops;

  # ExecCondition of nixos-upgrade.service. Exit 0: there is a newer commit,
  # go ahead and rebuild. Exit 1: already running the newest commit, skip
  # (not a failure). Exit 255: GitHub couldn't be asked, the unit fails.
  upgradeNeeded = pkgs.writeShellApplication {
    name = "nixos-upgrade-needed";
    runtimeInputs = [
      config.nix.package
      pkgs.jq
    ];
    runtimeEnv = {
      FLAKE = cfg.flake;
      # The commit this system was built from (system.configurationRevision,
      # set in flake.nix); "<commit>-dirty" or empty if it was built from
      # uncommitted changes.
      RUNNING = toString config.system.configurationRevision;
    };
    text = ''
      if ! latest=$(nix --extra-experimental-features 'nix-command flakes' \
        flake metadata --refresh --json "$FLAKE" | jq -er .revision); then
        echo "could not get the newest commit of $FLAKE" >&2
        exit 255
      fi
      if [ "$latest" = "$RUNNING" ]; then
        echo "already running the newest commit of $FLAKE ($latest)"
        exit 1
      fi
      echo "updating to $FLAKE at $latest (running: ''${RUNNING:-unknown})"
    '';
  };
in
{
  options.homelab.gitops.flake = lib.mkOption {
    type = with lib.types; nullOr str;
    default = null;
    example = "github:tonitert/homelab";
    description = ''
      Flake (without `#host`) the machine keeps itself in sync with; it
      builds `nixosConfigurations.<hostname>` from it. Follows the default
      branch; append `/<branch>` to follow another one. null disables
      pulling; deploy with `nixos-rebuild --target-host` instead.
    '';
  };

  config = lib.mkIf (cfg.flake != null) {
    system.autoUpgrade = {
      enable = true;
      flake = "${cfg.flake}#${config.networking.hostName}"; # also adds --refresh
      upgrade = false; # --upgrade is for channels
      dates = lib.mkDefault "*:0/5";
    };
    systemd.services.nixos-upgrade.serviceConfig.ExecCondition = lib.getExe upgradeNeeded;
  };
}
