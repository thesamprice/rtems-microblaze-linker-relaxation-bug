#!/usr/bin/env python3
"""collect.py REPO.git NAME N OUT.jsonl

Parse the N most recent non-merge, non-bot commits of REPO into one JSON
record each: subject, explanatory body, ChangeLog block and trailers
separated, plus size and complexity measures from the diff.  For
binutils-gdb, commits touching only gdb, gdbserver, gdbsupport or sim are
skipped.
"""
import json, re, subprocess, sys

repo, name, N, outp = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
GIT = ['/usr/bin/git', '-C', repo]

BOT_AUTHORS = {'GCC Administrator', 'GDB Administrator'}
BOT_SUBJ = re.compile(r'^(Daily bump|Automatic date update|Update copyright years'
                      r'|Update year range|Bump version|Regenerate|Regen\b)', re.I)
NOT_BINUTILS = re.compile(r'^(gdb|gdbserver|gdbsupport|sim|readline|gnulib|libbacktrace)/')
TRAILER = re.compile(r'^([A-Z][A-Za-z]*(-[A-Za-z]+)*-by|Change-Id|Fixes|Link|Bug|Closes|'
                     r'Suggested-by|Cc|Co-authored-by|Assisted-by)\s*:', re.I)
CL_DIR = re.compile(r'^[A-Za-z0-9_.+-]+(/[A-Za-z0-9_.+-]+)*/?:?\s*$')
CL_ENTRY = re.compile(r'^\t\* |^\t\(|^\tPR |^        \* ')
PR_LINE = re.compile(r'^\s*PR [a-z0-9+_.-]+/\d+')
TEST_PATH = re.compile(r'(^|/)testsuite/|(^|/)tests?/')
DOC_PATH = re.compile(r'\.(texi|texinfo|md|rst|txt|html|1|5)$|(^|/)doc/|NEWS$|MAINTAINERS$|README')

def classify(subj, body, files):
    s = subj.lower(); b = body.lower()
    nontest = [f for f in files if not TEST_PATH.search(f) and 'ChangeLog' not in f]
    if files and all(TEST_PATH.search(f) for f in files):
        return 'test'
    if nontest and all(DOC_PATH.search(f) for f in nontest):
        return 'docs'
    if re.search(r'\[pr\s?\d+\]|^[a-z-]+/\d+ - |\bpr\s?\d{4,}', s):
        return 'bugfix'
    if re.search(r'pre-commit|^revert|\btypo|whitespace|copyright|regenerat|\bregen\b|update (the )?'
                 r'(po|translations?)|sync (with|from)|\bbump\b|config\.(sub|guess)|'
                 r'autoconf|automake|libtool|cosmetic|spelling|indentation', s):
        return 'mechanical'
    if re.search(r'no functional change|nfc\b|nfci|refactor|clean ?up|cleanup|simplif|'
                 r'\brename|\bmove\b|split out|factor|constify|\bremove unused|dead code|'
                 r'use [a-z_]+ instead|replace .* with|\b(drop|remove|eliminate|fold|reuse|inline|'
                 r'tidy|pass an?|make .* (static|const)|use [a-z_]+\(\))\b', s + ' ' + b[:400]):
        return 'refactor'
    if re.search(r'\bfix|\bbug\b|\bpr\s|\bpr[a-z+-]*/\d|\bice\b|crash|wrong|incorrect|'
                 r'regression|fail|segfault|overflow|leak|ub\b|undefined behav|broken|'
                 r'correct|avoid|don\'t|do not|prevent|honou?r|respect|ignore|reject|validate|'
                 r'missing|corruption|mishandl|properly|bogus', s) or PR_LINE.search(body):
        return 'bugfix'
    if re.search(r'^(add|support|implement|new|introduce|enable|allow|handle|expand|'
                 r'optimi[sz]|improve|teach|recogni[sz]e|lower|vectori[sz]e|use )|'
                 r'[:\]] (add|support|implement|new|introduce|enable|allow|handle|'
                 r'optimi[sz]|improve|teach|recogni[sz]e|vectori[sz]e|permit|accept|lower|'
                 r'combine|convert|export|initial|default|widen|cost)', s):
        return 'feature'
    return 'other'

def split_message(lines):
    """-> (prose lines, quoted lines, changelog lines, trailer lines)."""
    prose, quoted, cl, tr = [], [], [], []
    in_cl = False
    for l in lines:
        if TRAILER.match(l):
            tr.append(l); in_cl = True; continue
        if not in_cl and (CL_ENTRY.match(l) or (CL_DIR.match(l) and l.strip().endswith(('/', ':'))
                                                and '/' in l or l.strip() in
                                                ('gcc/', 'libgcc/', 'bfd/', 'gas/', 'ld/',
                                                 'opcodes/', 'binutils/', 'include/'))):
            in_cl = True
        if in_cl:
            if l.strip():
                cl.append(l)
            continue
        if PR_LINE.match(l):
            cl.append(l); continue
        if not l.strip():
            prose.append('')
        elif l.startswith(('\t', '  ')):
            quoted.append(l); prose.append('<q>')
        else:
            prose.append(l)
    return prose, quoted, cl, tr

RATIONALE = re.compile(r'\b(because|since|so that|otherwise|which means|as a result|'
                       r'instead|the reason|in order to|this (causes|caused|leads|meant)|'
                       r'so the|the problem|the issue|the bug|fails?|crash)', re.I)
TESTED = re.compile(r'bootstrap|regtest|regression[- ]?test|tested on|tested with|'
                    r'tested by|no (new )?regressions|built and tested|testsuite|'
                    r'make check|tested\b', re.I)
HASH = re.compile(r'\b(r\d{1,2}-\d{1,6}|[0-9a-f]{8,40})\b')
FIRSTP = re.compile(r"\b(I|I've|I'm|I'd|my|we|We|our)\b")

def main():
    # One pass for messages + numstat; a second, -U0, for hunk and function counts.
    fmt = '%x00%H%x01%an%x01%ae%x01%cd%x01%B%x02'
    log = subprocess.Popen(GIT + ['log', '--no-merges', '--date=short', '--format=' + fmt,
                                  '--numstat', '-n', str(N * 4)],
                           stdout=subprocess.PIPE, text=True, errors='replace')
    recs = []
    buf = log.stdout.read()
    for chunk in buf.split('\x00')[1:]:
        head, _, stat = chunk.partition('\x02')
        h, an, ae, ad, body = head.split('\x01', 4)
        lines = body.rstrip('\n').split('\n')
        subj = lines[0].strip()
        if an in BOT_AUTHORS or BOT_SUBJ.search(subj):
            continue
        files = []
        for l in stat.strip().split('\n'):
            p = l.split('\t')
            if len(p) == 3:
                files.append((p[2], int(p[0]) if p[0].isdigit() else 0,
                              int(p[1]) if p[1].isdigit() else 0))
        fnames = [f for f, _, _ in files]
        if name == 'binutils' and (not fnames or all(NOT_BINUTILS.search(f) for f in fnames)):
            continue
        body_lines = lines[1:]
        while body_lines and not body_lines[0].strip():
            body_lines.pop(0)
        prose, quoted, cl, tr = split_message(body_lines)
        text_lines = [l for l in prose if l and l != '<q>']
        text = ' '.join(text_lines)
        paras = [p for p in '\n'.join(prose).split('\n\n') if p.strip()]
        code = [(f, a, d) for f, a, d in files if not TEST_PATH.search(f) and 'ChangeLog' not in f]
        recs.append(dict(
            repo=name, sha=h, author=an, email=ae, date=ad, subject=subj,
            subj_len=len(subj), subj_prefix=bool(re.match(r'^(\[[^\]]+\]\s*)?[\w./+*,{} -]+: ', subj)),
            subj_period=subj.endswith('.'),
            body_words=len(text.split()), body_lines=len(text_lines), paragraphs=len(paras),
            quoted_lines=len(quoted), cl_lines=len(cl), has_changelog=bool(cl),
            trailers=[t.split(':')[0].strip() for t in tr],
            max_width=max([len(l.expandtabs()) for l in body_lines] or [0]),
            over72=sum(len(l.expandtabs()) > 72 for l in text_lines),
            rationale=bool(RATIONALE.search(text)), tested=bool(TESTED.search(body)),
            cites_commit=bool(HASH.search(text)), first_person=bool(FIRSTP.search(text)),
            pr=bool(re.search(r'\bPR [a-z0-9+_.-]+/\d+', body)),
            files=len(files), code_files=len(code),
            added=sum(a for _, a, _ in files), deleted=sum(d for _, _, d in files),
            code_changed=sum(a + d for _, a, d in code),
            test_changed=sum(a + d for f, a, d in files if TEST_PATH.search(f)),
            dirs=sorted({f.split('/')[0] for f in fnames}),
            paths=fnames[:40],
            type=classify(subj, '\n'.join(body_lines), fnames)))
        if len(recs) >= N:
            break
    log.terminate()
    # Hunks and functions touched, from -U0 diffs of the selected commits.
    want = {r['sha']: r for r in recs}
    p = subprocess.Popen(GIT + ['log', '--no-merges', '-U0', '--format=%x00%H', '-n', str(N * 4)],
                         stdout=subprocess.PIPE, text=True, errors='replace')
    cur = None; hunks = 0; funcs = set()
    def flush():
        if cur in want:
            want[cur]['hunks'] = hunks; want[cur]['functions'] = len(funcs)
    for l in p.stdout:
        if l.startswith('\x00'):
            flush(); cur = l[1:].strip(); hunks = 0; funcs = set()
            if all('hunks' in r for r in recs):
                break
        elif l.startswith('@@'):
            hunks += 1
            m = re.match(r'@@ [^@]* @@ ?(.*)', l)
            if m and m.group(1).strip():
                funcs.add(m.group(1).strip()[:80])
    flush(); p.terminate()
    for r in recs:
        r.setdefault('hunks', 0); r.setdefault('functions', 0)
        # Rough semantic complexity: 0 trivial .. 4 broad.
        c = r['code_changed']
        r['complexity'] = (0 if c <= 2 else 1 if c <= 20 else 2 if c <= 100 else 3 if c <= 500 else 4) \
            + (1 if r['functions'] >= 5 or r['code_files'] >= 5 else 0)
    with open(outp, 'w') as f:
        for r in recs:
            f.write(json.dumps(r) + '\n')
    print(name, len(recs), 'commits,', recs[-1]['date'], 'to', recs[0]['date'])

main()
