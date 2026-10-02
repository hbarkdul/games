#!/usr/bin/env bash
# Build + (re)deploy every app directory that changed, then make sure each one is published in Pangolin.
# An "app" is any top-level directory that contains an index.html.  Usage: deploy.sh [app ...]
set -uo pipefail
cd "$(dirname "$0")/.."

STATE="${APPS_STATE_DIR:-$HOME/.heath-apps}"; mkdir -p "$STATE"; touch "$STATE/ports"
BASE_PORT="${BASE_PORT:-48081}"

is_app()   { [ -f "$1/index.html" ]; }
all_apps() { for d in */; do d=${d%/}; is_app "$d" && echo "$d"; done; }

# ---------- which apps need deploying? ----------
if [ "$#" -gt 0 ]; then
  APPS="$*"
elif [ "${DEPLOY_ALL:-}" = "true" ] || [ -z "${BEFORE_SHA:-}" ] || [[ "${BEFORE_SHA}" =~ ^0+$ ]] || ! git cat-file -e "${BEFORE_SHA}^{commit}" 2>/dev/null; then
  APPS=$(all_apps)
else
  CHANGED=$(git diff --name-only "$BEFORE_SHA" HEAD)
  if grep -qE '^(Dockerfile|nginx/|deploy/|\.dockerignore)' <<<"$CHANGED"; then
    echo "Infrastructure changed -> redeploying every app"; APPS=$(all_apps)
  else
    APPS=$(cut -d/ -f1 <<<"$CHANGED" | sort -u | while read -r d; do [ -d "$d" ] && is_app "$d" && echo "$d"; done)
  fi
fi
[ -n "${APPS// }" ] || { echo "Nothing to deploy."; exit 0; }
echo "Apps to deploy: $(echo $APPS)"

# ---------- stable host port per app ----------
port_of() {
  local app=$1 p
  p=$(docker inspect -f '{{with index .HostConfig.PortBindings "80/tcp"}}{{(index . 0).HostPort}}{{end}}' "$app" 2>/dev/null || true)
  [ -n "$p" ] || p=$(awk -v a="$app" '$1==a{print $2}' "$STATE/ports")
  if [ -z "$p" ]; then
    p=$BASE_PORT
    while grep -qE " $p\$" "$STATE/ports" || ss -ltn 2>/dev/null | grep -q ":$p " || docker ps -a --format '{{.Ports}}' | grep -q ":$p->"; do p=$((p+1)); done
  fi
  grep -q "^$app " "$STATE/ports" || echo "$app $p" >> "$STATE/ports"
  echo "$p"
}

deploy_app() {
  local app=$1 port i
  [[ "$app" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "Skipping '$app': use lowercase letters, digits and dashes"; return 1; }
  port=$(port_of "$app")
  echo "::group::$app (host port $port)"
  docker build --build-arg APP="$app" -t "heath-apps/$app:latest" . || return 1
  docker rm -f "$app" >/dev/null 2>&1 || true
  docker run -d --name "$app" --restart unless-stopped --label heath.apps=1 -p "$port:80" "heath-apps/$app:latest" >/dev/null || return 1
  for i in $(seq 1 20); do
    curl -fsS -o /dev/null "http://127.0.0.1:$port/" && break
    [ "$i" = 20 ] && { echo "Health check failed"; docker logs "$app" | tail -20; return 1; }
    sleep 0.5
  done
  bash deploy/pangolin.sh "$app" "$port" || echo "WARNING: container is up on :$port but the Pangolin step failed"
  echo "::endgroup::"
}

FAILED=""
for app in $APPS; do deploy_app "$app" || FAILED="$FAILED $app"; done
docker image prune -f >/dev/null 2>&1 || true
[ -z "$FAILED" ] || { echo "FAILED:$FAILED"; exit 1; }
echo "All done."
