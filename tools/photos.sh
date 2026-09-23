#!/usr/bin/env bash
# Search Pexels and Unsplash for stock photos.
#
# Usage: tools/photos.sh <pexels|unsplash|all> "<query>" [count]
#
# Reads API keys from the environment (never hard-code them):
#   PEXELS_API_KEY        https://www.pexels.com/api/
#   UNSPLASH_ACCESS_KEY   https://unsplash.com/developers
#
# Prints one JSON object per photo:
#   {source, id, alt, photographer, photographer_url, page_url, image_url, width, height}
set -euo pipefail

usage() { echo "Usage: $0 <pexels|unsplash|all> \"<query>\" [count]" >&2; exit 2; }

[[ $# -ge 2 ]] || usage
provider=$1
query=$2
count=${3:-5}
[[ $count =~ ^[0-9]+$ && $count -ge 1 && $count -le 30 ]] || { echo "count must be 1-30" >&2; exit 2; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
encoded=$(jq -rn --arg q "$query" '$q|@uri')

pexels() {
  : "${PEXELS_API_KEY:?PEXELS_API_KEY is not set}"
  curl -sS --fail-with-body \
    -H "Authorization: $PEXELS_API_KEY" \
    "https://api.pexels.com/v1/search?query=$encoded&per_page=$count" |
  jq -c '.photos[] | {
    source: "pexels", id, alt,
    photographer, photographer_url,
    page_url: .url, image_url: .src.large, width, height
  }'
}

unsplash() {
  : "${UNSPLASH_ACCESS_KEY:?UNSPLASH_ACCESS_KEY is not set}"
  curl -sS --fail-with-body \
    -H "Authorization: Client-ID $UNSPLASH_ACCESS_KEY" \
    -H "Accept-Version: v1" \
    "https://api.unsplash.com/search/photos?query=$encoded&per_page=$count" |
  jq -c '.results[] | {
    source: "unsplash", id, alt: (.alt_description // .description),
    photographer: .user.name, photographer_url: .user.links.html,
    page_url: .links.html, image_url: .urls.regular, width, height
  }'
}

case $provider in
  pexels) pexels ;;
  unsplash) unsplash ;;
  all) pexels; unsplash ;;
  *) usage ;;
esac
