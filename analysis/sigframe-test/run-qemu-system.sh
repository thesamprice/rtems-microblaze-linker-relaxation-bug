#!/bin/sh
# run-qemu-system.sh -- boot a MicroBlaze kernel under qemu-system and run the
# signal-frame unwinder test as init, then report PASS/FAIL from the serial log.
#
# Unlike qemu-user (the build harness), qemu-system runs a REAL kernel, so the
# real struct rt_sigframe is used and your patches/linux/ signal-frame patches
# take effect -- which is what gcc patch 0001 must be validated against.
#
# Usage:
#   KERNEL=path/to/simpleImage.s3adsp1800 ./run-qemu-system.sh [test-binary]
# Knobs (env):
#   KERNEL   (required) kernel image for the machine
#   DTB      device tree blob, if your kernel needs one passed separately
#   MACHINE  qemu -M value            (default petalogix-s3adsp1800)
#   CONSOLE  kernel console= value    (default ttyUL0)
#   QEMU     qemu-system binary       (default qemu-system-microblazeel)
#   TIMEOUT  seconds                  (default 60)
# The test binary must be STATIC (it carries the patched libgcc unwinder); build
# it with build-test.sh.  Default binary: ./sigunwind next to this script.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
TEST=${1:-$here/sigunwind}
MACHINE=${MACHINE:-petalogix-s3adsp1800}
CONSOLE=${CONSOLE:-ttyUL0}
QEMU=${QEMU:-qemu-system-microblazeel}
TIMEOUT=${TIMEOUT:-60}
: "${KERNEL:?set KERNEL=path/to/kernel image}"

[ -f "$TEST" ] || { echo "no test binary at $TEST (run build-test.sh first)"; exit 2; }
file "$TEST" 2>/dev/null | grep -q "statically linked" || \
  echo "warning: $TEST is not static; the patched libgcc must be reachable on the target"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# minimal initramfs: the test runs as /init (PID 1) and powers off when done
cp "$TEST" "$work/init"
chmod +x "$work/init"
( cd "$work" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$work/initramfs.cpio.gz"

log="$work/serial.log"
echo "== booting $MACHINE, kernel=$KERNEL${DTB:+, dtb=$DTB}, test=$TEST"
set +e
timeout "$TIMEOUT" "$QEMU" -M "$MACHINE" -kernel "$KERNEL" \
  ${DTB:+-dtb "$DTB"} \
  -initrd "$work/initramfs.cpio.gz" \
  -append "console=$CONSOLE rdinit=/init" \
  -nographic -no-reboot -serial mon:stdio </dev/null 2>&1 | tee "$log"
set -e

echo "== result:"
if grep -q "^RESULT: PASS" "$log"; then
  grep "^RESULT:" "$log"; echo "gcc 0001: signal-frame unwinding works in this kernel/libc."; exit 0
elif grep -q "^RESULT: FAIL" "$log"; then
  grep -A0 "^RESULT:" "$log"; grep -E "expect|captured|markers" "$log" | tail -12
  echo "gcc 0001: signal-frame unwinding is WRONG for this kernel/libc -- see the frame dump above."; exit 1
else
  echo "no RESULT line -- the test did not run to completion."
  echo "  * check the kernel booted and reached init (console=$CONSOLE right?)"
  echo "  * a kernel with a built-in initramfs may ignore -initrd; bake the test into your rootfs and run it there instead"
  tail -20 "$log"; exit 3
fi
