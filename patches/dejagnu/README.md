# dejagnu: a MicroBlaze QEMU baseboard

One patch, sent as a work in progress. It adds `baseboards/microblaze-qemu.exp`
so that MicroBlaze gets execution testing rather than compile-only coverage.

The board is the same shape as DejaGnu's other 46 `*-sim` boards: libgloss and
newlib supply the crt0, linker script, C library and syscalls, so it is the
four `*_flags` procs plus `ldscript ""` and the three things QEMU needs that a
simulator does not. The working copy, with its `setup.sh` and the measurements,
is [`../../dejagnu/microblaze-qemu/`](../../dejagnu/microblaze-qemu/); this
directory holds only what goes on the wire.

| file | lands at |
|---|---|
| the board | `baseboards/microblaze-qemu.exp` |
| the UART driver | `microblaze-qemu-libxil.c`, beside `testglue.c` |
| the runner | `contrib/microblaze-qemu-run` |

The cover letter puts three questions to reviewers: where the runner belongs,
whether the UART driver belongs in DejaGnu at all or in libgloss, and whether
four environment variables is too many.

## Status

v1 was written against DejaGnu `de0667b` (2026-07-02); the patch here is
v2, against `04e4201`. **v1 was sent 2026-10-12**, message-id
`<20261013014353.95350-1-thesamprice@gmail.com>`, to Michael Eager, Neal
Frager, Jeff Law and the author — not to `dejagnu@gnu.org`: it is a work in
progress, and Jeff may want to try it before the `__moddi3` fix lands.
`--suppress-cc=all` with all four in `--to`, because `sendemail.suppresscc`
is `self` here and would otherwise drop the author's own copy.

**v2 sent 2026-10-31**, message-id
`<20261031040016.82868-1-thesamprice@gmail.com>`, in reply to v1, to Michael
Eager with Neal Frager and the author in Cc. It is v1 rebased on DejaGnu
`04e4201`; only the ChangeLog context changed. The `.notes` file is the
reply to Michael's question about `make check` in binutils: the board does
nothing there, because ld's testsuite never links `testglue.c`, so its
execution probe gets no status line and every run test is UNSUPPORTED.

**Needs `patches/binutils-relax/0001`** or `MB_NO_RELAX=-Wl,--no-relax`.
Without one of them `testglue.c`'s `__wrap_exit` resolves before its own first
instruction and every execution test reports 2.

Measured on a combined tree of gcc trunk 17.0.0, newlib and libgloss from
sourceware, and binutils 2.47.50: eight `gcc.c-torture/execute` tests over all
seven torture levels, 53 clean compiles, and the only failures `pr50865.c` and
`arith-rand-ll.c`, both of which are `__moddi3` in trunk's libgcc and both of
which pass with the fix linked ahead. `printf-1.c` and `pr50865.c` were re-run
on the patch exactly as sent.

## Generating and sending

```sh
DEJAGNU_TREE=~/src/dejagnu DEJAGNU_BASE=origin/master ./tools/make-outbox.sh
python3 tools/check-patch-style.py patches/dejagnu
git send-email --confirm=never outbox/dejagnu/*.patch --to=... --cc=...
```

`outbox/dejagnu/` is generated; never hand-edit it. The message and diff live
here, and [`../STYLE.md`](../STYLE.md) is what they are written to.

**Add your own `Signed-off-by:` before sending it to the list.** It is a
statement about provenance and is deliberately not generated.
