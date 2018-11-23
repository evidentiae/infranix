#!/bin/sh

set -eu
set -o pipefail

origArgs=("$@")
cmd=""
cmdstr=""
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
    -c)
      if [ "$#" -lt 1 ]; then
        echo >&2 "No command specified"
        exit 1
      elif [ -n "$cmd" ]; then
        echo >&2 "Options -c and --run can't be combined"
        exit 1
      fi
      cmdstr="$1"
      shift
      ;;
    --run)
      if [ "$#" -lt 1 ]; then
        echo >&2 "No command specified"
        exit 1
      elif [ -n "$cmdstr" ]; then
        echo >&2 "Options -c and --run can't be combined"
        exit 1
      fi
      cmd="$1"
      shift
      ;;
    *)
      if [ -z "$cmd" ] && [ -z "$cmdstr" ]; then
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

if [ -n "$cmd" ]; then
  nix build -o "$link" "${nixArgs[@]}" config.cli.commands."$cmd".package
  if [ -x "$link/bin/$cmd" ]; then
    exec "$link/bin/$cmd" "${cmdArgs[@]}"
  else
    echo >&2 "Build failed"
    exit 1
  fi
else
  nix build -o "$link" "${nixArgs[@]}" config.cli.build.bashrc
  if [ -a "$link" ]; then
    if [ -z "$cmdstr" ]; then
      RELOADER_PID=$$ SHELL_RC="$link" bash --rcfile "$link" -i
    else
      RELOADER_PID=$$ SHELL_RC="$link" bash --rcfile "$link" -i \
        -c "$cmdstr"' "$@"' bash "${cmdArgs[@]}"
    fi
  else
    echo >&2 "Build failed"
    exit 1
  fi
fi

popd &>/dev/null
