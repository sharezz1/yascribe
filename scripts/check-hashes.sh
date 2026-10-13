#!/bin/bash
# Sprawdza, że każdy hash commita w backtickach w docs/**/*.md jest osiągalny z jakiejś gałęzi.
# Typowa wpadka: raport cytuje własny commit, a potem `git commit --amend` dopina raport
# i zmienia hash — cytowany obiekt wisi poza gałęzią (a po `git gc` znika).
# Hashe świadomie historyczne (opisane w raporcie) wpisz do scripts/check-hashes.allow.
#
# Użycie: scripts/check-hashes.sh   (też jako .git/hooks/pre-commit i post-commit)
set -uo pipefail
cd "$(dirname "$0")/.."

ALLOW=scripts/check-hashes.allow
BAD=0
for h in $(grep -rohE '`[0-9a-f]{7,40}`' docs --include='*.md' | tr -d '`' | sort -u); do
    grep -q "^$h" "$ALLOW" 2>/dev/null && continue
    [ -n "$(git branch -a --contains "$h" 2>/dev/null)" ] && continue
    echo "check-hashes: \`$h\` nie jest na żadnej gałęzi: $(grep -rl "$h" docs --include='*.md' | tr '\n' ' ')" >&2
    BAD=1
done
[ "$BAD" -eq 0 ] || echo "check-hashes: popraw hash (git log -1) albo dopisz go do $ALLOW z powodem." >&2
exit "$BAD"
