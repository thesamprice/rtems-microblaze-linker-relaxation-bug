#!/usr/bin/env python3
"""check-patch-style.py [dir|file ...] -- audit patch messages against STYLE.md.

Mechanical checks only: subject length and full stop, prose width, "--" used
as punctuation, single-space sentence breaks, the ChangeLog directory
headers, the trailer form and the blank line before it, and a list of
phrasings that have been flagged in review here.

It cannot tell you whether the message is any good.  Read patches/STYLE.md
and re-read the message; the one that got away in CLAUDE.md was caught by a
person, not a checker.

    python3 tools/check-patch-style.py patches/binutils-relax
"""
import io, re, sys, glob
BANNED = [
    'provenance rather than by argument', 'worth noting', 'aggravation',
    'bites harder', 'the symptom that led here', 'presents as',
    'is the substantive one', 'not a new one', 'shape of loop',
    'Hence ', 'It shows when', 'worth stating', 'worth having',
]
def msg(path):
    s = io.open(path, encoding='utf-8').read()
    if '\n---\n' in s:          # a .patch: message only
        s = s[s.index('Subject:'):s.index('\n---\n')]
    return s

fails = 0
targets = sys.argv[1:] or ['patches/binutils-relax']
paths = []
for t in targets:
    if t.endswith(('.patch', '.txt')):
        paths.append(t)
    else:
        paths += [f for f in sorted(glob.glob(t + '/*'))
                  if f.endswith('.patch') or f.endswith('0000-cover-letter.txt')]
for path in paths:
    m = msg(path)
    name = path.split('/')[-1]
    probs = []
    # subject length
    if path.endswith('.patch'):
        subj = m.split('\n', 1)[0].replace('Subject: [PATCH] ', '')
        if len(subj) > 55: probs.append('subject %d chars (>55)' % len(subj))
        if subj.endswith('.'): probs.append('subject ends with a full stop')
    # line width
    wide = [l for l in m.split('\n') if len(l) > 72 and not l.startswith('\t')
            and 'http' not in l and not l.lstrip().startswith('diff ')]
    if wide: probs.append('%d line(s) over 72 cols: %r' % (len(wide), wide[0][:50]))
    # em-dash punctuation
    for l in m.split('\n'):
        if re.search(r'\S \-\- \S', l) and 'wrap' not in l and 'git log' not in l:
            probs.append('"--" as punctuation: %r' % l.strip()[:55]); break
    # one-space sentence breaks
    one = re.findall(r'[a-z]\. [A-Z]', m)
    if one: probs.append('%d single-space sentence break(s), e.g. %r' % (len(one), one[0]))
    # banned phrases
    for b in BANNED:
        if b.lower() in m.lower(): probs.append('phrase: %r' % b)
    if path.endswith('.patch'):
        # At least one "dir/" header line.  A patch touching one directory
        # may omit it, but these series touch two or more.
        if not re.search(r'\n(bfd|gas|ld|binutils|opcodes|include)/\n', m):
            probs.append('ChangeLog block has no directory header')
        if 'Assisted-by: Claude <noreply@anthropic.com>' not in m:
            probs.append('trailer not the house form')
        if not re.search(r'\n\nAssisted-by:', m):
            probs.append('no blank line before the trailers')
    print('%-46s %s' % (name, 'OK' if not probs else ''))
    for p in probs:
        print('    - ' + p); fails += 1
sys.exit(1 if fails else 0)
