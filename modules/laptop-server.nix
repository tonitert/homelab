# Make a laptop behave like a server: keep running with the lid closed,
# never suspend, and turn the screen off.
{ config, lib, ... }:
{
  options.homelab.laptopServer.enable = lib.mkEnableOption "laptop-as-server power settings";

  config = lib.mkIf config.homelab.laptopServer.enable {
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      IdleAction = "ignore";
    };

    systemd.targets =
      lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" "suspend-then-hibernate" ]
        (_: {
          enable = false;
        });

    boot.kernelParams = [ "consoleblank=60" ]; # blank the built-in display after 60 s
  };
}
