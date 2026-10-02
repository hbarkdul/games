#!/usr/bin/env bash
# Print the IDs Pangolin knows about, so you can confirm the values to use.
#   export PANGOLIN_URL=https://<your integration api base>   PANGOLIN_API_KEY=<id>.<secret>   PANGOLIN_ORG=<org id>
set -u
: "${PANGOLIN_URL:?set PANGOLIN_URL}" "${PANGOLIN_API_KEY:?set PANGOLIN_API_KEY}" "${PANGOLIN_ORG:?set PANGOLIN_ORG}"
get() { curl -sS -H "Authorization: Bearer $PANGOLIN_API_KEY" "${PANGOLIN_URL%/}$1"; }
show() { local raw; raw=$(get "$1"); jq -r "$2" <<<"$raw" 2>/dev/null || echo "  (unexpected response) $raw"; }
echo "== Sites: siteId | niceId | name   (PANGOLIN_SITE = niceId or name) =="
show "/org/$PANGOLIN_ORG/sites?limit=1000" '.data.sites[]? | "\(.siteId)  \(.niceId)  \(.name)  online=\(.online)"'
echo; echo "== Domains: domainId | baseDomain | type   (PANGOLIN_DOMAIN = baseDomain) =="
show "/org/$PANGOLIN_ORG/domains?limit=1000" '.data.domains[]? | "\(.domainId)  \(.baseDomain)  \(.type)  verified=\(.verified)"'
echo; echo "== Existing public resources =="
show "/org/$PANGOLIN_ORG/resources?limit=1000" '.data.resources[]? | "\(.resourceId)  \(.name)  \(.fullDomain // "")"'
