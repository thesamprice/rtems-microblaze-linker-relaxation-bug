# Test harness: MicroBlaze binutils + gcc + glibc under qemu-user

One container, one script, reproduces the "round four" configuration from
`../glibc-longjmp-chk/README.md`: binutils master with `patches/binutils/0006`
to `0009`, gcc (the `microblaze-fixes` branch of thesamprice/gcc) with
`patches/gcc/0001` and `0002`, and glibc master with the seven patches in
`glibc-longjmp-chk/patches/`, then glibc's full `make check` run through
`qemu-microblazeel`.

## Run it

```sh
docker build -t mb-harness harness
docker volume create mbwork
docker run --init --rm -v mbwork:/work -v "$PWD":/repo:ro mb-harness all
```

`all` is `fetch binutils gcc glibc check`. Stages can be run one at a time
and rerun; each one is skipped or resumed where that is cheap (`configure`
is not rerun if `config.status` exists, sources are not recloned, patches are
not reapplied).

| Stage | What it does | Time on an M-series Mac (amd64 under Rosetta) |
|---|---|---|
| `fetch` | Bootlin toolchain (sysroot and kernel headers) into `/work/tc`; git clone of the three sources at the pinned commits into `/work/src`; `git am` of the patch series | 5 min |
| `binutils` | gas, ld, binutils to `/work/opt/binutils` | 10 min |
| `binutils-check` | gas and ld testsuites for MicroBlaze | 3 min |
| `gcc` | C and C++ to `/work/opt/gcc`, using the patched gas and ld, with the binutils symlinked where gcc and glibc's configure look for them | 2 h |
| `glibc` | to `/work/build/glibc`, compiled with that gcc; prints the `.eh_frame` state of `libc.so`, `ld.so`, `libm.so` | 30 min |
| `verify` | the specific tests each patch fixes, about 20 of them | 5 min |
| `check` | full `make check` plus `nptl` and `rt`, then `results` | 10 to 12 h |
| `results` | `/work/log/results.txt`: totals, per-directory counts, every failure with its first output line | seconds |

Logs go to `/work/log/`. To look around inside the volume:
`docker run --init --rm -it -v mbwork:/work -v "$PWD":/repo:ro --entrypoint bash mb-harness`.

## Knobs

Environment variables, all optional: `JOBS` (default `nproc`), the commits
`GLIBC_COMMIT`, `BINUTILS_COMMIT`, `GCC_COMMIT` and repositories
`GLIBC_REPO`, `BINUTILS_REPO`, `GCC_REPO`, and the patch lists
`GLIBC_PATCHES`, `BINUTILS_PATCHES`, `GCC_PATCHES` (space-separated files, or
empty for an unpatched tree). To test a different patch set, remove the
affected source tree (`rm -rf /work/src/glibc`) and rerun `fetch`; to iterate
on a source tree directly, edit under `/work/src` and rerun the build stage.

## Things this harness gets right that cost time before

- **Build on the container's own filesystem.** `/work` must be a Docker
  volume, not a bind mount from macOS: glibc writes `stamp.os` and `stamp.oS`
  side by side, and a case-insensitive mount makes the build fail late with a
  garbled `ar` object list.
- **`--init`.** Tests that fork leave orphaned qemu guests behind when the
  wrapper's 10 minute cap kills the parent; without an init process they pile
  up as zombies under a `sleep infinity` PID 1.
- **qemu under Rosetta drops the guest's argv[0]** because the host auxv
  `AT_FLAGS` carries binfmt_misc's preserve-argv0 bit. `qemu-wrap.sh` passes
  the program path twice. About 140 tests that spawn or re-exec guests still
  fail from this on a Mac; they pass on a Linux host.
- **gcc must find objdump at configure time.** Otherwise its read-only
  exception-table probe never runs, `HAVE_LD_RO_RW_SECTION_MIXING` stays
  unset and every `.eh_frame` is emitted writable regardless of the encoding.
- **glibc's configure asks gcc for objcopy and readelf.** gcc only reports
  tools installed under `$prefix/$target/bin`; the `gcc` stage symlinks the
  patched binutils there. Without it glibc silently uses the host's tools and
  fails at `libc_pic.os.clean`.
- **`support/links-dso-program` races `math/`** under `-j`: it links
  `libstdc++`, which needs `libm.so.6` from the build itself. The `glibc`
  stage builds `lib` before the rest.
- **runtest patterns are relative to the testsuite root**:
  `gas/microblaze/*.exp`, not `microblaze/*.exp`, which runs nothing and
  reports nothing.

## Reading the results

`results.txt` follows the format of `../glibc-longjmp-chk/evidence/full-check-results-*.txt`,
so two runs diff cleanly. The failure buckets that are the host or qemu-user
rather than MicroBlaze are listed in `../glibc-longjmp-chk/README.md`
("Final full run"); on this setup roughly 400 of 5400 results fail for those
reasons, and the 4 gas `all/` failures reported by `binutils-check` are
present on the unpatched assembler as well.
