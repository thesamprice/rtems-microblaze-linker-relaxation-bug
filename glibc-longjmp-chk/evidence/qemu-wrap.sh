#!/bin/bash
# glibc test-wrapper for qemu-user.
# - leading VAR=value args (test-wrapper-env convention) go to the guest via
#   qemu -E, never into this shell's own environment: LD_TRACE_LOADED_OBJECTS=1
#   exported here would make the host loader trace qemu itself
# - MicroBlaze ELF programs run under qemu-microblazeel; anything else (host
#   tools such as cp that glibc's testroot recipe routes through the wrapper)
#   runs natively with those variables in its environment
# - qemu-microblazeel under Rosetta drops the guest's argv[0] because the host
#   auxv AT_FLAGS carries binfmt_misc's preserve-argv0 bit; compensate by
#   passing the program path twice.
# - every guest execution is capped at 10 minutes: tests that predate
#   support/test-driver.c (elf/reldep6, gmon/tst-sprofil, the zic data build
#   in timezone/) have no timeout of their own and can hang qemu-user forever,
#   stalling the whole suite.
envs=()
while [ $# -gt 0 ]; do case "$1" in *=*) envs+=("$1"); shift;; *) break;; esac; done
prog=$1
if [ "${prog#/}" = "$prog" ]; then prog=$(command -v "$prog" 2>/dev/null || echo "$prog"); fi
if head -c 20 "$prog" 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46.*bd00$' ; then
  qargs=(); for e in "${envs[@]}"; do qargs+=(-E "$e"); done
  exec timeout -k 10 600 qemu-microblazeel "${qargs[@]}" "$1" "$@"
fi
exec env "${envs[@]}" "$@"
