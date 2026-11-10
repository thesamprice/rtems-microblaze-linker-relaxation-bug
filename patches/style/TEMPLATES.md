# Templates

**[RECOMMENDED]**, derived from the good examples in EXAMPLES.md.  Delete
any paragraph the reader does not need.  For GCC keep the ChangeLog block
(required) and put `Assisted-by:` above it; for binutils the ChangeLog
block is optional.  Trailers (`Signed-off-by:`) are added by the human
sending the patch.

## Bug fix

```
component: Don't <do the wrong thing> in <function> [PR12345]

<Input or condition> makes <function> <observable failure: wrong value,
ICE text, crash, FAIL line>.  <Cause: the invariant that is violated,
in one or two sentences.>

<What the fix does>.  <Why this fix rather than the obvious
alternative, if there is one.>  <What it deliberately leaves alone.>

<For a regression:> The problem came in with r16-1234 / commit
<12-char hash> ("subject").

Bootstrapped and regtested on <triplet>.          <- GCC
```

Model: e8621d3bdaf0 (GCC), 0cdae10e5786 (binutils).

## Optimisation

```
component: <Do X> for <case>

<Code that is slow now, as a short snippet or the generated sequence.>
<Why the compiler produced it.>

<What the change produces instead, with before and after if short.>
<Measured effect, with the benchmark and configuration named.>
<Cases it does not cover.>

Bootstrapped and regtested on <triplet>.
```

Model: 4d22d3ead95e, 5be7b70e769e.

## Refactor

```
component: <Do the mechanical thing>

<One or two sentences: why, e.g. "in preparation for <next change>" or
"X duplicates Y".>

No functional change.
```

Model: 35874595799c (GCC), b49b0bfe1215 (binutils).

## Test only

```
testsuite: <target:> Fix <test name>

<test> fails on <target> with "<error text>", because <reason>.
<What the change does: skip, xfail, adjust the expected output, and why
that rather than another option.>
```

Model: 73ae58ac01fc (GCC), 6197c6f3a6f9 (binutils).

## Architecture or back-end change

```
<target>: <What it adds or changes>

<The architecture rule involved, with the manual and section.>  <What
the port does now and why that is wrong or slow.>

<What the change does, and the patterns, options or encodings it
touches.>  <What it leaves unchanged and why.>

<How it was verified: simulator, hardware, testsuite, triplets.>
```

Model: 5be7b70e769e (GCC), 5ad7fd27ba37 (binutils).

## One-line correction

```
component: Fix <thing> in <function>
```

plus, if the reason is not obvious from the diff, one sentence.  Typos,
comment fixes and spelling need no body.  Model: 1beab80079e2 (three
sentences for a dead-code removal).

## Series cover letter

Shared background, how the patches depend on each other, how to
reproduce, and suite-wide test results go here once, not in each commit.
