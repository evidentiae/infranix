# Mostly copied from nixpkgs/nixos/default.nix to be able to inject
# `specialArgs.paths` to nixpkgs/nixos/lib/eval-config.nix
#
# This file can be used as a replacement for <nixpkgs/nixos>:
#
#  NIX_PATH=nixpkgs/nixos=eval-nixos-with-paths.nix nixos-rebuild ...

{ ... }:

let

  pathsFile = let f = builtins.getEnv "NIX_PATHS_FILE"; in
    if f != "" then f
    else builtins.throw "NIX_PATHS_FILE environment variable not set";

  paths = import ./eval-paths.nix pathsFile;

  eval = import (paths.nixpkgs + "/nixos/lib/eval-config.nix") {
    specialArgs.paths = paths;
    modules = [
      paths.nixos-config
    ];
  };

  # This is for `nixos-rebuild build-vm'.
  vmConfig = (import (paths.nixpkgs + "/nixos/lib/eval-config.nix") {
    specialArgs.paths = paths;
    modules = [
      paths.nixos-config
      (paths.nixpkgs + "nixos/modules/virtualisation/qemu-vm.nix")
    ];
  }).config;

  # This is for `nixos-rebuild build-vm-with-bootloader'.
  vmWithBootLoaderConfig = (import (paths.nixpkgs + "/nixos/lib/eval-config.nix") {
    specialArgs.paths = paths;
    modules = [
      paths.nixos-config
      (paths.nixpkgs + "nixos/modules/virtualisation/qemu-vm.nix")
      { virtualisation.useBootLoader = true; }
    ];
  }).config;

in

{
  inherit (eval) pkgs config options;

  system = eval.config.system.build.toplevel;

  vm = vmConfig.system.build.vm;

  vmWithBootLoader = vmWithBootLoaderConfig.system.build.vm;
}
