#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"

verification_scripts=(
  scripts/verify-part-2.sh
  scripts/verify-part-3-basics.sh
  scripts/verify-part-3-conflicts.sh
  scripts/verify-part-4-remotes.sh
  scripts/verify-part-4-history.sh
  scripts/verify-part-5-local-history.sh
  scripts/verify-part-5-recovery.sh
  scripts/verify-part-6-engineering.sh
)

for script in "${verification_scripts[@]}"; do
  bash -n "$script"
  "$script"
done

ruby scripts/check-book-links.rb
git diff --check

printf 'All Git blue book checks passed.\n'
