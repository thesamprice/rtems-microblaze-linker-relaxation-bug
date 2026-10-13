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
#   DEJAGNU_TREE=~/src/dejagnu DEJAGNU_BASE=origin/master \
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
# Order = what reviewers want: bug fixes first, prerequisites before their
# users, testsuite-only changes last.  Repo file numbers are bookkeeping.
series() {
  name=$1 tree=$2 base=$3 cover=$4; shift 4
  [ -n "$tree" ] || { echo "skip $name (no tree)"; return; }
  wt=$TMP/$name
  git -C "$tree" worktree add -q --detach "$wt" "$base"
  ( cd "$wt" && git am -q "$@" )
  rm -rf "$OUT/$name"; mkdir -p "$OUT/$name"
  n=$#
  # A cover letter whenever one is given, not only for a multi-patch series:
  # a single patch can still need one, and the dejagnu series is one patch
  # whose cover carries the open questions.
  if [ "$cover" != "-" ]; then
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
  # Reviewer notes: patches/<repo>/<stem>.notes is inserted after the "---"
  # line of the corresponding generated mail.  git am ignores everything
  # between "---" and the first "diff --git", so these reach reviewers but
  # never land in the commit message.  Source patches and generated mails are
  # in the same order, so zip them.
  i=0
  for src in "$@"; do
    i=$((i + 1))
    notes=${src%.patch}.notes
    [ -f "$notes" ] || continue
    gen=$(ls "$OUT/$name"/$(printf '%04d' "$i")-*.patch 2>/dev/null) || continue
    python3 - "$gen" "$notes" <<'PY'
import sys
gen, notes = sys.argv[1], sys.argv[2]
s = open(gen).read()
marker = "\n---\n"
i = s.index(marker) + len(marker)
open(gen, "w").write(s[:i] + open(notes).read().rstrip("\n") + "\n\n" + s[i:])
PY
    echo "  + notes from $(basename "$notes")"
  done
  git -C "$tree" worktree remove --force "$wt"
  echo "$name: $(ls "$OUT/$name" | wc -l | tr -d ' ') files on $(git -C "$tree" rev-parse --short "$base")"
}

B=${BINUTILS_TREE:-}; G=${GCC_TREE:-}; L=${GLIBC_TREE:-}; J=${DEJAGNU_TREE:-}

# 0004, 0010, 0011 and 0012 landed upstream 2026-09-24 as the v3 series and are
# no longer generated; see patches/binutils/landed/README.md.
series binutils        "$B" "${BINUTILS_BASE:-master}" "$P/binutils/0000-cover-letter.txt" \
  "$P"/binutils/0008-*.patch "$P"/binutils/0007-*.patch \
  "$P"/binutils/0006-*.patch "$P"/binutils/0009-*.patch "$P"/binutils/0003-*.patch
# The two relaxation patches live in their own directory and go as their own
# series: same file, same function, same two loops.  Keeping them out of the
# series above is deliberate -- that one is unrelated gas/eh_frame/PLT work,
# and bundling would split reviewer attention the way sending 0001 alone
# avoided.
series binutils-relax  "$B" "${BINUTILS_BASE:-master}" "$P/binutils-relax/0000-cover-letter.txt" \
  "$P"/binutils-relax/0001-*.patch "$P"/binutils-relax/0002-*.patch
# One patch, but it gets a cover letter: it is a work in progress, and the
# questions in the cover are the point of sending it.
series dejagnu         "$J" "${DEJAGNU_BASE:-master}" "$P/dejagnu/0000-cover-letter.txt" \
  "$P"/dejagnu/0001-*.patch
series gcc-0001        "$G" "${GCC_BASE:-master}"      - "$P"/gcc/0001-*.patch
series gcc-0002        "$G" "${GCC_BASE:-master}"      - "$P"/gcc/0002-*.patch
series glibc           "$L" "${GLIBC_BASE:-master}"    "$P/glibc/0000-cover-letter.txt" \
  "$P"/glibc/0001-*.patch "$P"/glibc/0003-*.patch "$P"/glibc/0005-*.patch \
  "$P"/glibc/0006-*.patch "$P"/glibc/0009-*.patch "$P"/glibc/0002-*.patch \
  "$P"/glibc/0004-*.patch "$P"/glibc/0007-*.patch "$P"/glibc/0008-*.patch
