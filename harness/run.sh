#!/bin/bash
# MicroBlaze toolchain + glibc test harness.  See README.md in this directory.
#
#   run.sh <stage>...      stages: fetch binutils binutils-check gcc glibc verify check results all
#
# Everything persistent lives under $WORK (sources, builds, installed
# toolchains, logs); the patch series is read from $REPO.  Both are normally
# Docker mounts, see README.md.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true

WORK=${WORK:-/work}
REPO=${REPO:-/repo}
JOBS=${JOBS:-$(nproc)}

GLIBC_REPO=${GLIBC_REPO:-https://sourceware.org/git/glibc.git}
GLIBC_COMMIT=${GLIBC_COMMIT:-10ed541ad1452ef6eb615e23af2e7a55fd62c513}     # master, 2026-08-25
BINUTILS_REPO=${BINUTILS_REPO:-https://sourceware.org/git/binutils-gdb.git}
BINUTILS_COMMIT=${BINUTILS_COMMIT:-6f24afa4391bd33f1263378280b99385d2c13055} # master, 2026-08-31
GCC_REPO=${GCC_REPO:-https://github.com/thesamprice/gcc.git}
GCC_COMMIT=${GCC_COMMIT:-95e1193774c67fe2e6acdeeeb404e20de747f93b}          # branch microblaze-fixes
BOOTLIN_URL=${BOOTLIN_URL:-https://toolchains.bootlin.com/downloads/releases/toolchains/microblazeel/tarballs/microblazeel--glibc--stable-2025.08-1.tar.xz}

# Unquoted on use so that the defaults expand as globs; override with a
# space-separated list of files, or an empty string for none.
BINUTILS_PATCHES=${BINUTILS_PATCHES-"$REPO/patches/binutils/000[6-9]-*.patch"}
GCC_PATCHES=${GCC_PATCHES-"$REPO/patches/gcc/000[1-2]-*.patch"}
GLIBC_PATCHES=${GLIBC_PATCHES-"$REPO/glibc-longjmp-chk/patches/000[1-7]-*.patch"}

TARGET=microblazeel-linux-gnu
TC=$WORK/tc
SYSROOT=$TC/microblazeel-buildroot-linux-gnu/sysroot
SRC=$WORK/src; BUILD=$WORK/build; OPT=$WORK/opt; LOG=$WORK/log
WRAP=$(dirname "$(readlink -f "$0")")/qemu-wrap.sh
RE=$OPT/binutils/bin/$TARGET-readelf
mkdir -p "$SRC" "$BUILD" "$OPT" "$LOG"

log() { echo "[$(date -u +%FT%TZ)] $*"; }
die() { log "ERROR: $*"; exit 1; }
run_logged() { # logfile cmd...   run a command, keep its output in a log, show the tail on failure
  local lf=$1; shift
  if ! "$@" > "$lf" 2>&1; then log "failed: $* (log: $lf)"; grep -n -E " error: |Error [0-9]+$|\*\*\*" "$lf" | head -10; return 1; fi
}

clone_at() { # repo commit dir
  # A pinned commit is not necessarily a ref tip, and neither sourceware nor
  # GitHub will serve an arbitrary SHA to a shallow "fetch <sha>".  So take a
  # blobless partial clone of all history (small: commits and trees only, blobs
  # arrive on checkout), which can then check out any commit.  Retry: these
  # large transfers drop their TLS connection under load.
  local repo=$1 commit=$2 dir=$3 try
  if [ -e "$dir/.git" ]; then
    if git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then log "$dir already cloned"; return; fi
    log "$dir exists but lacks $commit, refetching"; else log "cloning $repo @ ${commit:0:12} into $dir"; fi
  for try in 1 2 3 4 5; do
    rm -rf "$dir"
    if git -c http.postBuffer=524288000 clone -q --filter=blob:none "$repo" "$dir" \
       && git -C "$dir" checkout -q "$commit"; then return 0; fi
    log "clone attempt $try failed, retrying in $((try*20))s"; sleep $((try*20))
  done
  die "could not clone $repo @ $commit after 5 tries"
}
apply_patches() { # dir patches...
  local dir=$1; shift
  [ $# -gt 0 ] || return 0
  [ -e "$1" ] || die "no patches match: $*"
  if git -C "$dir" log -1 --format=%s | grep -q "^HARNESS-PATCHED$"; then log "$dir already patched"; return; fi
  log "applying $# patches in $dir"
  git -C "$dir" -c user.name=harness -c user.email=harness@localhost am -q "$@" || die "patches did not apply in $dir (git -C $dir am --abort to reset)"
  git -C "$dir" -c user.name=harness -c user.email=harness@localhost commit -q --allow-empty -m HARNESS-PATCHED
}

eh_stats() { # object...   how the exception tables of a shared object came out
  local f eh hdr lo sz n
  for f in "$@"; do
    [ -f "$f" ] || continue
    eh=$($RE -SW "$f" | grep -E " \.eh_frame " | awk '{print $8}')
    hdr=$($RE -x .eh_frame_hdr "$f" 2>/dev/null | sed -n 3p | awk '{print $2}')
    lo=$($RE -SW "$f" | grep -E " \.eh_frame " | awk '{print "0x"$4}')
    sz=$($RE -SW "$f" | grep -E " \.eh_frame " | awk '{print "0x"$6}')
    n=$($RE -rW "$f" | awk -v lo=$((lo)) -v hi=$((lo+sz)) '$3=="R_MICROBLAZE_REL"{a=strtonum("0x"$1); if (a>=lo && a<hi) c++} END{print c+0}')
    echo "   $f: .eh_frame flags=$eh hdr=$hdr dynamic-relocs-in-.eh_frame=$n FDEs=$($RE --debug-dump=frames "$f" 2>/dev/null | grep -c FDE)"
  done
}

stage_fetch() {
  if [ ! -x "$TC/bin/microblazeel-linux-gcc" ]; then
    log "downloading the Bootlin toolchain (sysroot, kernel headers, reference glibc)"
    wget -q "$BOOTLIN_URL" -O "$WORK/tc.tar.xz"
    mkdir -p "$TC" && tar -xJf "$WORK/tc.tar.xz" -C "$TC" --strip-components=1 && rm -f "$WORK/tc.tar.xz"
  fi
  clone_at "$BINUTILS_REPO" "$BINUTILS_COMMIT" "$SRC/binutils"; apply_patches "$SRC/binutils" $BINUTILS_PATCHES
  clone_at "$GCC_REPO" "$GCC_COMMIT" "$SRC/gcc";                apply_patches "$SRC/gcc" $GCC_PATCHES
  clone_at "$GLIBC_REPO" "$GLIBC_COMMIT" "$SRC/glibc";          apply_patches "$SRC/glibc" $GLIBC_PATCHES
  log "sources ready"
}

stage_binutils() {
  local B=$BUILD/binutils; mkdir -p "$B"; cd "$B"
  [ -f config.status ] || run_logged "$LOG/binutils-configure.log" "$SRC/binutils/configure" --target=$TARGET --prefix="$OPT/binutils" \
      --disable-gdb --disable-gdbserver --disable-sim --disable-gprofng --disable-nls
  run_logged "$LOG/binutils-make.log" make -j"$JOBS" all-gas all-ld all-binutils
  run_logged "$LOG/binutils-install.log" make install-gas install-ld install-binutils
  log "binutils installed: $("$OPT/binutils/bin/$TARGET-as" --version | head -1)"
}

stage_binutils_check() {
  # Patterns are relative to the testsuite root: "microblaze/*.exp" silently runs nothing.
  cd "$BUILD/binutils"
  make -C gas check RUNTESTFLAGS="gas/microblaze/*.exp gas/elf/*.exp gas/all/*.exp" > "$LOG/binutils-check-gas.log" 2>&1 || true
  make -C ld check RUNTESTFLAGS="ld-microblaze/microblaze.exp ld-elf/eh*.exp" > "$LOG/binutils-check-ld.log" 2>&1 || true
  for s in gas/testsuite/gas.sum ld/ld.sum; do echo "== $s"; grep -E "^# of|^(FAIL|ERROR|UNRESOLVED)" "$s" || echo "   (no summary: see $LOG)"; done
  echo "Expected on an unpatched tree too: gas/all diff1, simple-forward, forward and end fail for microblazeel."
}

stage_gcc() {
  # gcc's configure looks for objdump on PATH; without it the read-only
  # exception-table probe never runs and .eh_frame stays writable.
  export PATH=$OPT/binutils/bin:$PATH
  local B=$BUILD/gcc; mkdir -p "$B"; cd "$B"
  [ -f config.status ] || run_logged "$LOG/gcc-configure.log" "$SRC/gcc/configure" --target=$TARGET --prefix="$OPT/gcc" \
      --with-sysroot="$SYSROOT" --with-as="$OPT/binutils/bin/$TARGET-as" --with-ld="$OPT/binutils/bin/$TARGET-ld" \
      --enable-languages=c,c++ --disable-bootstrap --disable-multilib --disable-nls --disable-libsanitizer \
      --disable-libssp --disable-libquadmath --disable-libgomp --disable-libitm --disable-libvtv --disable-lto --disable-werror
  run_logged "$LOG/gcc-make.log" make -j"$JOBS"
  run_logged "$LOG/gcc-install.log" make install
  # glibc's configure asks gcc for objcopy, readelf and friends; gcc only
  # knows them under $prefix/$target/bin, so put the patched binutils there.
  mkdir -p "$OPT/gcc/$TARGET/bin"
  local t; for t in "$OPT/binutils/bin/$TARGET"-*; do ln -sf "$t" "$OPT/gcc/$TARGET/bin/${t##*/$TARGET-}"; done
  log "gcc installed: $("$OPT/gcc/bin/$TARGET-gcc" --version | head -1)"
  grep -h "HAVE_LD_RO_RW_SECTION_MIXING\|HAVE_GAS_CFI_DIRECTIVE" gcc/auto-host.h | sed 's/^/   /'
  eh_stats "$OPT/gcc/$TARGET/lib/libgcc_s.so.1"
}

stage_glibc() {
  local B=$BUILD/glibc; mkdir -p "$B"; cd "$B"
  [ -f config.status ] || run_logged "$LOG/glibc-configure.log" "$SRC/glibc/configure" --host=$TARGET --build=x86_64-linux-gnu --prefix=/usr \
      --with-headers="$SYSROOT/usr/include" --disable-werror --disable-nscd --disable-crypt \
      CC="$OPT/gcc/bin/$TARGET-gcc" CXX="$OPT/gcc/bin/$TARGET-g++"
  grep -h "assembler supports CFI" configure.log | sed 's/^/   /' || true
  # support/links-dso-program links libstdc++, which needs the libm.so.6 of
  # this very build; with -j that link can race ahead of math/.  Libraries first.
  run_logged "$LOG/glibc-make-lib.log" make -j"$JOBS" lib
  run_logged "$LOG/glibc-make.log" make -j"$JOBS"
  log "glibc built"
  eh_stats "$B/libc.so" "$B/elf/ld.so" "$B/math/libm.so"
}

wrapper_args() { echo "test-wrapper=$WRAP test-wrapper-env=$WRAP test-wrapper-env-only=$WRAP"; }

stage_verify() {
  # The quick version of the check: the tests that each glibc patch fixes.
  cd "$BUILD/glibc"; ulimit -c 0
  local W; W=$(wrapper_args)
  local list="debug:tst-longjmp_chk tst-longjmp_chk2 tst-longjmp_chk3 tst-backtrace4 tst-backtrace5 tst-backtrace6
              elf:tst-array1-cmp tst-unwind-main tst-addr1
              stdlib:tst-makecontext tst-setcontext tst-swapcontext1
              nptl:tst-cancelx4 tst-cleanupx4
              misc:tst-ldbl-errorfptr
              math:test-float-acos test-double-exp"
  # Ask for each test's .out file: that rule runs the test and writes the
  # .test-result, and it exists alike for plain, generated (math) and
  # tests-special (elf/tst-array1-cmp) tests, which a "tests=" override skips.
  local entry d tests t targets
  while read -r entry; do
    [ -n "$entry" ] || continue
    d=${entry%%:*}; tests=${entry#*:}; targets=
    for t in $tests; do rm -f "$d/$t.out" "$d/$t.test-result"; targets="$targets $BUILD/glibc/$d/$t.out"; done
    make -j"$JOBS" -k objdir="$BUILD/glibc" -C "$SRC/glibc/$d" $W $targets > "$LOG/verify-$d.log" 2>&1 || true
    for t in $tests; do printf '   %-32s %s\n' "$d/$t" "$(head -1 "$d/$t.test-result" 2>/dev/null || echo 'no result')"; done
  done <<< "$list"
}

stage_check() {
  cd "$BUILD/glibc"; ulimit -c 0
  local W; W=$(wrapper_args)
  rm -rf testroot.pristine testroot.root
  find . -name '*.test-result' -delete; find . -name '*.out' -newer config.status -delete
  log "full make check started (expect many hours under qemu-user)"
  make -j"$JOBS" -k check $W > "$LOG/check.log" 2>&1 || true
  # glibc orders nptl and rt after everything else; a failure earlier (the
  # zic data build hangs under qemu) skips them, so run them explicitly.
  local d; for d in nptl rt; do make -j"$JOBS" -k objdir="$BUILD/glibc" -C "$SRC/glibc/$d" tests $W > "$LOG/check-$d.log" 2>&1 || true; done
  log "full make check finished"
  stage_results
}

stage_results() {
  cd "$BUILD/glibc"
  local out=$LOG/results.txt d n f r t st fl
  {
    echo "# glibc $GLIBC_COMMIT + $(ls $GLIBC_PATCHES 2>/dev/null | wc -l) patches, built with gcc $GCC_COMMIT + $(ls $GCC_PATCHES 2>/dev/null | wc -l) patches and binutils $BINUTILS_COMMIT + $(ls $BINUTILS_PATCHES 2>/dev/null | wc -l) patches"
    echo "# $(qemu-microblazeel --version | head -1), $(date -u +%FT%TZ)"
    echo
    cat ./*/*.test-result | cut -d: -f1 | sort | uniq -c | grep -v "exit status"
    echo
    echo "## Per directory: FAIL/total"
    for d in */; do d=${d%/}; n=$(ls "$d"/*.test-result 2>/dev/null | wc -l); [ "$n" -gt 0 ] || continue
      f=$(grep -l "^FAIL" "$d"/*.test-result 2>/dev/null | wc -l); printf "%-17s %d/%-4d\n" "$d" "$f" "$n"; done
    echo
    echo "## Failures: test | exit status | first line of output"
    for r in $(grep -l "^FAIL" ./*/*.test-result | sort); do t=${r#./}; t=${t%.test-result}; st=$(sed -n 2p "$r")
      fl=$(grep -v "^\s*$" "$t.out" 2>/dev/null | head -1 | cut -c1-90); echo "$t | $st | $fl"; done
  } > "$out"
  sed -n 1,8p "$out"
  log "full table: $out"
}

[ $# -gt 0 ] || { sed -n 2,6p "$0"; exit 1; }
for stage in "$@"; do
  case $stage in
    fetch) stage_fetch ;;
    binutils) stage_binutils ;;
    binutils-check) stage_binutils_check ;;
    gcc) stage_gcc ;;
    glibc) stage_glibc ;;
    verify) stage_verify ;;
    check) stage_check ;;
    results) stage_results ;;
    all) stage_fetch; stage_binutils; stage_gcc; stage_glibc; stage_check ;;
    *) die "unknown stage $stage" ;;
  esac
done
log "done: $*"
