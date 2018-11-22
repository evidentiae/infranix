#!/bin/sh

set -eu
set -o pipefail

origArgs=("$@")
cmd=""
cmdArgs=()
nixArgs=()
bootstrap=1
BASE_DIR="$(readlink -m .)"

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
      ;;
    *)
      if [ -z "$cmd" ]; then
        nixArgs+=("$x")
      else
        cmdArgs+=("$x")
      fi
      ;;
  esac
done

export BASE_DIR
pushd "$BASE_DIR" &>/dev/null

trap 'echo >&2 "Reloading shell..."; exec "$0" -d "$BASE_DIR" "${origArgs[@]}"' SIGHUP

cacheDir="${HOME}/.cache/infranix/drvs"
mkdir -p "$cacheDir"
link="$(readlink -m "$cacheDir/shell-$(date +%s%N)")"

pathsfile="$BASE_DIR/paths.nix"

export NIX_PATH=""

nixArgs+=(
  --fallback
  -f "$EVAL"
  --option tarball-ttl 0
  --arg paths "$BASE_DIR/paths.nix"
  --arg configuration "import \"$BASE_DIR\""
  "$@"
)

if [ -n "$bootstrap" ]; then
  nix build -o "$link-bootstrap" "${nixArgs[@]}" config.cli.build.bootstrapScript
  if [ -x "$link-bootstrap" ]; then
    "$link-bootstrap"
  fi
fi

nix build -o "$link" "${nixArgs[@]}" config.cli.build.bashrc
if [ -a "$link" ]; then
  if [ -z "$cmd" ]; then
    RELOADER_PID=$$ SHELL_RC="$link" bash --rcfile "$link" -i
  else
    RELOADER_PID=$$ SHELL_RC="$link" bash --rcfile "$link" -i \
      -c "$cmd"' "$@"' bash "${cmdArgs[@]}"
  fi
else
  echo >&2 "Build failed"
  exit 1
fi

popd &>/dev/null
