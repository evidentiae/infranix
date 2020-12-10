#!/usr/bin/env bash

set -eu
set -o pipefail

origArgs=("$@")
cmd=""
cmdstr=""
cmdArgs=()
nixArgs=()
extraPaths=()
bootstrap=1
pathsfile=""
tmppathsfile=""
configuration=""
BASE_DIR=""
timed=""

function cleanup() {
  if [ -n "$tmppathsfile" ]; then
    rm -f "$tmppathsfile"
  fi
}

trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  x="$1"; shift 1
  case "$x" in
    -d)
      BASE_DIR="$(readlink -m "$1")"
      shift
      ;;
    -f)
      configuration="$(readlink -m "$1")"
      shift
      ;;
    -p)
      pathsfile="$(readlink -m "$1")"
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
    --time)
      timed=1
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
    -I)
      if [ "$#" -lt 1 ]; then
        echo >&2 "Invalid -I option argument"
        exit 1
      fi
      kv="$1"
      k="${kv%%=*}"
      v="${kv#*=}"
      if [ -z "$k" ] || [ -z "$v" ]; then
        echo >&2 "Invalid -I option argument"
        exit 1
      fi
      extraPaths+=("\"$k\" = $v")
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

if [ -z "$configuration" ]; then
  configuration="$(readlink -m ./default.nix)"
  origArgs+=(-f "$configuration")
fi
if ! [ -r "$configuration" ]; then
  echo >&2 "Can't read shell configuration $configuration"
  exit 1
fi

if [ -z "$pathsfile" ]; then
  pathsfile="$(readlink -m ./paths.nix)"
  origArgs+=(-p "$pathsfile")
fi
if ! [ -f "$pathsfile" ]; then
  echo >&2 "Can't find paths file $pathsfile"
  exit 1
fi

if (( ${#extraPaths[@]} )); then
  tmppathsfile="$(mktemp -p . .paths-XXXXX.nix)"
  echo "(import $(readlink -m "$pathsfile")) // {" >> "$tmppathsfile"
  for p in "${extraPaths[@]}"; do
   echo "$p;" >> "$tmppathsfile"
  done
  echo "}" >> "$tmppathsfile"
  pathsfile="$tmppathsfile"
fi

if [ -z "$BASE_DIR" ]; then
  if [ -d "$configuration" ]; then
    BASE_DIR="$configuration"
  else
    BASE_DIR="$(dirname "$configuration")"
  fi
  origArgs+=(-d "$BASE_DIR")
fi
if ! [ -d "$BASE_DIR" ]; then
  echo >&2 "Base directory is not a valid directory"
  exit 1
fi

trap 'echo >&2 "Reloading shell..."; exec "$0" "${origArgs[@]}"' SIGHUP

cacheDir="${HOME}/.cache/infranix/drvs"
mkdir -p "$cacheDir"
link="$(readlink -m "$cacheDir/shell-$(date +%s%N)")"

export BASE_DIR
export NIX_PATH=""

nixArgs+=(
  --fallback
  -f "$INFRANIX_LIB/eval-paths-module.nix"
  --option tarball-ttl 0
  --arg paths "$pathsfile"
  --arg configuration "import \"$configuration\""
  "$@"
)

if [ -n "$bootstrap" ]; then
  if [ -n "$timed" ]; then
    TIME='+ build bootstrap %es' time nix build -o "$link-bootstrap" "${nixArgs[@]}" config.cli.build.bootstrapScript
  else
    nix build -o "$link-bootstrap" "${nixArgs[@]}" config.cli.build.bootstrapScript
  fi
  if [ -x "$link-bootstrap" ]; then
    "$link-bootstrap"
  fi
fi

if [ -n "$cmd" ]; then
  if [ -n "$timed" ]; then
    TIME='+ build command %es' time nix build -o "$link" "${nixArgs[@]}" config.cli.commands."$cmd".package
  else
    nix build -o "$link" "${nixArgs[@]}" config.cli.commands."$cmd".package
  fi
  if [ -x "$link/bin/$cmd" ]; then
    exec "$link/bin/$cmd" "${cmdArgs[@]}"
  else
    echo >&2 "Build failed"
    exit 1
  fi
else
  if [ -n "$timed" ]; then
    TIME='+ build shell %es' time nix build -o "$link" "${nixArgs[@]}" config.cli.build.bashrc
  else
    nix build -o "$link" "${nixArgs[@]}" config.cli.build.bashrc
  fi
  if [ -a "$link" ]; then
    if [ -z "$cmdstr" ]; then
      RELOADER_PID=$$ SHELL_RC="$(readlink "$link")" bash --rcfile "$link" -i
    else
      RELOADER_PID=$$ SHELL_RC="$(readlink "$link")" bash --rcfile "$link" -i \
        -c "$cmdstr"' "$@"' bash "${cmdArgs[@]}"
    fi
  else
    echo >&2 "Build failed"
    exit 1
  fi
fi

popd &>/dev/null
