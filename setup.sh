#!/bin/sh
# Brushfall: guided setup for Docker hosts (macOS, Linux, Raspberry Pi).
#
#   curl -fsSL https://raw.githubusercontent.com/Twelve47Studios/brushfall_release/main/setup.sh -o setup.sh
#   sh setup.sh                 # sets up ~/brushfall
#   sh setup.sh ~/somewhere     # or another folder
#   sh setup.sh --share         # also share it outside your home with Tailscale Funnel
#
# It is safe to run again: your .env settings are never replaced.
# What it does: checks Docker, gets docker-compose.yml and .env, picks a free port,
# starts Brushfall, and shows the address and the one-time setup code for the Studio Desk.

RAW_URL="https://raw.githubusercontent.com/Twelve47Studios/brushfall_release/main"
FIRST_PORT=8080
SETUP_CODE_CMD="brushfall setup-code"

say() { printf '%s\n' "$*"; }
fail() {
  printf '\n%s\n' "Sorry, setup stopped: $*" >&2
  exit 1
}

FOLDER="$HOME/brushfall"
SHARE=no
for arg in "$@"; do
  case "$arg" in
    --share) SHARE=yes ;;
    -h | --help)
      say "Usage: sh setup.sh [folder] [--share]"
      say "  folder   where Brushfall keeps its two files (default: ~/brushfall)"
      say "  --share  also let family outside your home join, with Tailscale Funnel"
      exit 0
      ;;
    -*) fail "I don't know the option \"$arg\". Try: sh setup.sh --help" ;;
    *) FOLDER="$arg" ;;
  esac
done

say ""
say "Hello! Let's set up your Brushfall world."
say ""

# --- 1. Docker ---------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  fail "Docker isn't installed yet. Install it from https://docs.docker.com/get-docker/ (on a Mac: Docker Desktop), start it, and run this again."
fi
docker_err=$(docker info 2>&1 >/dev/null)
if [ $? -ne 0 ]; then
  case "$docker_err" in
    *"permission denied"* | *"Permission denied"*)
      fail "Docker is installed, but your account isn't allowed to use it yet. Run: sudo usermod -aG docker \$USER  then log out and back in (or restart), and run this again."
      ;;
  esac
  if [ "$(uname -s)" = "Darwin" ]; then
    fail "Docker is installed but not running. Start Docker Desktop and look for the whale icon in the menu bar; when it stops moving, run this again."
  fi
  fail "Docker is installed but not running. Start it (Docker Desktop: look for the whale icon; a server: sudo systemctl start docker) and run this again. Docker said: $docker_err"
fi
if ! docker compose version >/dev/null 2>&1; then
  fail "Docker is running, but \"docker compose\" is missing. Update Docker Desktop, or on Linux install the Compose plugin: https://docs.docker.com/compose/install/linux/"
fi
say "Docker is installed and running. Good."

# --- 2. The folder and its two files ----------------------------------------
mkdir -p "$FOLDER" || fail "I couldn't make the folder $FOLDER."
cd "$FOLDER" || fail "I couldn't open the folder $FOLDER."
say "Your Brushfall folder: $(pwd)"

download() { # download <published path> <file>
  curl -fsSL "$RAW_URL/$1" -o "$2" || fail "I couldn't download $RAW_URL/$1. Check this computer is online and try again."
}

download docker-compose.yml docker-compose.yml.new
if [ ! -f docker-compose.yml ]; then
  mv docker-compose.yml.new docker-compose.yml
  say "Got docker-compose.yml (what to run)."
elif cmp -s docker-compose.yml docker-compose.yml.new; then
  rm -f docker-compose.yml.new
  say "docker-compose.yml is already up to date."
else
  mv docker-compose.yml docker-compose.yml.old
  mv docker-compose.yml.new docker-compose.yml
  say "Note: there was a newer docker-compose.yml, so I put it in place. Your old one is saved as docker-compose.yml.old in case you had changed it."
fi

NEW_ENV=no
if [ -f .env ]; then
  say "Keeping your settings in .env (I never replace it)."
else
  download .env.example .env
  NEW_ENV=yes
  say "Got .env (your settings)."
fi
chmod 600 .env || fail "I couldn't make .env private to your account."

# env_get KEY: the last value of KEY= in .env (empty when missing).
env_get() {
  sed -n "s/^$1=//p" .env | tail -n 1 | tr -d '\r"'
}
# env_set KEY VALUE: change KEY's line in .env in place, or add it. Keeps the file's permissions.
env_set() {
  ENV_KEY="$1" ENV_VALUE="$2" awk '
    BEGIN { k = ENVIRON["ENV_KEY"]; v = ENVIRON["ENV_VALUE"]; done = 0 }
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' .env > .env.tmp || fail "I couldn't update $1 in .env."
  cat .env.tmp > .env || fail "I couldn't write .env."
  rm -f .env.tmp
}

# --- 3. A free port -----------------------------------------------------------
port_busy() { # exit 0 when something on this computer listens on TCP port $1
  case "$(uname -s)" in
    Darwin)
      lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
      ;;
    *)
      command -v ss >/dev/null 2>&1 || fail "I need the \"ss\" tool to find a free port (it comes in the iproute2 package). Install it, or set BRUSHFALL_PORT in .env yourself."
      [ -n "$(ss -Hltn "sport = :$1")" ]
      ;;
  esac
}

PORT=$(env_get BRUSHFALL_PORT)
if [ "$NEW_ENV" = no ] && [ -n "$PORT" ]; then
  say "Using port $PORT from your .env."
else
  PORT=$FIRST_PORT
  while port_busy "$PORT"; do
    PORT=$((PORT + 1))
    [ "$PORT" -le $((FIRST_PORT + 50)) ] || fail "Ports $FIRST_PORT to $((PORT - 1)) are all in use on this computer. Set BRUSHFALL_PORT in .env to a free one and run this again."
  done
  env_set BRUSHFALL_PORT "$PORT"
  if [ "$PORT" = "$FIRST_PORT" ]; then
    say "Brushfall will use port $PORT."
  else
    say "Port $FIRST_PORT is already used by something else on this computer, so Brushfall will use port $PORT."
  fi
fi

# --- 4. Start it --------------------------------------------------------------
wait_for_health() {
  printf 'Waiting for your world to wake up'
  tries=0
  while [ $tries -lt 60 ]; do
    case "$(curl -fsS --max-time 3 "http://localhost:$PORT/api/health" 2>/dev/null)" in
      *'"ok":true'*)
        say " ready!"
        return 0
        ;;
    esac
    printf '.'
    sleep 2
    tries=$((tries + 1))
  done
  say ""
  say "Here is what Brushfall said last:"
  docker compose logs --tail 30 brushfall
  fail "Brushfall didn't answer on http://localhost:$PORT within 2 minutes. The lines above usually say why. Fix that (or ask for help at https://github.com/Twelve47Studios/brushfall_release/issues) and run this again."
}

say ""
say "Starting Brushfall. The first time, Docker downloads it, which takes a minute or two..."
docker compose up -d || fail "Docker couldn't start Brushfall (the message above says why)."
wait_for_health

# --- 5. The setup code --------------------------------------------------------
code_err=$(mktemp) || fail "I couldn't make a temporary file."
CODE=$(docker compose exec -T brushfall $SETUP_CODE_CMD 2>"$code_err")
code_status=$?
code_msg=$(cat "$code_err")
rm -f "$code_err"
case $code_status in
  0) [ -n "$CODE" ] || fail "Brushfall gave an empty setup code. Run: docker compose exec brushfall $SETUP_CODE_CMD" ;;
  3) CODE="" ;;
  *) fail "I couldn't get the setup code ($code_msg). Try: docker compose exec brushfall $SETUP_CODE_CMD" ;;
esac

lan_address() {
  case "$(uname -s)" in
    Darwin)
      iface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
      [ -n "$iface" ] && ipconfig getifaddr "$iface" 2>/dev/null
      ;;
    *)
      command -v ip >/dev/null 2>&1 && ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1
      ;;
  esac
}

ADMIN_URL="http://localhost:$PORT/admin"
LAN=$(lan_address)

say ""
say "+--------------------------------------------------------------+"
say "  Your Brushfall world is running!"
say ""
say "  Open:  $ADMIN_URL"
if [ -n "$CODE" ]; then
  say "  Setup code:  $CODE"
  say "  (type it on that page, name your world and make your account)"
else
  say "  This world is already set up: sign in with your admin account."
fi
say ""
if [ -n "$LAN" ]; then
  say "  Family on your home Wi-Fi can join at http://$LAN:$PORT"
else
  say "  Family on your home Wi-Fi can join with this computer's address;"
  say "  the Studio Desk's Hosting tab shows it, with a QR code."
fi
say "  If your computer asks whether to allow incoming connections,"
say "  choose Allow, or family can't join."
say "+--------------------------------------------------------------+"

# --- 6. Open the browser --------------------------------------------------------
case "$(uname -s)" in
  Darwin) open "$ADMIN_URL" >/dev/null 2>&1 ;;
  *)
    if command -v xdg-open >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
      xdg-open "$ADMIN_URL" >/dev/null 2>&1 &
    fi
    ;;
esac

# --- 7. Sharing outside the home (optional) -------------------------------------
if [ "$SHARE" = no ] && [ -t 0 ]; then
  say ""
  printf 'Do you want family outside your home to join too, with Tailscale (free)? [y/N] '
  read -r answer
  case "$answer" in y | Y | yes | Yes | YES) SHARE=yes ;; esac
fi
[ "$SHARE" = yes ] || {
  say ""
  say "All done. Have fun painting! (Run this again with --share any time to let family outside your home join.)"
  exit 0
}

say ""
say "Sharing with Tailscale Funnel gives your world a public https address, with no router changes."
say "Before we start, in the Tailscale admin console (free account at https://tailscale.com):"
say "  1. DNS page: turn on MagicDNS and HTTPS Certificates."
say "  2. Access controls: allow Funnel (https://tailscale.com/kb/1223/funnel)."
say "  3. Settings > Keys (https://login.tailscale.com/admin/settings/keys): generate an auth key."

KEY=$(env_get TS_AUTHKEY)
if [ -n "$KEY" ]; then
  say "Using the Tailscale auth key already saved in your .env."
else
  printf 'Paste your Tailscale auth key (it stays hidden while you type) and press Enter: '
  if [ -t 0 ]; then
    trap 'stty echo' EXIT
    stty -echo
    read -r KEY
    stty echo
  else
    read -r KEY
  fi
  say ""
  case "$KEY" in
    tskey-*) ;;
    "") fail "No key was pasted. Run sh setup.sh --share again when you have one." ;;
    *) fail "That doesn't look like a Tailscale auth key (they start with tskey-). Copy it again from https://login.tailscale.com/admin/settings/keys" ;;
  esac
  env_set TS_AUTHKEY "$KEY"
fi
KEY=""

mkdir -p deploy || fail "I couldn't make the deploy folder."
download deploy/tailscale-funnel.json deploy/tailscale-funnel.json
env_set TS_SERVE_FILE tailscale-funnel.json
env_set TRUST_PROXY 1
# Docker reads this from .env, so plain "docker compose up -d" (and updates) include Tailscale from now on.
env_set COMPOSE_PROFILES tailscale

say "Starting Tailscale..."
docker compose --profile tailscale up -d || fail "Docker couldn't start Tailscale (the message above says why)."

printf 'Waiting for Tailscale to connect'
NAME=""
tries=0
while [ $tries -lt 30 ]; do
  status=$(docker compose exec -T tailscale tailscale status --json 2>/dev/null | tr -d '\n')
  state=$(printf '%s' "$status" | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p')
  if [ "$state" = Running ]; then
    NAME=$(printf '%s' "$status" | sed -n 's/.*"Self": *{[^}]*"DNSName": *"\([^"]*\)".*/\1/p')
    NAME=${NAME%.}
  fi
  [ -n "$NAME" ] && break
  printf '.'
  sleep 2
  tries=$((tries + 1))
done
say ""
if [ -z "$NAME" ]; then
  say "Here is what Tailscale said last:"
  docker compose logs --tail 30 tailscale
  fail "Tailscale didn't connect within a minute. The auth key may be wrong, expired or already used: make a new one, delete the TS_AUTHKEY value in $(pwd)/.env, and run sh setup.sh --share again."
fi

PUBLIC="https://$NAME"
env_set PUBLIC_URL "$PUBLIC"
say "Restarting Brushfall with its public address..."
docker compose up -d || fail "Docker couldn't restart Brushfall (the message above says why)."
wait_for_health

say ""
say "+--------------------------------------------------------------+"
say "  Family anywhere can now join at:"
say "  $PUBLIC"
say ""
say "  The very first visit can take a minute while Tailscale makes"
say "  the https certificate. Keep sign-ups on approval or invite."
say "+--------------------------------------------------------------+"
