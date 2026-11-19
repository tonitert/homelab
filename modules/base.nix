# Settings every homelab machine shares: admin user, SSH, networking, Nix.
{ config, lib, ... }:
let
  cfg = config.homelab;
in
{
  options.homelab = {
    adminUser = lib.mkOption {
      type = lib.types.str;
      description = "Login name of the administrator account (member of wheel).";
    };
    adminKeys = lib.mkOption {
      type = with lib.types; listOf str;
      description = "SSH public keys allowed to log in as the admin user (and as root on the installer).";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.adminKeys != [ ];
        message = "homelab.adminKeys must contain at least one SSH public key; SSH is key-only.";
      }
    ];

    users.users.${cfg.adminUser} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      openssh.authorizedKeys.keys = cfg.adminKeys;
    };
    # SSH is key-only, so sudo without a password keeps remote
    # `nixos-rebuild --sudo` deploys non-interactive. The console password
    # (set by the installer) is only for logging in locally.
    security.sudo.wheelNeedsPassword = false;

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    networking.networkmanager.enable = true; # ethernet via DHCP; Wi-Fi with `nmtui`
    networking.firewall.enable = true;
    # Reachable as <hostname>.local on the LAN.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    zramSwap.enable = true;
    time.timeZone = lib.mkDefault "Europe/Helsinki";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
    console.keyMap = lib.mkDefault "fi";

    nix = {
      channel.enable = false; # flakes only
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [ "@wheel" ]; # lets `nixos-rebuild --target-host` copy closures
        auto-optimise-store = true;
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };
  };
}
