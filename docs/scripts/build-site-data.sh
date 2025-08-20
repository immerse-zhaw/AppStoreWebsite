#!/usr/bin/env bash
set -euo pipefail

# -------- Config --------
API_BASE="${API_BASE:-https://github.zhaw.ch/api/v3}"
PROJECTS_FILE="${PROJECTS_FILE:-docs/projects.json}"
OUT_FILE="${OUT_FILE:-docs/site-data.json}"
OWNER_DEFAULT="${OWNER_DEFAULT:-}"   # optional: set to your org, e.g. OWNER_DEFAULT=IMMERSE

# -------- Helpers --------
log()  { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }

need() { command -v "$1" >/dev/null || { echo "Missing dependency: $1" >&2; exit 1; }; }
need jq
need perl
[[ -n "${SITE_TOKEN:-}" ]] || { echo "Please: export SITE_TOKEN=your_PAT" >&2; exit 1; }

# Skip H1 title, stop at first H2 subtitle
extract_intro() {
  awk '
    BEGIN{inbody=0}
    {
      if (!inbody) { if ($0 ~ /^# /) next; inbody=1 }
      if ($0 ~ /^##[[:space:]]/) exit
      print
    }'
}

# First non-empty paragraph (separated by blank line)
first_paragraph() {
  awk -v RS= -v ORS='' 'NF{gsub(/\r/,""); print; exit}'
}

# Strip images so the text paragraph isn’t cluttered
strip_md_images() {
  sed -E 's/!\[[^]]*\]\([^)]*\)//g'
}

# Minimal inline Markdown → HTML (links, bold, italic)
md_inline_to_html() {
  perl -0777 -pe '
    # links: [text](url)
    s{\[([^\]]+)\]\(([^)]+)\)}{<a href="$2">$1</a>}g;

    # bold: **text** or __text__
    s{\*\*([^*]+)\*\*}{<strong>$1</strong>}g;
    s{__([^_]+)__}{<strong>$1</strong>}g;

    # italic: *text* or _text_ (avoid matching inside words/newlines)
    s{(?<!\*)\*([^*\n]+)\*(?!\*)}{<em>$1</em>}g;
    s{(?<!_)_([^_\n]+)_(?!_)}{<em>$1</em>}g;
  '
}

# Fetch JSON from GHES API
gh_get() {
  curl -sS -H "Authorization: Bearer $SITE_TOKEN" \
           -H "Accept: application/vnd.github+json" \
           "$API_BASE$1"
}

build_items() {
  jq -c '.[]' "$PROJECTS_FILE" | while IFS= read -r row; do
    owner="$(jq -r '(.owner // empty)' <<<"$row")"
    repo_raw="$(jq -r '.repo' <<<"$row")"
    web="$(jq -r '(.web // "")' <<<"$row")"

    if [[ "$repo_raw" == */* ]]; then
      owner="${repo_raw%%/*}"
      repo="${repo_raw#*/}"
    else
      repo="$repo_raw"
    fi

    if [[ -z "$owner" ]]; then
      if [[ -n "$OWNER_DEFAULT" ]]; then owner="$OWNER_DEFAULT"
      else warn "Missing owner for repo '$repo' (set OWNER_DEFAULT or add \"owner\" in projects.json)"; continue
      fi
    fi

    log "=========="
    log "Processing $owner/$repo"

    # Repo metadata
    repo_json="$(gh_get "/repos/$owner/$repo" || true)"
    name="$(jq -r --arg r "$repo" '.name // $r' <<<"$repo_json")"
    branch="$(jq -r '.default_branch // "main"' <<<"$repo_json")"
    log "Repo: $name (branch=$branch)"

    # README → intro → first paragraph
    blurb=""
    rd_json="$(gh_get "/repos/$owner/$repo/readme?ref=$branch" || true)"
    if [[ -n "$rd_json" && "$(jq -r '.content? // empty' <<<"$rd_json")" != "" ]]; then
      md="$(jq -r '.content' <<<"$rd_json" | tr -d '\n' | base64 --decode 2>/dev/null || true)"
      intro="$(printf "%s\n" "$md" | extract_intro)"
      para="$(printf "%s\n" "$intro" | strip_md_images | first_paragraph)"
      blurb="$(printf "%s" "$para" | md_inline_to_html)"
    fi
    if [[ -z "${blurb// /}" ]]; then
      blurb="$(jq -r '(.description // "")' <<<"$repo_json")"
    fi

    # Latest release (mac/windows)
    rel_json="$(gh_get "/repos/$owner/$repo/releases/latest" || true)"
    macUrl="$(jq -r '.assets[]?.browser_download_url | select(test("OSX|osx|Mac|mac|darwin|arm64|universal";"i"))' <<<"$rel_json" | head -n1)"
    winUrl="$(jq -r '.assets[]?.browser_download_url | select(test("Win|win|Windows|windows|x64|amd64";"i"))' <<<"$rel_json" | head -n1)"
    log "macUrl=${macUrl:-}"
    log "winUrl=${winUrl:-}"

    repoUrl="$(jq -r '.html_url // ""' <<<"$repo_json")"

    # Demo gif from assets
    demoGif=""
    asset_path="docs/assets/${name}Demo.gif"
    if [[ -f "$asset_path" ]]; then
      demoGif="assets/${name}Demo.gif"
      log "Found demo gif: $demoGif"
    else
      log "No demo gif for $name"
    fi

    jq -n \
      --arg name "$name" \
      --arg blurb "$blurb" \
      --arg mac "$macUrl" \
      --arg win "$winUrl" \
      --arg web "$web" \
      --arg repo "$repoUrl" \
      --arg demo "$demoGif" \
      '{name:$name, blurb:$blurb, macUrl:$mac, winUrl:$win, web:$web, repoUrl:$repo, demoGif:$demo}'
  done | jq -s '.'
}

tmp="$(mktemp)"
build_items > "$tmp"

if [[ ! -s "$tmp" ]] || [[ "$(jq 'length' "$tmp")" -eq 0 ]]; then
  echo "[ERROR] No project items were generated" >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$OUT_FILE"
log "Wrote $OUT_FILE"
