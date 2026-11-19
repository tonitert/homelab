{
  description = "NixOS homelab: laptop server running gorilla-blackout, installable over PXE";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # A host is ./hosts/<name>/default.nix on top of the shared modules.
      mkHost =
        name: extraModules:
        lib.nixosSystem {
          modules = [
            disko.nixosModules.disko
            self.nixosModules.default
            ./hosts/${name}
            {
              networking.hostName = lib.mkDefault name;
              # The commit the system was built from (`nixos-version
              # --configuration-revision`); homelab.gitops compares it with
              # the newest commit on GitHub.
              system.configurationRevision = self.rev or self.dirtyRev or null;
            }
          ]
          ++ extraModules;
        };

      # PXE installer for a host: a RAM-only netboot system carrying the host's closure.
      mkInstaller =
        target: extraModules:
        lib.nixosSystem {
          specialArgs = { inherit target; };
          modules = [ ./installer/netboot.nix ] ++ extraModules;
        };

      # What a PXE server hands out: kernel, initrd, iPXE script and kernel command line.
      mkNetboot =
        installer:
        let
          inherit (installer.config.system) build;
        in
        pkgs.linkFarm "${installer.config.networking.hostName}-netboot" [
          {
            name = "bzImage";
            path = "${build.kernel}/${installer.config.system.boot.loader.kernelFile}";
          }
          {
            name = "initrd";
            path = "${build.netbootRamdisk}/initrd";
          }
          {
            name = "netboot.ipxe";
            path = "${build.netbootIpxeScript}/netboot.ipxe";
          }
          {
            name = "cmdline";
            path = pkgs.writeText "cmdline" (
              "init=${build.toplevel}/init " + toString installer.config.boot.kernelParams
            );
          }
        ];

      blackout = self.nixosConfigurations.blackout;
      netboot = mkNetboot self.nixosConfigurations.blackout-installer;
      tools = pkgs.callPackage ./tools {
        inherit netboot;
        inherit (blackout.config.networking) hostName;
        inherit (blackout.config.homelab) adminUser;
      };
    in
    {
      nixosModules.default = ./modules;

      nixosConfigurations = {
        blackout = mkHost "blackout" [ ];
        blackout-installer = mkInstaller blackout [ ];
      };

      packages.${system} = {
        inherit netboot;
        inherit (tools) pxe-server pxe-vm;
        default = netboot;
      };

      apps.${system} = {
        pxe-server = {
          type = "app";
          program = lib.getExe tools.pxe-server;
          meta.description = "Serve the blackout installer over PXE on the LAN (proxyDHCP, needs root)";
        };
        pxe-vm = {
          type = "app";
          program = lib.getExe tools.pxe-vm;
          meta.description = "UEFI PXE boot the blackout installer in a local QEMU VM";
        };
      };

      checks.${system} = {
        blackout = blackout.config.system.build.toplevel;
        pxe-install = import ./tests/pxe-install.nix {
          inherit pkgs mkInstaller mkNetboot;
          target = blackout;
        };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
