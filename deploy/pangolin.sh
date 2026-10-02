#!/usr/bin/env bash
# Make sure <app>.<PANGOLIN_DOMAIN> exists in Pangolin as a public HTTP resource pointing at this app. Safe to re-run.
# Optional per-app file  <app>/app.env  with  SUBDOMAIN=...  and/or  TITLE=...
set -uo pipefail
app=$1; port=$2
if [ -z "${PANGOLIN_API_KEY:-}" ] || [ -z "${PANGOLIN_URL:-}" ]; then echo "Pangolin not configured - skipping resource creation"; exit 0; fi
for v in PANGOLIN_ORG PANGOLIN_SITE PANGOLIN_DOMAIN; do [ -n "${!v:-}" ] || { echo "$v is not set"; exit 1; }; done
command -v jq >/dev/null || { echo "jq is required on the runner (sudo apt install jq)"; exit 1; }

SUBDOMAIN=$app; TITLE=$app
[ -f "$app/app.env" ] && . "$app/app.env"
HOST="${PANGOLIN_TARGET_HOST:-$(hostname -I | awk '{print $1}')}"
API="${PANGOLIN_URL%/}"
FQDN="$SUBDOMAIN.$PANGOLIN_DOMAIN"

BODY=""; CODE=""
call() {   # method path [json]  -> sets BODY and CODE
  local out
  out=$(curl -sS -w '\n%{http_code}' -X "$1" -H "Authorization: Bearer $PANGOLIN_API_KEY" -H "Content-Type: application/json" ${3:+-d "$3"} "$API$2") || { BODY="curl failed"; CODE=000; return; }
  CODE=${out##*$'\n'}; BODY=${out%$'\n'*}
}
ok() { [[ "$CODE" =~ ^2 ]]; }
die() { echo "Pangolin: $1 (HTTP $CODE): $BODY"; exit 1; }

call GET "/org/$PANGOLIN_ORG/domains?limit=1000";  ok || die "could not list domains"
DOMAIN_ID=$(jq -r --arg d "$PANGOLIN_DOMAIN" '.data.domains[]? | select(.baseDomain==$d) | .domainId' <<<"$BODY" | head -1)
[ -n "$DOMAIN_ID" ] || { echo "Pangolin: no domain '$PANGOLIN_DOMAIN'. Available: $(jq -r '[.data.domains[]?.baseDomain]|join(", ")' <<<"$BODY")"; exit 1; }

call GET "/org/$PANGOLIN_ORG/sites?limit=1000";    ok || die "could not list sites"
SITE_ID=$(jq -r --arg s "$PANGOLIN_SITE" '.data.sites[]? | select(.niceId==$s or .name==$s or (.siteId|tostring)==$s) | .siteId' <<<"$BODY" | head -1)
[ -n "$SITE_ID" ] || { echo "Pangolin: no site '$PANGOLIN_SITE'. Available: $(jq -r '[.data.sites[]?|.niceId]|join(", ")' <<<"$BODY")"; exit 1; }

call GET "/org/$PANGOLIN_ORG/resources?limit=1000"
if ok && [ -n "$(jq -r --arg f "$FQDN" '.data.resources[]? | select(.fullDomain==$f) | .resourceId' <<<"$BODY")" ]; then
  echo "Pangolin: $FQDN already published - nothing to do"; exit 0
fi

PAYLOAD=$(jq -nc --arg n "$TITLE" --arg s "$SUBDOMAIN" --arg d "$DOMAIN_ID" '{name:$n,http:true,subdomain:$s,domainId:$d,protocol:"tcp"}')
call PUT "/org/$PANGOLIN_ORG/public-resource" "$PAYLOAD"
[ "$CODE" = 404 ] && call PUT "/org/$PANGOLIN_ORG/resource" "$PAYLOAD"      # older Pangolin versions
if ! ok; then
  grep -qi 'exist' <<<"$BODY" && { echo "Pangolin: $FQDN already exists - nothing to do"; exit 0; }
  die "could not create resource"
fi
RID=$(jq -r '.data.resourceId' <<<"$BODY")

TARGET=$(jq -nc --argjson s "$SITE_ID" --arg ip "$HOST" --argjson p "$port" '{siteId:$s,ip:$ip,port:$p,method:"http"}')
call PUT "/public-resource/$RID/target" "$TARGET"
[ "$CODE" = 404 ] && call PUT "/resource/$RID/target" "$TARGET"
ok || die "resource $RID created but adding the target failed"

# Make the page reachable without a Pangolin login (best effort - check the dashboard if this warns)
if [ "${PANGOLIN_SSO:-false}" = "false" ]; then
  call POST "/public-resource/$RID" '{"sso":false}'
  [ "$CODE" = 404 ] && call POST "/resource/$RID" '{"sso":false}'
  ok || echo "WARNING: could not switch off SSO automatically ($CODE) - set authentication for $FQDN in the Pangolin dashboard"
fi
echo "Pangolin: published https://$FQDN -> $HOST:$port (resource $RID, site $SITE_ID)"
