# gorilla-blackout multiplayer backend (Fastify + Socket.IO, in-memory lobbies).
# The static frontend is served by Cloudflare Pages on blackout.beer and talks
# to this backend at https://<hostname> through the Cloudflare Tunnel.
#
# Template for new services: copy this file, run the app as an
# oci-container bound to 127.0.0.1, add a `homelab.tunnel.ingress` entry,
# import it in ../default.nix and enable it in the host file.
{ config, lib, ... }:
let
  cfg = config.homelab.services.gorilla-blackout;
in
{
  options.homelab.services.gorilla-blackout = {
    enable = lib.mkEnableOption "the gorilla-blackout multiplayer backend";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/tonitert/gorilla-blackout-backend:latest";
      description = "Backend image, published by the repo's publish-backend-image workflow.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Host port the backend listens on (127.0.0.1 only).";
    };
    hostname = lib.mkOption {
      type = with lib.types; nullOr str;
      default = "api.blackout.beer";
      description = ''
        Public hostname routed to the backend through the Cloudflare Tunnel.
        Must match the frontend's backend URL (VITE_PUBLIC_BACKEND_URL,
        default https://api.blackout.beer). null = not exposed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    homelab.containers.enable = true;

    virtualisation.oci-containers.containers.gorilla-blackout-backend = {
      inherit (cfg) image;
      ports = [ "127.0.0.1:${toString cfg.port}:3001" ];
      environment.PORT = "3001";
      # Run node directly behind a tiny init so SIGTERM stops it promptly
      # (the image's default is `pnpm start`).
      cmd = [
        "node"
        "dist/index.js"
      ];
      extraOptions = [ "--init" ];
      labels."io.containers.autoupdate" = "registry";
    };

    homelab.tunnel.ingress = lib.mkIf (cfg.hostname != null) {
      ${cfg.hostname} = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
