#!/bin/sh

set -e
set -o pipefail

origArgs=("$@")
bootstrap=1

while [ "$#" -gt 0 ]; do
  x="$1"; shift 1
  case "$x" in
    -d)
      BASE_DIR="$(readlink -m "$1")"
      shift
      ;;
    --no-bootstrap)
      bootstrap=""
      ;;
    --run)
      if [ "$#" -lt 1 ]; then
        echo >&2 "No command specified"
	exit 1
      fi
      cmd="$1"
      shift
      break
      ;;
    --)
      break
      ;;
    *)
      nixPathArgs+=("$x")
      ;;
  esac
done

if [ -z "$BASE_DIR" ]; then
  BASE_DIR="$(readlink -m .)"
fi
export BASE_DIR
pushd "$BASE_DIR" &>/dev/null

trap 'echo >&2 "Reloading shell..."; exec "$0" -d "$BASE_DIR" "${origArgs[@]}"' SIGHUP

mkdir -p "$BASE_DIR/.drvs"
link="$(readlink -m "$BASE_DIR/.drvs/shell-$(date +%s%N)")"

nixPathArgs=("-f" "$BASE_DIR/paths.nix" "${nixPathArgs[@]}")
NIX_PATH="$(nix-path "${nixPathArgs[@]}" env | grep '^NIX_PATH=' | cut -d = --complement -f 1)"
export NIX_PATH

evalDefault='let pkgs = import <nixpkgs> { config.allowUnfree = true; }; in pkgs.lib.evalModules { modules = [ ./default.nix { _module.args = { inherit pkgs; }; } ]; }'

if [ -n "$bootstrap" ]; then
  nix-build --fallback --out-link "$link-bootstrap" --drv-link "$link-bootstrap.drv" \
    -E "$evalDefault" -A config.cli.build.bootstrapScript
  if [ -x "$link-bootstrap" ]; then
    "$link-bootstrap"
  fi
fi

if [ -z "$cmd" ]; then
  nix-build --fallback --out-link "$link" --drv-link "$link.drv" \
    -E "$evalDefault" -A config.cli.build.bashrc "$@"
  if [ -a "$link" ]; then
    RELOADER_PID=$$ $SHELL --rcfile "$link" -i
  else
    echo >&2 "Build failed"
    exit 1
  fi
else
  nix-build --fallback --out-link "$link" --drv-link "$link.drv" \
    -E "$evalDefault" -A config.cli.commands."$cmd".package
  if [ -x "$link/bin/$cmd" ]; then
    exec "$link/bin/$cmd" "$@"
  else
    echo >&2 "Build failed"
    exit 1
  fi
fi

popd &>/dev/null
