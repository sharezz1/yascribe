#!/usr/bin/env python3
"""Jednorazowo: podmienia hashe commitów w śledzonych plikach tekstowych po `git filter-repo`.

Użycie: scripts/rewrite-hashes.py <commit-map> [--dry-run]
`commit-map` to `.git/filter-repo/commit-map` (kolumny: stary nowy). Token hex 7–40 znaków
jest commitem tylko wtedy, gdy jest jednoznacznym prefiksem jakiegoś starego hasha; zamieniany
jest na prefiks tej samej długości nowego hasha. Zero trafień (hash spoza mapy: UUID, przed-amendowy)
zostaje bez zmian; niejednoznaczność po obu stronach jest wypisywana i też zostaje bez zmian.
Zapis operacji dla docs/superpowers/reports/Y-przepisanie-historii.md.
"""
import bisect
import re
import subprocess
import sys

TOKEN = re.compile(r"(?<![0-9A-Za-z_])[0-9a-f]{7,40}(?![0-9A-Za-z_])")


def load_map(path):
    pairs = [line.split() for line in open(path) if line.strip()]
    # 40 zer = commit usunięty przez filter-repo (puste po --invert-paths): bez mapowania
    pairs = [p for p in pairs if len(p[0]) == 40 and len(p[1]) == 40 and p[0] != p[1] and p[1] != "0" * 40]
    return dict(pairs)


def matches(sorted_hashes, prefix):
    i = bisect.bisect_left(sorted_hashes, prefix)
    out = []
    while i < len(sorted_hashes) and sorted_hashes[i].startswith(prefix):
        out.append(sorted_hashes[i])
        i += 1
    return out


def main():
    mapping = load_map(sys.argv[1])
    dry = "--dry-run" in sys.argv
    old = sorted(mapping)
    new = sorted(mapping.values())
    files = subprocess.check_output(["git", "ls-files", "-z"], text=True).split("\0")
    replaced, unmapped, ambiguous = {}, {}, {}

    def sub(m, path):
        tok = m.group(0)
        hits = matches(old, tok)
        if not hits:
            unmapped.setdefault(tok, set()).add(path)
            return tok
        repl = mapping[hits[0]][: len(tok)]
        if len(hits) > 1 or len(matches(new, repl)) > 1:
            ambiguous.setdefault(tok, set()).add(path)
            return tok
        replaced.setdefault((tok, repl), set()).add(path)
        return repl

    for path in filter(None, files):
        try:
            text = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue
        out = TOKEN.sub(lambda m: sub(m, path), text)
        if out != text and not dry:
            open(path, "w", encoding="utf-8").write(out)

    print(f"zamienione: {len(replaced)} tokenów w {len({p for s in replaced.values() for p in s})} plikach")
    for (a, b), ps in sorted(replaced.items()):
        print(f"  {a} -> {b}  ({len(ps)} plików)")
    print(f"bez mapowania: {len(unmapped)}")
    for t, ps in sorted(unmapped.items()):
        print(f"  {t}  {sorted(ps)}")
    print(f"niejednoznaczne: {len(ambiguous)}")
    for t, ps in sorted(ambiguous.items()):
        print(f"  {t}  {sorted(ps)}")


main()
