{
  description = "infranix";

  outputs = {self}: {

    lib.evalModulesWithInputs = {modules ? [], inputs, system, ...}@attrs:
      inputs.nixpkgs.lib.evalModules (
        (builtins.removeAttrs attrs ["system" "inputs" "modules"]) // {
          specialArgs = (attrs.specialArgs or {}) // {
            inherit inputs;
          };
          modules = modules ++ [
            (inputs.nixpkgs + "/nixos/modules/misc/nixpkgs.nix")
            { nixpkgs.system = system; }
            ./nix/cli.nix
          ];
        }
      );

    lib.mkShell = attrs: (
      self.lib.evalModulesWithInputs attrs
    ).config.cli.build.shell;

    lib.mkBootstrapScript = attrs: (
      self.lib.evalModulesWithInputs attrs
    ).config.cli.build.bootstrapScript;

  };
}
