#!/bin/sh
# Every local reference in site/ resolves inside site/, and the installer the
# site advertises is actually shipped.
#
# site/ is uploaded ON ITS OWN, so a reference that works locally because
# docs/ or web/public/ happens to sit beside the page is dead in production
# while looking perfect in a checkout. This is the local half of the same
# check the pages workflow runs before uploading; keeping both means the
# deploy cannot be the first thing that notices.
#
# Two kinds of reference, and they fail differently:
#
#   href/src  a dead one is a 404 the reader sees.
#   url(...)  a dead one is SILENT. The fonts are referenced from CSS, so a
#             missing file does not 404 - the page renders every heading in
#             the fallback face, all 200s, and looks merely "a bit off".
#             That is the one worth a gate.
#
# Then the installer, which is a different question from a reference: the page
# does not LINK site/install.sh, it tells the reader to CURL it. A script that
# is not shipped - or that drifted from scripts/install.sh - cannot be caught by
# looking for dead links, and it is the one command whose failure the user
# experiences directly, in their own shell.
#
# Exit codes: 0 everything checks out · 1 a reference is dead or the installer is wrong.
set -eu

root="${1:-site}"

if [ ! -d "$root" ]; then
  printf 'error: %s is not a directory\n' "$root" >&2
  exit 1
fi

# --- the published installer --------------------------------------------------
# Resolved before cd, because the comparison is against the repo's scripts/.
# Skipped when the caller points at some other tree (a scratch copy for probing
# the reference check), which is why it keys off the default root rather than
# hardcoding site/.
if [ "$root" = site ]; then
  if [ ! -f site/install.sh ]; then
    printf 'error: site/install.sh is missing, but the site advertises https://madkoding.github.io/motita/install.sh\n' >&2
    exit 1
  fi
  # Byte-identical: the published copy is what `curl | sh` runs, and a drifted
  # copy is the entire risk of publishing one.
  if ! cmp -s scripts/install.sh site/install.sh; then
    printf 'error: site/install.sh has drifted from scripts/install.sh\n' >&2
    printf '       fix it with a copy, not an edit:  cp scripts/install.sh site/install.sh\n' >&2
    exit 1
  fi
  # A CRLF in a script piped to `sh` fails on the target in a way that reads as
  # a syntax error in a file the user never wrote.
  if grep -qU "$(printf '\r')" site/install.sh; then
    printf 'error: site/install.sh contains CR characters; it is piped to sh and must use Unix line endings\n' >&2
    exit 1
  fi
  if ! dash -n site/install.sh 2>/dev/null && ! sh -n site/install.sh 2>/dev/null; then
    printf 'error: site/install.sh does not parse as sh\n' >&2
    exit 1
  fi
  printf 'the published installer is shipped and parses as sh\n'
fi

cd "$root"

missing=0
checked=0

# --- href / src -------------------------------------------------------------
# A query and a fragment are stripped first: neither is part of the resource
# path, so `architecture.html?theme=dark` is served by architecture.html and a
# checker that kept the query would call a working reference dead - failing in
# the safe direction, which is the same as not checking.
for f in $(grep -rhoE '(href|src)="[^"]+"' . \
           | sed -E 's/.*="([^"]+)"/\1/' \
           | grep -vE '^(https?:|mailto:|#|data:)' \
           | sed -E 's/[?#].*$//' \
           | sort -u); do
  checked=$((checked + 1))
  if [ ! -e "$f" ]; then
    printf 'missing: %s (referenced by href/src)\n' "$f" >&2
    missing=1
  fi
done

# --- CSS url() --------------------------------------------------------------
# Both quote styles and no quotes at all, because the page uses all three:
# the font faces use url(fonts/x.woff2) and the icon fallback is a data: URI.
for f in $(grep -rhoE "url\((['\"]?)[^)'\"]+\1\)" --include='*.html' . \
           | sed -E "s/^url\((['\"]?)([^)'\"]+)\1\)$/\2/" \
           | grep -vE '^(https?:|data:|#)' \
           | sed -E 's/[?#].*$//' \
           | sort -u); do
  checked=$((checked + 1))
  if [ ! -e "$f" ]; then
    printf 'missing: %s (referenced by CSS url())\n' "$f" >&2
    missing=1
  fi
done

# A check that examined nothing is not a pass: it means the pattern stopped
# matching, and it would keep saying "ok" while the site lost its references.
if [ "$checked" -eq 0 ]; then
  printf 'error: no local references found in %s, so nothing was checked\n' "$root" >&2
  exit 1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

printf 'every local reference resolves (%s checked)\n' "$checked"
