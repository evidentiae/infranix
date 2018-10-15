#!/bin/sh

set -eu
set -o pipefail

origArgs=("$@")
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
    --)
      break
      ;;
    *)
      echo >&2 "Unknown infranix option $x"
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

nixArgs=(
  --fallback
  -f "$EVAL"
  --arg paths "import \"$BASE_DIR/paths.nix\""
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
  RELOADER_PID=$$ SHELL_RC="$link" $SHELL --rcfile "$link" -i
else
  echo >&2 "Build failed"
  exit 1
fi

popd &>/dev/null
