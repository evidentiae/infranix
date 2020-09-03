{
  description = "infranix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/20.03";

  outputs = {self, nixpkgs}:

    let

      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

    in {

      lib.evalModulesWithInputs = {inputs ? {}, ...}@attrs:
        nixpkgs.lib.evalModules ((builtins.removeAttrs attrs ["inputs"]) // {
          specialArgs = (attrs.specialArgs or {}) // {
            inherit inputs;
            paths = inputs; # for backwards compatibility
          };
        });

      lib.mkShells = {modules, ...}@attrs: forAllSystems (system:
        (self.lib.evalModulesWithInputs (attrs // {
          modules = modules ++ [
            (nixpkgs + "/nixos/modules/misc/nixpkgs.nix")
            { nixpkgs.system = system; }
            ./nix/cli.nix
          ];
        })).config.cli.build.shell
      );

    };
}
