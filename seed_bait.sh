#!/usr/bin/env bash
# seed bait files into decoy repos using your own `gh auth`. run locally, one time. Give each decoy its OWN canarytoken so an alert points back at one repo.

#   ./seed_bait.sh owner/repo dir    one repo from dir
#   ./seed_bait.sh --map bait        every bait/<org>/<repo>/ from its own dir

set -euo pipefail

# a few plain messages so the pushes don't all read the same
msgs=(
  "update config"
  "sync env defaults"
  "bump deps"
  "fix registry url"
  "tidy credentials"
  "adjust ci settings"
  "cleanup"
  "rotate creds"
  "update lockfile"
)

seed() {
  repo=$1
  dir=${2%/}
  find "$dir" -type f | while read -r f; do
    path=${f#$dir/}
    msg=${msgs[RANDOM % ${#msgs[@]}]}
    sha=$(gh api "repos/$repo/contents/$path" --jq .sha 2>/dev/null || true)
    gh api --method PUT "repos/$repo/contents/$path" \
      -f message="$msg" \
      -f content="$(openssl base64 -A -in "$f")" \
      ${sha:+-f sha="$sha"} >/dev/null
    echo "seeded $repo:$path"
  done
}

if [ "${1:-}" = "--map" ]; then
  root=${2%/}
  for d in "$root"/*/*/; do
    repo=${d#$root/}
    seed "${repo%/}" "$d"
  done
else
  seed "$1" "$2"
fi
