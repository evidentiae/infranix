{ lib, ... }:

{
  system.activationScripts.nix = lib.mkForce ''
    mkdir -p /nix/var/nix/gcroots
  '';

  systemd.sockets.nix-daemon.enable = false;
}
