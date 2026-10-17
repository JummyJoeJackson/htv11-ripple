#!/usr/bin/env bash
# Turns compiler and test errors in a build log into GitHub annotations, so
# they show on the run summary without opening the full log.
# Usage: annotate.sh <log file> <title>
log="$1"
title="$2"
[ -f "$log" ] || exit 0
errors="$(mktemp)"
grep -E '(: error:|: fatal error:|xcodebuild: error|error: unable|error: no such module|\*\* BUILD FAILED \*\*|Test Case .* failed)' "$log" \
  | sed "s#${GITHUB_WORKSPACE:-/nonexistent}/##g" \
  | awk '!seen[$0]++' > "$errors" || true
count=$(wc -l < "$errors" | tr -d ' ')
[ "$count" -gt 0 ] || exit 0
summary=$(head -120 "$errors" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
echo "::error title=${title} (${count} lines)::${summary}"
head -8 "$errors" | while IFS= read -r line; do
  if [[ "$line" =~ ^([^:]+):([0-9]+):([0-9]+):\ (fatal\ )?error:\ (.*)$ ]]; then
    msg=$(printf '%s' "${BASH_REMATCH[5]}" | sed 's/%/%25/g')
    echo "::error file=${BASH_REMATCH[1]},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${msg}"
  fi
done
