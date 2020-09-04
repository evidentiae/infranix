{
  description = "infranix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/20.03";

  outputs = {self, nixpkgs}: {

    lib.evalModulesWithInputs = {modules ? [], inputs ? {}, ...}@attrs:
      nixpkgs.lib.evalModules (
        (builtins.removeAttrs attrs ["system" "inputs" "modules"]) // {
          specialArgs = (attrs.specialArgs or {}) // {
            inherit inputs;
            paths = inputs; # for backwards compatibility
          };
          modules = modules ++ [
            (nixpkgs + "/nixos/modules/misc/nixpkgs.nix")
            { nixpkgs.system = attrs.system; }
            ./nix/cli.nix
          ];
        }
      );

    lib.mkShell = attrs: (
      self.lib.evalModulesWithInputs attrs
    ).config.cli.build.shell;

  };
}
