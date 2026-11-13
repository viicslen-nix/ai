root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-desktop"
first_port=5960
last_port=5999

usage() {
  cat <<'EOF'
agent-desktop: headless Wayland desktops for agents, invisible to your session.

  up [name]                    start a desktop (default name: default)
  down [name]                  stop it and every app it runs
  list                         running desktops and their VNC ports
  run <name> [--fresh] -- cmd  launch a GUI app in it (detached; logs to a file)
  exec <name> -- cmd           run a command against it in the foreground
  windows <name>               list its windows (JSON lines)
  shot <name> [path]           screenshot the whole output to a PNG
  type <name> <text>           type text into the focused window
  key <name> <combo>...        press keys: Return, ctrl+s, ctrl+shift+t, ...
  click <name> <x> <y> [left|right|middle]
  dclick <name> <x> <y>        double-click
  hover <name> <x> <y> [path]   screenshot with the pointer held over x,y
  drag <name> <x1> <y1> <x2> <y2>
  scroll <name> <x> <y> <up|down> [steps]
  size <name> <WxH>            change the output resolution
  view [name] [--interact]     watch it in a VNC viewer (view-only unless --interact);
                               without a name, opens every running desktop
EOF
}

die() {
  echo "agent-desktop: $*" >&2
  exit 1
}

check_name() {
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid desktop name '$1' (use letters, digits, - and _)"
}

unit_of() { echo "agent-desktop@$1.service"; }

running() { systemctl --user -q is-active "$(unit_of "$1")"; }

load() {
  check_name "$1"
  running "$1" && [[ -f $root/$1/env ]] || die "desktop '$1' is not running; start it with: agent-desktop up $1"
  set -a
  # shellcheck disable=SC1090
  . "$root/$1/env"
  set +a
  unset NIRI_SOCKET HYPRLAND_INSTANCE_SIGNATURE
  export XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
}

free_port() {
  local p
  for ((p = first_port; p <= last_port; p++)); do
    grep -qsx "AGENT_DESKTOP_VNC_PORT=$p" "$root"/*/env && continue
    [[ -z $(ss -Hltn "sport = :$p") ]] && echo "$p" && return
  done
  die "no free VNC port in $first_port-$last_port"
}

# Runs as ExecStart of agent-desktop@<name>.service.
session() {
  local name=$1 state=$root/$1 port
  mkdir -p "$state"
  port=$(free_port)
  printf 'address=127.0.0.1\nport=%s\n' "$port" >"$state/vnc.conf"
  cat >"$state/sway.conf" <<EOF
output HEADLESS-1 resolution 1920x1080 bg #202020 solid_color
xwayland enable
focus_on_window_activation focus
exec dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
exec $self _ready $name $port
exec wayvnc -r -R -C $state/vnc.conf -S $state/wayvncctl -o HEADLESS-1
EOF
  exec dbus-run-session -- sway -c "$state/sway.conf"
}

# Runs inside sway, which hands its children the desktop's socket, display and bus.
ready() {
  local env=$root/$1/env
  {
    for v in WAYLAND_DISPLAY DISPLAY SWAYSOCK DBUS_SESSION_BUS_ADDRESS; do
      printf '%s=%q\n' "$v" "${!v-}"
    done
    printf 'AGENT_DESKTOP_VNC_PORT=%s\n' "$2"
  } >"$env.tmp"
  mv "$env.tmp" "$env"
}

port_of() { sed -n 's/^AGENT_DESKTOP_VNC_PORT=//p' "$root/$1/env"; }

up() {
  local name=${1:-default} i
  check_name "$name"
  if ! running "$name"; then
    systemctl --user reset-failed "$(unit_of "$name")" 2>/dev/null || true
    systemctl --user start "$(unit_of "$name")"
  fi
  for ((i = 0; i < 100; i++)); do
    [[ -f $root/$name/env ]] && break
    sleep 0.1
  done
  [[ -f $root/$name/env ]] || die "desktop '$name' did not come up; see: journalctl --user -u $(unit_of "$name")"
  echo "desktop '$name' is up (1920x1080). Watch it: agent-desktop view $name (VNC 127.0.0.1:$(port_of "$name"))"
}

down() {
  local name=${1:-default}
  check_name "$name"
  systemctl --user stop "$(unit_of "$name")"
  echo "desktop '$name' stopped"
}

names() {
  systemctl --user list-units --plain --no-legend --state=active 'agent-desktop@*.service' |
    sed -n 's/^agent-desktop@\([^ ]*\)\.service .*/\1/p'
}

list() {
  local name
  for name in $(names); do
    printf '%s\tvnc 127.0.0.1:%s\n' "$name" "$(port_of "$name" 2>/dev/null || echo '?')"
  done
}

run() {
  local name=${1:-} fresh='' unit log
  shift || true
  load "$name"
  [[ ${1:-} == --fresh ]] && fresh=1 && shift
  [[ ${1:-} == -- ]] && shift
  (($#)) || die "usage: agent-desktop run <name> [--fresh] -- <command>..."
  if [[ -n $fresh ]]; then
    export XDG_CONFIG_HOME=$root/$name/home/config XDG_DATA_HOME=$root/$name/home/data \
      XDG_CACHE_HOME=$root/$name/home/cache XDG_STATE_HOME=$root/$name/home/state
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  fi
  unit=agent-desktop-$name-$(date +%s%N | tail -c 8)
  log=$root/$name/$unit.log
  # Chromium ignores SIGTERM once its X server is gone, hence the short stop timeout.
  setsid -f systemd-run --user --scope --quiet --unit="$unit" \
    -p PartOf="$(unit_of "$name")" -p TimeoutStopSec=5 -- "$@" >"$log" 2>&1 </dev/null
  echo "started in '$name' as $unit.scope; log: $log"
}

exec_in() {
  local name=${1:-}
  shift || true
  load "$name"
  [[ ${1:-} == -- ]] && shift
  (($#)) || die "usage: agent-desktop exec <name> -- <command>..."
  exec "$@"
}

windows() {
  load "$1"
  swaymsg -t get_tree | jq -c '.. | select(.type? == "con" or .type? == "floating_con") | select(.pid != null)
    | {id, app_id: (.app_id // .window_properties.class), title: .name, focused,
       x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}'
}

shot() {
  local name=$1 path=${2:-}
  load "$name"
  path=${path:-$(shot_path "$name")}
  grim "$path"
  echo "$path"
}

shot_path() { echo "${TMPDIR:-/tmp}/agent-desktop-$1-$(date +%Y%m%d-%H%M%S).png"; }

# wtype drops a lone key sent right after it uploads its keymap; -s 100 gives the client time.
type_text() {
  load "$1"
  printf '%s' "$2" | wtype -s 100 -
}

key() {
  local name=${1:-} combo part
  local -a args=(-s 100) mods
  shift || true
  load "$name"
  (($#)) || die "usage: agent-desktop key <name> <combo>..."
  for combo in "$@"; do
    IFS=+ read -ra mods <<<"$combo"
    local k=${mods[-1]}
    unset 'mods[-1]'
    for part in "${mods[@]}"; do
      args+=(-M "$(modifier "$part")")
    done
    args+=(-k "$k")
    for part in "${mods[@]}"; do
      args+=(-m "$(modifier "$part")")
    done
  done
  wtype "${args[@]}"
}

modifier() {
  case ${1,,} in
  ctrl | control) echo ctrl ;;
  shift) echo shift ;;
  alt) echo alt ;;
  super | logo | meta | win) echo logo ;;
  altgr) echo altgr ;;
  *) die "unknown modifier '$1' (ctrl, shift, alt, super, altgr)" ;;
  esac
}

button() {
  case ${1:-left} in
  left) echo 1 ;;
  middle) echo 2 ;;
  right) echo 3 ;;
  *) die "unknown button '$1' (left, right, middle)" ;;
  esac
}

# Headless sway has no pointer device and `seat - cursor` never reaches clients;
# wayvnc adds a virtual pointer per VNC connection, so pointer input goes through it.
# The pause lets the client bind that new pointer before the first button event.
pointer() {
  local name=$1 x=$2 y=$3
  shift 3
  number "$x" && number "$y"
  load "$name"
  timeout 30 vncdo -s "127.0.0.1::$(port_of "$name")" move "$x" "$y" pause 0.2 "$@" 2>/dev/null
}

hover() {
  local name=$1 path=${4:-} pid
  path=${path:-$(shot_path "$name")}
  pointer "$name" "$2" "$3" pause 2 &
  pid=$!
  sleep 1
  load "$name"
  grim "$path"
  wait "$pid"
  echo "$path"
}

number() { [[ $1 =~ ^[0-9]+$ ]] || die "expected a pixel coordinate, got '$1'"; }

dispatch() {
  local cmd=${1:-help}
  shift || true
  case $cmd in
  up) up "$@" ;;
  down) down "$@" ;;
  list | ls) list ;;
  run) run "$@" ;;
  exec) exec_in "$@" ;;
  windows) windows "${1:-default}" ;;
  shot) shot "${1:-default}" "${2:-}" ;;
  type)
    (($# == 2)) || die "usage: agent-desktop type <name> <text>"
    type_text "$1" "$2"
    ;;
  key) key "$@" ;;
  click)
    (($# >= 3)) || die "usage: agent-desktop click <name> <x> <y> [left|right|middle]"
    pointer "$1" "$2" "$3" click "$(button "${4:-left}")"
    ;;
  dclick)
    (($# == 3)) || die "usage: agent-desktop dclick <name> <x> <y>"
    pointer "$1" "$2" "$3" click 1 click 1
    ;;
  hover)
    (($# >= 3)) || die "usage: agent-desktop hover <name> <x> <y> [path]"
    hover "$@"
    ;;
  drag)
    (($# == 5)) || die "usage: agent-desktop drag <name> <x1> <y1> <x2> <y2>"
    number "$4" && number "$5"
    pointer "$1" "$2" "$3" mousedown 1 drag "$4" "$5" mouseup 1
    ;;
  scroll)
    (($# >= 4)) || die "usage: agent-desktop scroll <name> <x> <y> <up|down> [steps]"
    number "${5:-3}"
    local b i
    local -a clicks=()
    case $4 in up) b=4 ;; down) b=5 ;; *) die "scroll direction must be up or down" ;; esac
    for ((i = 0; i < ${5:-3}; i++)); do clicks+=(click "$b"); done
    pointer "$1" "$2" "$3" "${clicks[@]}"
    ;;
  size)
    (($# == 2)) && [[ $2 =~ ^[0-9]+x[0-9]+$ ]] || die "usage: agent-desktop size <name> <WxH>"
    load "$1"
    swaymsg -q "output HEADLESS-1 resolution $2"
    ;;
  view) view "$@" ;;
  _session) session "$1" ;;
  _ready) ready "$1" "$2" ;;
  help | -h | --help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
  esac
}

view() {
  local -a targets=() flags=(-ViewOnly)
  local arg name
  for arg in "$@"; do
    case $arg in
    --interact) flags=() ;;
    *) targets+=("$arg") ;;
    esac
  done
  ((${#targets[@]})) || mapfile -t targets < <(names)
  ((${#targets[@]})) || die "no desktop is running"
  for name in "${targets[@]}"; do
    check_name "$name"
    running "$name" || die "desktop '$name' is not running"
    setsid -f vncviewer "${flags[@]}" "127.0.0.1::$(port_of "$name")" >/dev/null 2>&1 </dev/null
  done
}

self=$(realpath "${BASH_SOURCE[0]}")
dispatch "$@"
