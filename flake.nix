{

  description = "infranix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/20.03";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }: {

    lib.mkShell = inputs: module:
      flake-utils.lib.eachDefaultSystem (system: {
        defaultApp = (nixpkgs.lib.evalModules {
          specialArgs.inputs = inputs;
          specialArgs.paths = inputs; # for backwards compatibility
          modules = [
            (nixpkgs + "/nixos/modules/misc/nixpkgs.nix")
            { nixpkgs.system = system; }
            ./nix/cli.nix
            module
          ];
        }).config.cli.build.shell;
      });

  };

}
