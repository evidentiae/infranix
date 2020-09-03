{
  description = "infranix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/20.03";

  outputs = {self, nixpkgs}: {

    lib.evalModulesWithInputs = {inputs ? {}, ...}@attrs:
      nixpkgs.lib.evalModules ((builtins.removeAttrs attrs ["inputs"]) // {
        specialArgs = (attrs.specialArgs or {}) // {
          inherit inputs;
          paths = inputs; # for backwards compatibility
        };
      });

    lib.mkShell = system: {modules, ...}@attrs:
      (self.lib.evalModulesWithInputs (attrs // {
        modules = modules ++ [
          (nixpkgs + "/nixos/modules/misc/nixpkgs.nix")
          { nixpkgs.system = system; }
          ./nix/cli.nix
        ];
      })).config.cli.build.shell;

  };
}
