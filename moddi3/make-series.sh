#!/bin/sh
# make-series.sh -- regenerate moddi3/patches/ from the sources in this directory.
#
#   GCC_TREE=~/src/gcc GCC_BASE=<commit> ./make-series.sh
#
# 1/2 and 2/2 are ALTERNATIVES, so they are not a linear series: each is
# committed on the same base and formatted on its own, then numbered by hand.
# That is why this does not use git format-patch's --cover-letter, which would
# emit a diffstat for applying both.
#
# Sources, all in this directory:
#   harness/moddi3-noquo.S   the file 1/2 installs
#   messages/0001.msg        1/2's commit message (first line = subject)
#   messages/0002.msg        2/2's commit message
#   messages/cover.txt       the cover letter (first line = subject)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${GCC_TREE:?set GCC_TREE to a gcc git checkout}"
BASE=${GCC_BASE:-8361264a1}
OUT=$here/patches
TMP=${TMPDIR:-/tmp}/mb-moddi3.$$
trap 'for w in a b t; do
        git -C "$GCC_TREE" worktree remove --force "$TMP/$w" 2>/dev/null || :
      done
      rm -rf "$TMP"' EXIT
mkdir -p "$TMP" "$OUT"

commit () {  # commit <worktree> <name> <email> <message-file>
  git -C "$1" add -A
  git -C "$1" -c user.name="$2" -c user.email="$3" \
      commit -q --author="$2 <$3>" -F "$4"
}

# 1/2 -- Ramin's fix to the assembly.
git -C "$GCC_TREE" worktree add -q --detach "$TMP/a" "$BASE"
cp "$here/harness/moddi3-noquo.S" "$TMP/a/libgcc/config/microblaze/moddi3.S"
commit "$TMP/a" 'Sam Price' 'thesamprice@gmail.com' "$here/messages/0001.msg"
git -C "$TMP/a" format-patch -q --subject-prefix='PATCH 1/2' -o "$OUT" -1
git -C "$GCC_TREE" worktree remove --force "$TMP/a"

# 2/2 -- delete the assembly, on the same unpatched base.
git -C "$GCC_TREE" worktree add -q --detach "$TMP/b" "$BASE"
git -C "$TMP/b" rm -q libgcc/config/microblaze/moddi3.S
python3 - "$TMP/b/libgcc/config/microblaze/t-microblaze" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'LIB2FUNCS_EXCLUDE += _divsi3 _modsi3 _moddi3 _mulsi3 _udivsi3 _umodsi3'
new = 'LIB2FUNCS_EXCLUDE += _divsi3 _modsi3 _mulsi3 _udivsi3 _umodsi3'
assert s.count(old) == 1, 'LIB2FUNCS_EXCLUDE line not found verbatim'
s = s.replace(old, new)
add = [l for l in s.splitlines(True) if 'moddi3.S' in l]
assert len(add) == 1, 'expected one LIB2ADD moddi3.S line, got %r' % add
open(p, 'w').write(s.replace(add[0], ''))
PY
commit "$TMP/b" 'Sam Price' 'thesamprice@gmail.com' "$here/messages/0002.msg"
git -C "$TMP/b" format-patch -q --subject-prefix='PATCH 2/2' -o "$OUT" -1
mv "$OUT"/0001-microblaze-use-the-generic-* \
   "$(echo "$OUT"/0001-microblaze-use-the-generic-* | sed "s|/0001-|/0002-|")"

# A standalone testsuite patch, independent of both 1/2 and 2/2: it tests the
# C semantics, so it applies whichever fix is taken, and it is not MicroBlaze
# specific.  Kept out of the numbering for that reason.
git -C "$GCC_TREE" worktree add -q --detach "$TMP/t" "$BASE"
cp "$here/tests/divmod-2.c" \
   "$TMP/t/gcc/testsuite/gcc.c-torture/execute/divmod-2.c"
commit "$TMP/t" 'Sam Price' 'thesamprice@gmail.com' "$here/messages/0003-test.msg"
rm -rf "$OUT-test"; mkdir -p "$OUT-test"
git -C "$TMP/t" format-patch -q -o "$OUT-test" -1
git -C "$GCC_TREE" worktree remove --force "$TMP/t"

# 0/2 -- the cover letter, written from messages/cover.txt.
python3 - "$OUT" "$here/messages/cover.txt" <<'PY'
import glob, re, sys
out, cov = sys.argv[1], sys.argv[2]
one = open(glob.glob(out + "/0001-*.patch")[0]).read()
frm = re.search(r"^From: .*$", one, re.M).group(0)
date = re.search(r"^Date: .*$", one, re.M).group(0)
tail = re.search(r"^-- \n.*$", one, re.M | re.S).group(0)
subj, body = open(cov).read().split("\n\n", 1)
open(out + "/0000-cover-letter.patch", "w").write(
    "From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001\n"
    + frm + "\n" + date + "\n"
    + "Subject: [PATCH 0/2] " + subj.strip() + "\n\n"
    + body.rstrip("\n") + "\n\n" + tail)
PY
echo "patches/ regenerated on $(git -C "$GCC_TREE" rev-parse --short "$BASE"):"
ls -1 "$OUT"
