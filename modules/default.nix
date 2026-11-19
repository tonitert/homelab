# Every homelab module. Importing them is free: each one only does something
# once its `enable` (or equivalent) option is set from a host file.
{
  imports = [
    ./base.nix
    ./disk.nix
    ./laptop-server.nix
    ./containers.nix
    ./tunnel.nix
    ./tailscale.nix
    ./gitops.nix
    ./services/gorilla-blackout.nix
  ];
}
