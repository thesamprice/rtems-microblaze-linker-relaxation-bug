#!/usr/bin/env python3
"""stats.py: Markdown statistics from gcc.jsonl and binutils.jsonl."""
import collections, json, statistics, sys

def load(n):
    return [json.loads(l) for l in open(n + '.jsonl')]

def q(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p))] if v else 0

def rank(v):
    s = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v); i = 0
    while i < len(s):
        j = i
        while j + 1 < len(s) and v[s[j + 1]] == v[s[i]]:
            j += 1
        for k in range(i, j + 1):
            r[s[k]] = (i + j) / 2
        i = j + 1
    return r

def spearman(x, y):
    if len(x) < 3:
        return float('nan')
    rx, ry = rank(x), rank(y)
    mx, my = statistics.mean(rx), statistics.mean(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = (sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry)) ** .5
    return num / den if den else float('nan')

def pct(rows, k):
    return '%.0f%%' % (100 * sum(bool(r[k]) for r in rows) / len(rows)) if rows else '-'

def bucket(c):
    return '1-10' if c <= 10 else '11-50' if c <= 50 else '51-300' if c <= 300 else '>300'

def subsystem(r, repo):
    p = [x for x in r['paths'] if '/testsuite/' not in x and 'ChangeLog' not in x] or r['paths']
    if not p:
        return '?'
    f = p[0]; parts = f.split('/')
    if repo == 'gcc':
        if parts[0] == 'gcc' and len(parts) > 2 and parts[1] == 'config':
            return 'gcc/config (back ends)'
        if parts[0] == 'gcc' and len(parts) > 2 and parts[1] in ('cp', 'c', 'c-family', 'fortran',
                                                                 'ada', 'rust', 'cobol', 'm2', 'go', 'd',
                                                                 'algol68', 'jit', 'analyzer'):
            return 'gcc/' + parts[1] + ' (front end)' if parts[1] != 'analyzer' else 'gcc/analyzer'
        if parts[0] == 'gcc' and len(parts) > 2 and parts[1] == 'testsuite':
            return 'gcc/testsuite only'
        if parts[0] == 'gcc':
            return 'gcc middle-end'
        return parts[0]
    else:
        if parts[0] in ('gas', 'opcodes', 'bfd') and len(parts) > 1 and (
                parts[1] == 'config' or any(a in parts[-1] for a in ('aarch64', 'riscv', 'i386', 'x86',
                'arm', 'mips', 'ppc', 'loongarch', 's390', 'sparc', 'microblaze', 'sh', 'kvx', 'bpf'))):
            return parts[0] + ' (target)'
        return parts[0]

out = []
P = out.append
for repo in ('gcc', 'binutils'):
    R = load(repo)
    P('## %s: %d commits, %s to %s\n' % (repo, len(R), min(r['date'] for r in R),
                                          max(r['date'] for r in R)))
    P('Bot commits (daily bumps, date updates, copyright years, regeneration) are excluded'
      + ('; so are commits touching only gdb, gdbserver, gdbsupport or sim.' if repo == 'binutils' else '.')
      + '  "Explanation" means the body with the ChangeLog block, PR lines, trailers and indented'
      ' quotes removed.  Sizes count non-test, non-ChangeLog lines added plus deleted.\n')
    P('### Explanation length by patch size\n')
    P('| lines changed | commits | no explanation | median words | p75 | p90 | median lines |')
    P('|---|---:|---:|---:|---:|---:|---:|')
    for b in ('1-10', '11-50', '51-300', '>300'):
        s = [r for r in R if r['code_changed'] and bucket(r['code_changed']) == b]
        w = [r['body_words'] for r in s]
        P('| %s | %d | %.0f%% | %d | %d | %d | %d |' % (
            b, len(s), 100 * sum(x == 0 for x in w) / len(s), statistics.median(w), q(w, .75),
            q(w, .9), statistics.median(r['body_lines'] for r in s)))
    t = [r for r in R if r['code_changed'] == 0]
    if t:
        w = [r['body_words'] for r in t]
        P('| tests/docs only | %d | %.0f%% | %d | %d | %d | %d |' % (
            len(t), 100 * sum(x == 0 for x in w) / len(t), statistics.median(w), q(w, .75), q(w, .9),
            statistics.median(r['body_lines'] for r in t)))
    P('')
    P('### By change type (heuristic classification from subject and paths)\n')
    P('| type | commits | median words | p90 | rationale words | testing stated | PR cited | cites a commit | quotes code/output |')
    P('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
    for ty, _ in collections.Counter(r['type'] for r in R).most_common():
        s = [r for r in R if r['type'] == ty]; w = [r['body_words'] for r in s]
        P('| %s | %d | %d | %d | %s | %s | %s | %s | %s |' % (
            ty, len(s), statistics.median(w), q(w, .9), pct(s, 'rationale'), pct(s, 'tested'),
            pct(s, 'pr'), pct(s, 'cites_commit'), '%.0f%%' % (100 * sum(r['quoted_lines'] > 0 for r in s) / len(s))))
    P('')
    P('### By subsystem (first non-test file)\n')
    P('| subsystem | commits | median words | p90 | ChangeLog block | testing stated |')
    P('|---|---:|---:|---:|---:|---:|')
    subs = collections.Counter(subsystem(r, repo) for r in R)
    for sname, n in subs.most_common(14):
        s = [r for r in R if subsystem(r, repo) == sname]; w = [r['body_words'] for r in s]
        P('| %s | %d | %d | %d | %s | %s |' % (sname, n, statistics.median(w), q(w, .9),
                                               pct(s, 'has_changelog'), pct(s, 'tested')))
    P('')
    P('### Correlation of explanation length with patch measures (Spearman rho)\n')
    P('| measure | all | bugfix | feature | refactor |')
    P('|---|---:|---:|---:|---:|')
    for m in ('code_changed', 'code_files', 'hunks', 'functions', 'complexity'):
        cells = []
        for ty in (None, 'bugfix', 'feature', 'refactor'):
            s = [r for r in R if r['code_changed'] and (ty is None or r['type'] == ty)]
            cells.append('%.2f' % spearman([r[m] for r in s], [r['body_words'] for r in s]))
        P('| %s | %s |' % (m, ' | '.join(cells)))
    P('')
    P('### Form\n')
    sl = [r['subj_len'] for r in R]
    P('- Subject length: median %d, p90 %d, %.0f%% over 72.  Component prefix ("x: ..."): %s.  '
      'Ends with a full stop: %s.' % (statistics.median(sl), q(sl, .9),
                                       100 * sum(x > 72 for x in sl) / len(R), pct(R, 'subj_prefix'),
                                       pct(R, 'subj_period')))
    wide = [r for r in R if r['body_lines']]
    P('- Explanation lines over 72 columns: in %.0f%% of commits with an explanation.' % (
        100 * sum(r['over72'] > 0 for r in wide) / len(wide)))
    P('- ChangeLog block in the message: %s overall.' % pct(R, 'has_changelog'))
    P('- Mentions testing: %s.  First person (I/we): %s of commits with an explanation.' % (
        pct(R, 'tested'), pct(wide, 'first_person')))
    pc = [r['paragraphs'] for r in wide]
    P('- Paragraphs in the explanation: median %d, p90 %d.' % (statistics.median(pc), q(pc, .9)))
    tc = collections.Counter(t.lower() for r in R for t in set(r['trailers']))
    P('- Trailers: ' + ', '.join('%s %.1f%%' % (k, 100 * v / len(R)) for k, v in tc.most_common(8)) + '.')
    # Prefix vocabulary
    pre = collections.Counter(r['subject'].split(':')[0] for r in R if r['subj_prefix'])
    P('- Most common subject prefixes: ' + ', '.join('`%s` %d' % (k, v) for k, v in pre.most_common(15)) + '.')
    P('')
    # Established contributors
    au = collections.Counter(r['author'] for r in R)
    P('### Frequent authors: explanation length\n')
    P('| author | commits | median words | p90 | ChangeLog block | testing stated |')
    P('|---|---:|---:|---:|---:|---:|')
    for a, n in au.most_common(10):
        s = [r for r in R if r['author'] == a]; w = [r['body_words'] for r in s]
        P('| %s | %d | %d | %d | %s | %s |' % (a, n, statistics.median(w), q(w, .9),
                                               pct(s, 'has_changelog'), pct(s, 'tested')))
    P('')
print('\n'.join(out))
