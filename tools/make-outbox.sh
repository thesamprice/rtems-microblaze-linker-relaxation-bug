#!/bin/sh
# make-outbox.sh -- turn patches/<repo>/ into mailing-list-ready series.
#
# For each series: check out the upstream base in a throwaway worktree, git am
# the patches in order (so every patch is verified to apply on top of the
# previous one), then git format-patch them back out with standard
# [PATCH n/N] numbering and, for series of more than one patch, a
# [PATCH 0/N] cover letter filled from patches/<repo>/0000-cover-letter.txt
# (first line = subject, rest = body).  Output goes to outbox/<series>/,
# ready for: git send-email --to=... outbox/<series>/*.patch
#
#   BINUTILS_TREE=~/src/binutils-gdb BINUTILS_BASE=origin/master \
#   GCC_TREE=~/src/gcc GCC_BASE=origin/master \
#   GLIBC_TREE=~/src/glibc GLIBC_BASE=origin/master \
#   tools/make-outbox.sh
#
# A tree that is unset is skipped.  Bases default to the pinned commits in
# harness/run.sh's spirit: whatever "master" resolves to in that tree.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
P=$here/patches; OUT=$here/outbox
TMP=${TMPDIR:-/tmp}/mb-outbox.$$
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

# series <name> <tree> <base> <cover-or-"-"> <patch>...
series() {
  name=$1 tree=$2 base=$3 cover=$4; shift 4
  [ -n "$tree" ] || { echo "skip $name (no tree)"; return; }
  wt=$TMP/$name
  git -C "$tree" worktree add -q --detach "$wt" "$base"
  ( cd "$wt" && git am -q "$@" )
  rm -rf "$OUT/$name"; mkdir -p "$OUT/$name"
  n=$#
  if [ "$n" -gt 1 ]; then
    ( cd "$wt" && git format-patch -q --cover-letter -o "$OUT/$name" "$base" )
    cl=$OUT/$name/0000-cover-letter.patch
    subj=$(sed -n 1p "$cover"); body=$(sed '1,2d' "$cover")
    python3 - "$cl" "$subj" "$body" <<'PY'
import sys
p,subj,body=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(p).read()
s=s.replace("*** SUBJECT HERE ***",subj).replace("*** BLURB HERE ***",body)
open(p,"w").write(s)
PY
  else
    ( cd "$wt" && git format-patch -q -o "$OUT/$name" -1 )
  fi
  git -C "$tree" worktree remove --force "$wt"
  echo "$name: $(ls "$OUT/$name" | wc -l | tr -d ' ') files on $(git -C "$tree" rev-parse --short "$base")"
}

B=${BINUTILS_TREE:-}; G=${GCC_TREE:-}; L=${GLIBC_TREE:-}
series binutils        "$B" "${BINUTILS_BASE:-master}" "$P/binutils/0000-cover-letter.txt" \
  "$P"/binutils/0003-*.patch "$P"/binutils/0004-*.patch "$P"/binutils/0006-*.patch \
  "$P"/binutils/0007-*.patch "$P"/binutils/0008-*.patch "$P"/binutils/0009-*.patch \
  "$P"/binutils/0010-*.patch
series binutils-dwarf2 "$B" "${BINUTILS_BASE:-master}" - "$P"/binutils/0005-*.patch
series gcc-0001        "$G" "${GCC_BASE:-master}"      - "$P"/gcc/0001-*.patch
series gcc-0002        "$G" "${GCC_BASE:-master}"      - "$P"/gcc/0002-*.patch
series glibc           "$L" "${GLIBC_BASE:-master}"    "$P/glibc/0000-cover-letter.txt" \
  "$P"/glibc/000[1-9]-*.patch
