#!/usr/bin/env bash
# Download mood-board reference images into Velor/<keyword>/ subfolders.
#
# Usage: tools/download-mood-board.sh [keywords-file] [count-per-keyword]
#   keywords-file      default: tools/mood-board-keywords.txt (one keyword per line, # comments ignored)
#   count-per-keyword  default: 10
#
# Sources: Pexels, Unsplash, Pixabay (round-robin, until `count` images are saved
# or all three sources are exhausted for that keyword). Kaboompics has no public
# search API and is not included here — download from it manually if you need it.
#
# Reads API keys from the environment (never hard-code them):
#   PEXELS_API_KEY        https://www.pexels.com/api/
#   UNSPLASH_ACCESS_KEY   https://unsplash.com/developers
#   PIXABAY_API_KEY       https://pixabay.com/api/docs/
#
# Output: Velor/<slugified-keyword>/NN-<source>-<id>.<ext>
#         Velor/<slugified-keyword>/CREDITS.txt   (photographer + link + license, per image)
set -euo pipefail

keywords_file=${1:-tools/mood-board-keywords.txt}
count=${2:-10}
out_root=${VELOR_OUT_DIR:-Velor}

[[ -f "$keywords_file" ]] || { echo "keywords file not found: $keywords_file" >&2; exit 2; }
[[ $count =~ ^[0-9]+$ && $count -ge 1 ]] || { echo "count must be a positive integer" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

have_pexels=0; have_unsplash=0; have_pixabay=0
[[ -n "${PEXELS_API_KEY:-}" ]] && have_pexels=1
[[ -n "${UNSPLASH_ACCESS_KEY:-}" ]] && have_unsplash=1
[[ -n "${PIXABAY_API_KEY:-}" ]] && have_pixabay=1

if (( !have_pexels && !have_unsplash && !have_pixabay )); then
  echo "No API keys set (PEXELS_API_KEY / UNSPLASH_ACCESS_KEY / PIXABAY_API_KEY). Nothing to do." >&2
  exit 1
fi

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# Each search_* fn prints up to N lines of: image_url<TAB>filename_stub<TAB>credit_line
search_pexels() {
  local query=$1 n=$2 encoded
  encoded=$(jq -rn --arg q "$query" '$q|@uri')
  curl -sS --fail-with-body -H "Authorization: $PEXELS_API_KEY" \
    "https://api.pexels.com/v1/search?query=$encoded&per_page=$n" |
  jq -r '.photos[] | [.src.large, ("pexels-" + (.id|tostring)), ("Photo by " + .photographer + " on Pexels — " + .url)] | @tsv'
}

search_unsplash() {
  local query=$1 n=$2 encoded
  encoded=$(jq -rn --arg q "$query" '$q|@uri')
  curl -sS --fail-with-body -H "Authorization: Client-ID $UNSPLASH_ACCESS_KEY" -H "Accept-Version: v1" \
    "https://api.unsplash.com/search/photos?query=$encoded&per_page=$n" |
  jq -r '.results[] | [.urls.regular, ("unsplash-" + .id), ("Photo by " + .user.name + " on Unsplash — " + .links.html)] | @tsv'
}

search_pixabay() {
  local query=$1 n=$2 encoded
  encoded=$(jq -rn --arg q "$query" '$q|@uri')
  curl -sS --fail-with-body \
    "https://pixabay.com/api/?key=$PIXABAY_API_KEY&q=$encoded&image_type=photo&per_page=$n" |
  jq -r '.hits[] | [.largeImageURL, ("pixabay-" + (.id|tostring)), ("Photo by " + .user + " on Pixabay — " + .pageURL)] | @tsv'
}

download_keyword() {
  local keyword=$1 slug dir credits
  slug=$(slugify "$keyword")
  dir="$out_root/$slug"
  mkdir -p "$dir"
  credits="$dir/CREDITS.txt"
  : > "$credits"

  local -a lines=()
  local per_source=$count
  ((have_pexels))   && mapfile -t -O "${#lines[@]}" lines < <(search_pexels "$keyword" "$per_source" | sed 's/^/pexels\t/')   || true
  ((have_unsplash)) && mapfile -t -O "${#lines[@]}" lines < <(search_unsplash "$keyword" "$per_source" | sed 's/^/unsplash\t/') || true
  ((have_pixabay))  && mapfile -t -O "${#lines[@]}" lines < <(search_pixabay "$keyword" "$per_source" | sed 's/^/pixabay\t/')  || true

  if [[ ${#lines[@]} -eq 0 ]]; then
    echo "  [$keyword] no results from any source" >&2
    return
  fi

  # Round-robin interleave by source so results are mixed, not one source then the next.
  local -a by_pexels=() by_unsplash=() by_pixabay=()
  local line src rest
  for line in "${lines[@]}"; do
    src=${line%%$'\t'*}
    rest=${line#*$'\t'}
    case $src in
      pexels)   by_pexels+=("$rest") ;;
      unsplash) by_unsplash+=("$rest") ;;
      pixabay)  by_pixabay+=("$rest") ;;
    esac
  done

  local saved=0 i=0
  local -a srcnames=(pexels unsplash pixabay)
  while (( saved < count )); do
    local progressed=0
    for src in "${srcnames[@]}"; do
      (( saved >= count )) && break
      local -n arr="by_$src"
      if (( ${#arr[@]} > 0 )); then
        rest=${arr[0]}
        arr=("${arr[@]:1}")
        IFS=$'\t' read -r url stub credit <<<"$rest"
        local ext=jpg
        [[ $url =~ \.(png|webp|jpg|jpeg)(\?|$) ]] && ext=${BASH_REMATCH[1]}
        local n; n=$(printf "%02d" $((saved + 1)))
        local dest="$dir/${n}-${stub}.${ext}"
        if curl -sSL --fail-with-body -o "$dest" "$url"; then
          echo "$dest — $credit" >> "$credits"
          saved=$((saved + 1))
          progressed=1
        else
          echo "  [$keyword] failed to download $url" >&2
        fi
      fi
    done
    (( progressed == 0 )) && break
  done

  echo "  [$keyword] saved $saved/$count -> $dir"
}

echo "Sources enabled: $((have_pexels)) pexels, $((have_unsplash)) unsplash, $((have_pixabay)) pixabay"
echo "Kaboompics is skipped (no public API) — download that one manually if needed."
mkdir -p "$out_root"

while IFS= read -r raw; do
  keyword="${raw%%#*}"
  keyword="$(echo "$keyword" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -z "$keyword" ]] && continue
  echo "Searching: $keyword"
  download_keyword "$keyword"
done < "$keywords_file"

echo "Done. Results in $out_root/"
