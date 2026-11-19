# Public ingress through a locally-managed Cloudflare Tunnel. No inbound
# ports are opened; services add `hostname -> origin` pairs to
# `homelab.tunnel.ingress` and they become reachable on those hostnames.
#
# One-time setup (on any machine with cloudflared logged in to your account):
#   cloudflared tunnel login
#   cloudflared tunnel create blackout            # prints the tunnel UUID, writes ~/.cloudflared/<UUID>.json
#   cloudflared tunnel route dns blackout api.blackout.beer
# then set `homelab.tunnel.id = "<UUID>"` and copy the JSON to `credentialsFile`
# on the server. The tunnel starts as soon as that file exists.
{ config, lib, ... }:
let
  cfg = config.homelab.tunnel;
  unit = "cloudflared-tunnel-${cfg.id}";
in
{
  options.homelab.tunnel = {
    id = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "6ff42ae2-765d-4adf-8112-31c55c1551ef";
      description = "UUID of the Cloudflare Tunnel. The tunnel is disabled while this is null.";
    };
    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/secrets/cloudflared-tunnel.json";
      description = ''
        Tunnel credentials JSON from `cloudflared tunnel create`. Kept out of the
        Nix store on purpose: copy it to the server by hand.
      '';
    };
    ingress = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
      example = {
        "api.example.com" = "http://127.0.0.1:3001";
      };
      description = "Public hostname -> origin service. Each hostname also needs a `cloudflared tunnel route dns`.";
    };
  };

  config = lib.mkIf (cfg.id != null) {
    services.cloudflared = {
      enable = true;
      tunnels.${cfg.id} = {
        inherit (cfg) credentialsFile ingress;
        default = "http_status:404";
      };
    };

    systemd.tmpfiles.rules = [ "d /var/lib/secrets 0700 root root -" ];

    # Don't crash-loop before the credentials have been copied over ...
    systemd.services.${unit}.unitConfig.ConditionPathExists = cfg.credentialsFile;
    # ... and start the tunnel as soon as they appear.
    systemd.paths."${unit}-credentials" = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = cfg.credentialsFile;
        Unit = "${unit}.service";
      };
    };
  };
}
