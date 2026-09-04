#!/bin/sh
# build-test.sh -- cross-compile sigunwind.c with the patched toolchain.
# Set CC to your patched microblazeel-linux-gnu-gcc (the one built from
# harness/run.sh, so it carries gcc patch 0001 in its libgcc).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-microblazeel-linux-gnu-gcc}
MODE=${MODE:-segv}          # segv (fault inside leaf) or alrm (SIGALRM via raise)
def=; [ "$MODE" = alrm ] && def=-DMODE_ALRM
echo "== $CC ($MODE), static"
$CC -O1 -g -static -fasynchronous-unwind-tables $def "$here/sigunwind.c" -o "$here/sigunwind"
file "$here/sigunwind" 2>/dev/null | sed 's/^/  /'
echo "built $here/sigunwind"
