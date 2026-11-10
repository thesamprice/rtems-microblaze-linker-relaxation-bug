#!/usr/bin/env python3
"""review-commit-msg.py: check commit messages against patches/style/.

    tools/review-commit-msg.py [--project gcc|binutils] PATCH|DIR ...
    tools/review-commit-msg.py [--project gcc|binutils] --git REPO RANGE

PATCH is a git format-patch file; DIR is a series directory (its *.patch
files, plus 0000-cover-letter.txt for the cross-patch checks).  --git
reads commits from a repository instead.  The project is guessed from the
paths the diff touches when --project is not given.

Findings are labelled as patches/style/ labels them:

  REQUIRED     an official rule (for GCC, what the push hook rejects)
  CONVENTION   what most upstream commits do; not a rule
  RECOMMENDED  this study's advice

It does not replace contrib/gcc-changelog/git_check_commit.py, which is
the authority for GCC's ChangeLog rules, and it cannot judge whether a
message explains the change.  Read patches/style/GCC.md or BINUTILS.md
and the message itself.

Exit status is 1 if any REQUIRED finding is reported.
"""
import argparse, collections, glob, os, re, subprocess, sys

# Population percentiles of explanation words by non-test lines changed
# (patches/style/STATS.md, 4000 commits each).  (p75, p90).
LENGTH = {
    'gcc':      {'1-10': (76, 119), '11-50': (101, 172), '51-300': (130, 235), '>300': (119, 216),
                 'tests': (52, 89)},
    'binutils': {'1-10': (45, 82), '11-50': (68, 118), '51-300': (92, 162), '>300': (85, 168),
                 'tests': (47, 92)},
}
# p90 at the highest judged complexity in the deep samples: beyond this a
# message is longer than nearly anything upstream accepts.
CEILING = {'gcc': 285, 'binutils': 291}

TRAILER = re.compile(r'^([A-Z][A-Za-z]*(-[A-Za-z]+)*-by|Change-Id|Fixes|Link|Bug|Closes|'
                     r'Generated-By)\s*:', re.I)
GCC_HOOK_TRAILERS = ('reviewed-by:', 'reviewed-on:', 'signed-off-by:', 'acked-by:',
                     'tested-by:', 'reported-by:', 'suggested-by:', 'co-authored-by:')
CL_START = re.compile(r'^([\w.+-]+(/[\w.+-]+)*/ChangeLog:?|[\w.+-]+(/[\w.+-]+)*/:?)\s*$'
                      r'|^\t\* |^\tPR [\w+.-]+/\d+')
TEST_PATH = re.compile(r'(^|/)testsuite/|(^|/)tests?/')
TESTED = re.compile(r'bootstrapped|regtested|regression[- ]tested|tested on|tested with|'
                    r'no (new )?regressions|expected passes|unexpected failures', re.I)
RESIDUE = re.compile(r'\[PATCH|\bv\d+:|changes (since|in) v\d|waiting on|\bthanks\b|'
                     r'have a (great|nice) day|^PS\b|cover letter', re.I | re.M)
HASH = re.compile(r'\b(r\d{1,2}-\d{1,6}|[0-9a-f]{9,40})\b')
VAGUE = re.compile(r'\b(a recent (change|patch|commit)|my previous patch'
                   r'|an earlier (change|patch))\b', re.I)


class Msg:
    def __init__(self, name, subject, body, files, line2_blank=True):
        self.name, self.subject, self.body, self.files = name, subject, body, files
        self.line2_blank = line2_blank
        lines = body.split('\n')
        self.lines = lines
        self.cl_index = next((i for i, l in enumerate(lines) if CL_START.match(l)), None)
        free = lines[:self.cl_index] if self.cl_index is not None else \
            [l for l in lines if not TRAILER.match(l)]
        self.free = free
        prose = [l for l in free if l.strip() and not l.startswith(('\t', '  '))
                 and not TRAILER.match(l)]
        self.prose = prose
        self.words = len(' '.join(prose).split())
        self.paragraphs = [p.strip() for p in '\n'.join(free).split('\n\n')
                           if p.strip() and not TRAILER.match(p.strip())]
        self.code = sum(a + d for f, a, d in files if not TEST_PATH.search(f) and 'ChangeLog' not in f)
        self.total = sum(a + d for f, a, d in files if 'ChangeLog' not in f)


def parse_patch(path):
    s = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'^Subject: (.*(?:\n[ \t].*)*)', s, re.M)
    subject = re.sub(r'\s*\n\s+', ' ', m.group(1)) if m else ''
    subject = re.sub(r'^\[[^\]]*\]\s*', '', subject)
    start = s.index('\n\n', m.end()) + 2 if m else 0
    end = s.find('\n---\n', start)
    body = s[start:end if end >= 0 else len(s)].strip('\n')
    files = []
    for f, a, d in re.findall(r'^diff --git a/\S+ b/(\S+)\n(?:.*\n)*?', s, re.M) and \
            numstat_from_diff(s) or []:
        files.append((f, a, d))
    return Msg(os.path.basename(path), subject, body, files)


def numstat_from_diff(s):
    out, cur, a, d = [], None, 0, 0
    for l in s.split('\n'):
        if l.startswith('diff --git '):
            if cur:
                out.append((cur, a, d))
            cur, a, d = l.split(' b/', 1)[1], 0, 0
        elif cur and l.startswith('+') and not l.startswith('+++'):
            a += 1
        elif cur and l.startswith('-') and not l.startswith('---'):
            d += 1
    if cur:
        out.append((cur, a, d))
    return out


def from_git(repo, rng):
    G = ['git', '-C', repo]
    shas = subprocess.run(G + ['rev-list', '--reverse', rng], capture_output=True, text=True,
                          check=True).stdout.split()
    msgs = []
    for h in shas:
        b = subprocess.run(G + ['log', '-1', '--format=%B', h], capture_output=True, text=True).stdout
        st = subprocess.run(G + ['show', '--numstat', '--format=', h], capture_output=True,
                            text=True).stdout
        files = [(p[2], int(p[0]) if p[0].isdigit() else 0, int(p[1]) if p[1].isdigit() else 0)
                 for p in (l.split('\t') for l in st.split('\n')) if len(p) == 3]
        subj, _, body = b.partition('\n')
        msgs.append(Msg(h[:12], subj, body.strip('\n'), files,
                        line2_blank=not body.split('\n', 1)[0].strip()))
    return msgs


def guess_project(msgs):
    paths = [f for m in msgs for f, _, _ in m.files]
    if any(p.startswith(('gcc/', 'libgcc/', 'libstdc++-v3/', 'libgfortran/')) for p in paths):
        return 'gcc'
    if any(p.startswith(('bfd/', 'gas/', 'ld/', 'opcodes/', 'binutils/')) for p in paths):
        return 'binutils'
    return 'gcc' if any(re.match(r'^[\w/+-]*ChangeLog:', l) for m in msgs for l in m.lines) \
        else 'binutils'


def bucket(m):
    c = m.code
    return 'tests' if c == 0 else '1-10' if c <= 10 else '11-50' if c <= 50 else \
        '51-300' if c <= 300 else '>300'


def review(m, project):
    F = []
    add = lambda level, text: F.append((level, text))
    s = m.subject
    # --- subject
    if len(s) > 75:
        add('CONVENTION' if project == 'binutils' else 'REQUIRED*',
            'subject is %d characters; GCC documents 75 at most, 90%% of commits are '
            'under %d' % (len(s), 75 if project == 'gcc' else 67))
    elif len(s) > 72:
        add('CONVENTION', 'subject is %d characters; 86-95%% of upstream subjects are 72 or '
            'fewer' % len(s))
    if s.endswith('.'):
        add('CONVENTION', 'subject ends with a full stop (13% of GCC, 4% of 2026 binutils '
            'commits do)')
    if not re.match(r'^[\w./+*,{} -]+: |^PR \d+|^Revert ', s):
        add('CONVENTION', 'subject has no "component:" prefix (83% of GCC and 75% of '
            'binutils commits use one)')
    if re.search(r'\[PATCH|\bv\d\b', s):
        add('RECOMMENDED', 'subject still carries a mailing-list tag')
    # --- GCC hook rules
    if project == 'gcc':
        if not m.line2_blank:
            add('REQUIRED', 'line 2 of the message must be blank')
        if m.cl_index is None:
            add('REQUIRED', 'no ChangeLog block; the GCC push hook rejects the commit')
        else:
            after = m.lines[m.cl_index:]
            for l in after:
                if not l.strip() or l.startswith('\t') or CL_START.match(l):
                    continue
                if l.lower().startswith(GCC_HOOK_TRAILERS):
                    continue
                if l.lower().startswith('assisted-by:'):
                    add('REQUIRED', 'Assisted-by after the ChangeLog block fails the push hook '
                        '("line should start with a tab"); move it above the block')
                else:
                    add('REQUIRED', 'line in the ChangeLog block does not start with a tab: %r'
                        % l[:50])
                break
            for l in after:
                if len(l.expandtabs(8)) > 100 and l.startswith('\t'):
                    add('REQUIRED', 'ChangeLog line over 100 columns: %r' % l.strip()[:40])
                    break
            named = ' '.join(after)
            for f, _, _ in m.files:
                base = f.split('/')[-1]
                if 'ChangeLog' in f or base in named:
                    continue
                add('REQUIRED', 'changed file not named in the ChangeLog: %s' % f)
            prs = re.findall(r'PR\s?(\d{4,})', s)
            for pr in prs:
                if not re.search(r'^\tPR [\w+.-]+/%s\b' % pr, m.body, re.M):
                    add('REQUIRED', 'PR %s in the subject has no "\\tPR component/%s" line'
                        % (pr, pr))
    if not any(l.lower().startswith('signed-off-by:') for l in m.lines):
        add('REQUIRED*', 'no Signed-off-by (needed unless you have an FSF assignment; '
            'added by the human sending the patch)')
    if any(l.lower().startswith('co-authored-by:') and re.search(r'claude|gpt|llm|copilot|ai\b', l, re.I)
           for l in m.lines):
        add('REQUIRED', 'Co-Authored-By names an AI tool; reviewers read it as AI-generated '
            'code and GCC makes it a ChangeLog author.  Use Assisted-by (GCC)')
    if project == 'binutils' and any(l.lower().startswith(('assisted-by:', 'generated-by:'))
                                     for l in m.lines) and m.total > 10:
        add('REQUIRED*', 'marks LLM involvement on a %d-line change (tests included); binutils '
            'does not accept legally significant LLM-generated content, testsuites included '
            '(binutils/MAINTAINERS)' % m.total)
    if project == 'gcc' and any(l.lower().startswith('assisted-by:') for l in m.lines) \
            and m.code > 10:
        add('REQUIRED*', 'marks LLM involvement on %d non-test lines; GCC declines legally '
            'significant LLM-generated content outside test cases (gcc.gnu.org/ai-policy.html)'
            % m.code)
    # --- explanation
    lo, hi = LENGTH[project][bucket(m)]
    if m.words == 0 and m.code > 10:
        add('RECOMMENDED', 'no explanation for a %d-line change; reviewers ask for the why'
            % m.code)
    elif m.words > CEILING[project]:
        add('RECOMMENDED', '%d words of explanation: above the p90 even for the hardest '
            'changes upstream (%d).  Move background and verification detail to the cover '
            'letter or notes' % (m.words, CEILING[project]))
    elif m.words > hi:
        add('CONVENTION', '%d words for a %s-line change; 90%% of upstream %s commits of that '
            'size use %d or fewer.  Fine if the change is hard to understand' %
            (m.words, bucket(m), project, hi))
    for l in m.prose:
        if len(l) > 76 and 'http' not in l:
            add('CONVENTION', 'explanation line over 76 columns: %r' % l[:40])
            break
    r = RESIDUE.search('\n'.join(m.free))
    if r:
        add('RECOMMENDED', 'mailing-list residue in the message: %r' % r.group(0))
    v = VAGUE.search('\n'.join(m.prose))
    if v:
        add('RECOMMENDED', '"%s" cannot be followed later; cite r-number or hash' % v.group(0))
    hashes = HASH.findall(' '.join(m.prose))
    if len(hashes) > 2:
        add('RECOMMENDED', '%d commit citations; right for a regression chain, otherwise '
            'cite history only for a dependency' % len(hashes))
    return F


def cross(msgs, project):
    """Findings across a series."""
    F = []
    count = collections.Counter()
    for m in msgs:
        for p in set(m.paragraphs):
            norm = re.sub(r'\d+', 'N', re.sub(r'\s+', ' ', p))
            count[norm] += 1
    rep = [p for p, n in count.items() if n >= 3 and len(p.split()) >= 12]
    for p in rep:
        F.append(('RECOMMENDED', 'paragraph repeated in %d patches; say it once in the cover '
                  'letter: %r' % (count[p], p[:70])))
    tested = sum(bool(TESTED.search('\n'.join(m.free))) for m in msgs)
    if len(msgs) >= 3 and tested == len(msgs) and project == 'binutils':
        F.append(('CONVENTION', 'every patch states test results; about 2% of binutils '
                  'commits do.  Put them in the cover letter'))
    return F


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--project', choices=('gcc', 'binutils'))
    ap.add_argument('--git', nargs=2, metavar=('REPO', 'RANGE'))
    ap.add_argument('paths', nargs='*')
    a = ap.parse_args()
    msgs = []
    if a.git:
        msgs = from_git(*a.git)
    for p in a.paths:
        files = sorted(glob.glob(os.path.join(p, '*.patch'))) if os.path.isdir(p) else [p]
        msgs += [parse_patch(f) for f in files if not f.endswith('0000-cover-letter.patch')]
    if not msgs:
        ap.error('nothing to review')
    project = a.project or guess_project(msgs)
    req = 0
    print('project: %s%s' % (project, '' if a.project else ' (guessed)'))
    for m in msgs:
        F = review(m, project)
        print('\n%s  (%d words, %d code lines)\n  %s' % (m.name, m.words, m.code, m.subject))
        for level, text in F or [('ok', 'nothing found')]:
            print('  %-11s %s' % (level, text))
            req += level == 'REQUIRED'
    X = cross(msgs, project)
    if X:
        print('\nseries')
        for level, text in X:
            print('  %-11s %s' % (level, text))
    print('\nREQUIRED* = a rule that has exceptions (assignment instead of DCO; GCC subject '
          'length is documented, not enforced; legal significance is the reviewer\'s call).')
    sys.exit(1 if req else 0)


main()
