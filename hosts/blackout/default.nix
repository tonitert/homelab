# The laptop server. Everything machine-specific lives here; reusable
# behaviour lives in ../../modules.
{ ... }:
{
  imports = [ ./hardware.nix ];

  homelab = {
    adminUser = "toni";
    # From https://github.com/tonitert.keys
    adminKeys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDAlIMcNhfbmQtU7UNF+vS0ayDG53Df+QisXUk/yAG/wCF+2cVxITcs4fu/Ajnud08JaZZbyKmImE18e//40cl+NquZHXh1ZRuLTzWlA159GVHt0cZyvDMZ+YoDKw+fkYAzFkNQO1gh1u4GFXHBLDEPf4/Q5rrUfUArWsggF9zJdoGKmY1s8Cuh9iqW9bXD7VwqbV7b/WpoWHLocetewbP9GjX+ZwEiu9pEwd2ZvqlEtHVaPN1PX1UdL0hqqKFwHWf7jz9NA/xA+Nrc0K+0bXIdQzDwf8cdVTl/HaXZTfAj3npDZBw2kWR5Q1IzMMXXSHNdn8c8ZALPJMwenkKC5NxHvahuJZd8fg08FDO+bP9870JFd3L4GysDvXgFEPYs/UhUuNgKm237tjQrhgmebHM+Il60/XKjRzTY3NdRIJtWPz90Mp1hRunGo3TW+1jXFYbuAXA6JbCsbWhmyjIcNqDlLU55uribvz0Kwh8aUHzIWTguliRszVtOtaizmYFi/Ys="
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDT3UWactw0gPjzt5LR6Nsck2o3E5wtAEf3KERI65Kbca6LiuCbQVI9NO1reaRDz5FM26R+urYtiUTTQbprOe3ROjA4ZZlho08vE4Z0EzKI1UtdVgxyDXHqf96MbheP4EKpbdPw7b4SXmrUmJLtLxQKARuwD/KJHLE2kqWUmtT4UhWBwviP7t1fzMP2de5V7EgaDfxeGu0ZL7djdYLCAG5we66OcpGPkwJvyyv8WwIRqlqI1ywCLZmkTgfqrtaacAYBNm4nxog6T0vdmlJWR9BdpQ358tlnmJzcVnWdWz1HPwSMcL/mwYDOBJqM7JgWnExf/RRgQVjdwvd55nlIGkVM0ojZp5CLvJlT+D7sdfX34nE2w4AR3D4AXHXQgczuKL6G/yVFCSEbF8DgA1HgQrzex/WHz47AjdOTu6oK1npNNQkB2CkUbLrwL/PYAS5e/0xA7m0mslgApXDB/Bud4jDQAg45/M5nz47h3hD57opkT33+Zh2kiIDn1SRohnvDEtE="
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP+Y+EfRXn3gHODTYIaOVwUn6w3tEr1GmQghxP72LKql"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG7amwnfT3AwqBmZ5gqC3LuxXEpNG8TR29XE3xl72RYz"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAION1ehE5mIj7mSAqtlXxW9wsY5p8YCys7UcR6leB+71f"
    ];

    # Default install target; the installer can pick another disk at install time.
    disk.device = "/dev/nvme0n1";

    laptopServer.enable = true;

    # Set to the UUID printed by `cloudflared tunnel create blackout`, then copy
    # the credentials JSON to /var/lib/secrets/cloudflared-tunnel.json on the laptop.
    tunnel.id = "6fb069b0-db7b-4cee-b855-9d0ea4399aee";

    services.gorilla-blackout.enable = true; # https://api.blackout.beer -> backend container

    tailscale.enable = true; # log in once with `sudo tailscale up`

    # Push to this repo and the laptop rebuilds itself from the newest commit
    # within 5 minutes (see modules/gitops.nix).
    gitops.flake = "github:tonitert/homelab";
  };

  # Set once at install time; don't change it when upgrading nixpkgs.
  system.stateVersion = "26.05";
}
