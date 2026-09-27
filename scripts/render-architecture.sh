#!/bin/sh
# Regenerate site/architecture.html from site/motita-arch.json.
#
# The diagram is a BUILD ARTIFACT, not a hand-written page: the spec is the
# source and this script is how it becomes HTML. It exists so the diagram can be
# rebuilt after `curator`, a new package or a moved file, without anyone having
# to remember the archify invocation and the fact that the render comes back in
# archify's own palette until scripts/apply-archify-theme.sh re-themes it.
#
# It is deliberately NOT wired into `make` or CI. Regenerating changes an 800 KB
# artifact whose diff is unreviewable, and the diagram should change when the
# architecture does - a decision a person makes - not on every commit.
#
# Usage: scripts/render-architecture.sh [--check]
#   (no args)  render and re-theme site/architecture.html in place
#   --check    render to a temp file, validate, and FAIL if the committed
#              artifact does not match; nothing is written
#
# Requires the archify skill. Override its location with ARCHIFY_SKILL.
# Exit codes: 0 ok · 1 the render, the validation or the comparison failed
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

archify="${ARCHIFY_SKILL:-$HOME/.hermes/skills/creative/archify}"
spec="site/motita-arch.json"
out="site/architecture.html"

if [ ! -f "$spec" ]; then
  printf 'error: %s is missing\n' "$spec" >&2
  exit 1
fi
if [ ! -f "$archify/bin/archify.mjs" ]; then
  printf 'error: the archify skill is not at %s (set ARCHIFY_SKILL)\n' "$archify" >&2
  exit 1
fi

# The spec pins meta.repository.revision, and archify verifies every
# sources.path against the checkout at that revision. A stale pin means the
# diagram silently describes code from an old commit, so keep it at HEAD.
head_sha="$(git rev-parse HEAD)"
pinned="$(python3 -c "
import json
print(json.load(open('$spec'))['meta'].get('repository',{}).get('revision',''))
")"
if [ "$pinned" != "$head_sha" ]; then
  printf 'error: %s pins revision %s but HEAD is %s\n' "$spec" "${pinned:0:12}" "${head_sha:0:12}" >&2
  printf '       update meta.repository.revision before rendering: the diagram\n' >&2
  printf '       must cite the code it was drawn from.\n' >&2
  exit 1
fi

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

# Render to a temp file so --check never touches the committed artifact.
tmp="$(mktemp "${TMPDIR:-/tmp}/motita-arch.XXXXXX.html")"
# mktemp creates the file; archify writes the path itself, so clear it.
: > "$tmp"

node "$archify/bin/archify.mjs" render architecture "$spec" "$tmp" \
  --repo-root . --quality standard >/dev/null

# The renderer's own palette is wrong on purpose for this site: the spec schema
# has no colour field, so the product's tokens are applied afterwards.
./scripts/apply-archify-theme.sh "$tmp" >/dev/null

if [ "$check_only" -eq 1 ]; then
  if cmp -s "$tmp" "$out"; then
    printf 'architecture.html is up to date with %s\n' "$spec"
    rm -f "$tmp"
    exit 0
  fi
  printf 'error: %s does not match a fresh render of %s\n' "$out" "$spec" >&2
  printf '       run scripts/render-architecture.sh to rebuild it.\n' >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$out"
printf 'rendered %s (%s bytes)\n' "$out" "$(wc -c < "$out" | tr -d ' ')"
