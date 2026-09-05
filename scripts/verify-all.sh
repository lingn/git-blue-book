#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"

verification_scripts=(
  scripts/verify-object-model.sh
  scripts/verify-part-2.sh
  scripts/verify-part-3-basics.sh
  scripts/verify-part-3-conflicts.sh
  scripts/verify-complex-conflicts-rerere.sh
  scripts/verify-part-4-remotes.sh
  scripts/verify-part-4-history.sh
  scripts/verify-remote-transport-auth.sh
  scripts/verify-refspec-partial-clone.sh
  scripts/verify-part-5-local-history.sh
  scripts/verify-interactive-rebase.sh
  scripts/verify-force-with-lease.sh
  scripts/verify-reset-reflog.sh
  scripts/verify-revert.sh
  scripts/verify-remote-history-rewrite.sh
  scripts/verify-part-6-collaboration.sh
  scripts/verify-part-6-engineering.sh
  scripts/verify-ci-evidence-chain.sh
  scripts/verify-ci-trigger-queue.sh
  scripts/verify-reproducible-build.sh
  scripts/verify-release-promotion.sh
  scripts/verify-deploy-rollback.sh
  scripts/verify-database-migrations.sh
  scripts/verify-incident-to-release.sh
  scripts/verify-monorepo-topology.sh
  scripts/verify-signatures-trust.sh
  scripts/verify-untrusted-repository.sh
  scripts/verify-repository-performance-baseline.sh
  scripts/verify-lfs-pointer-model.sh
  scripts/verify-submodule-subtree.sh
  scripts/verify-sensitive-history-boundaries.sh
  scripts/verify-machine-credential-boundaries.sh
  scripts/verify-ci-dependency-pinning.sh
  scripts/verify-secret-scanning-and-exports.sh
  scripts/verify-forensic-acquisition.sh
  scripts/verify-object-forensics-recovery.sh
  scripts/verify-history-attribution.sh
  scripts/verify-bundle-mirror-recovery.sh
  scripts/verify-repository-migration-cutover.sh
  scripts/verify-disaster-failover-recovery.sh
  scripts/verify-repository-lifecycle-governance.sh
  scripts/verify-access-lifecycle-governance.sh
  scripts/verify-policy-rules-and-exceptions.sh
  scripts/verify-audit-evidence-retention.sh
  scripts/verify-repository-health-capacity.sh
  scripts/verify-organizational-recovery-drill.sh
  scripts/verify-troubleshooting-snapshot.sh
  scripts/verify-missing-files-and-commits.sh
  scripts/verify-push-auth-permission-boundaries.sh
  scripts/verify-performance-troubleshooting.sh
  scripts/verify-external-dependency-ci-failures.sh
  scripts/verify-signature-troubleshooting.sh
  scripts/verify-remote-ref-drift-failures.sh
  scripts/verify-repository-corruption-locks-concurrency.sh
)

for script in "${verification_scripts[@]}"; do
  bash -n "$script"
  "$script"
done

ruby scripts/check-book-links.rb
git diff --check

printf 'All Git blue book checks passed.\n'
