#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-ci-evidence.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS GIT_CONFIG_COUNT SSH_ASKPASS

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'A SHA-256 command is required for the CI evidence experiment.\n' >&2
    return 1
  fi
}

mkdir -p "$lab_dir/seed/app" "$lab_dir/seed/config" "$lab_dir/seed/.ci"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"

printf 'service version 1\n' > "$lab_dir/seed/app/service.txt"
printf 'timeout=10\n' > "$lab_dir/seed/config/runtime.conf"
printf 'dependency-a=1.0.0\n' > "$lab_dir/seed/dependencies.lock"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'test -f app/service.txt' \
  'grep -Fq "service version 2" app/service.txt' \
  'test -s dependencies.lock' \
  > "$lab_dir/seed/.ci/pipeline.sh"
chmod +x "$lab_dir/seed/.ci/pipeline.sh"
git -C "$lab_dir/seed" add .ci app config dependencies.lock
git -C "$lab_dir/seed" commit --quiet -m "build: establish reproducible input"
base_commit="$(git -C "$lab_dir/seed" rev-parse HEAD)"

git -C "$lab_dir/seed" switch --quiet --create feature/payment
printf 'service version 2\n' > "$lab_dir/seed/app/service.txt"
git -C "$lab_dir/seed" add app/service.txt
git -C "$lab_dir/seed" commit --quiet -m "feat: update payment service"
feature_commit="$(git -C "$lab_dir/seed" rev-parse HEAD)"

git -C "$lab_dir/seed" switch --quiet main
printf 'timeout=20\n' > "$lab_dir/seed/config/runtime.conf"
git -C "$lab_dir/seed" add config/runtime.conf
git -C "$lab_dir/seed" commit --quiet -m "ops: adjust runtime timeout"
target_commit="$(git -C "$lab_dir/seed" rev-parse HEAD)"

git -C "$lab_dir/seed" switch --quiet --create integration/candidate
git -C "$lab_dir/seed" merge --quiet --no-ff feature/payment \
  -m "merge: test payment feature with current main"
candidate_commit="$(git -C "$lab_dir/seed" rev-parse HEAD)"
test "$(git -C "$lab_dir/seed" cat-file -p "$candidate_commit" | grep -c '^parent ')" = "2"
test "$(git -C "$lab_dir/seed" rev-parse "$candidate_commit^1")" = "$target_commit"
test "$(git -C "$lab_dir/seed" rev-parse "$candidate_commit^2")" = "$feature_commit"
git -C "$lab_dir/seed" tag -a v1.0.0-rc.1 "$candidate_commit" \
  -m "Release candidate 1"
tag_object="$(git -C "$lab_dir/seed" rev-parse v1.0.0-rc.1)"

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
server_url="file://$lab_dir/server.git"
git -C "$lab_dir/seed" remote add origin "$server_url"

existing_tag_output="$(git ls-remote --tags "$server_url" \
  refs/tags/v1.0.0-rc.1)"
test -n "$existing_tag_output"
test "$(printf '%s\n' "$existing_tag_output" | awk 'NR == 1 {print $1}')" = "$tag_object"
test "$(git ls-remote --tags "$server_url" \
  'refs/tags/v1.0.0-rc.1^{}' | awk 'NR == 1 {print $1}')" = "$candidate_commit"
test -z "$(git ls-remote --tags "$server_url" refs/tags/v1.0.0)"

git clone --quiet "$server_url" "$lab_dir/runner"
git -C "$lab_dir/runner" switch --quiet --detach "$candidate_commit"

test -z "$(git -C "$lab_dir/runner" branch --show-current)"
test "$(git -C "$lab_dir/runner" rev-parse HEAD)" = "$candidate_commit"
test -z "$(git -C "$lab_dir/runner" status --short)"
test "$(git -C "$lab_dir/runner" rev-parse v1.0.0-rc.1^{})" = "$candidate_commit"
test "$(git -C "$lab_dir/runner" cat-file -t v1.0.0-rc.1)" = "tag"

candidate_tree="$(git -C "$lab_dir/runner" rev-parse HEAD^{tree})"
pipeline_blob="$(git -C "$lab_dir/runner" rev-parse HEAD:.ci/pipeline.sh)"
(cd "$lab_dir/runner" && ./.ci/pipeline.sh)

mkdir "$lab_dir/build" "$lab_dir/staging" "$lab_dir/production"
git -C "$lab_dir/runner" archive --format=tar \
  --output="$lab_dir/build/candidate-one.tar" HEAD
git -C "$lab_dir/runner" archive --format=tar \
  --output="$lab_dir/build/candidate-two.tar" HEAD
git -C "$lab_dir/runner" archive --format=tar \
  --output="$lab_dir/build/feature-head.tar" "$feature_commit"

artifact_digest="$(sha256_file "$lab_dir/build/candidate-one.tar")"
test "$artifact_digest" = "$(sha256_file "$lab_dir/build/candidate-two.tar")"
test "$artifact_digest" != "$(sha256_file "$lab_dir/build/feature-head.tar")"

printf '%s\n' \
  "repository=$server_url" \
  "source_commit=$candidate_commit" \
  "source_tree=$candidate_tree" \
  "target_commit=$target_commit" \
  "feature_commit=$feature_commit" \
  "pipeline_blob=$pipeline_blob" \
  'build_command=git archive --format=tar HEAD' \
  "artifact_sha256=$artifact_digest" \
  'release_ref=refs/tags/v1.0.0-rc.1' \
  > "$lab_dir/build/evidence.env"

grep -Fqx "source_commit=$candidate_commit" "$lab_dir/build/evidence.env"
grep -Fqx "source_tree=$candidate_tree" "$lab_dir/build/evidence.env"
grep -Fqx "pipeline_blob=$pipeline_blob" "$lab_dir/build/evidence.env"
grep -Fqx "artifact_sha256=$artifact_digest" "$lab_dir/build/evidence.env"

cp "$lab_dir/build/candidate-one.tar" "$lab_dir/staging/application.tar"
cp "$lab_dir/build/evidence.env" "$lab_dir/staging/deployment.env"
test "$(sha256_file "$lab_dir/staging/application.tar")" = "$artifact_digest"

printf 'environment\tattempt\texpected_digest\tactual_digest\tresult\n' \
  > "$lab_dir/build/promotion-attempts.tsv"
printf 'staging\t1\t%s\t%s\taccepted\n' \
  "$artifact_digest" "$artifact_digest" \
  >> "$lab_dir/build/promotion-attempts.tsv"
cp "$lab_dir/build/candidate-one.tar" "$lab_dir/production/application.tar"
printf 'production\t1\t%s\t%s\taccepted\n' \
  "$artifact_digest" "$(sha256_file "$lab_dir/production/application.tar")" \
  >> "$lab_dir/build/promotion-attempts.tsv"
awk -F '\t' 'NR > 1 && ($3 != $4 || $5 != "accepted") { exit 1 }' \
  "$lab_dir/build/promotion-attempts.tsv"

printf 'tampered after deployment\n' >> "$lab_dir/staging/application.tar"
test "$(sha256_file "$lab_dir/staging/application.tar")" != "$artifact_digest"
cp "$lab_dir/build/candidate-one.tar" "$lab_dir/staging/application.tar"
test "$(sha256_file "$lab_dir/staging/application.tar")" = "$artifact_digest"

printf 'tampered production copy\n' >> "$lab_dir/production/application.tar"
production_actual_digest="$(sha256_file "$lab_dir/production/application.tar")"
test "$production_actual_digest" != "$artifact_digest"
printf 'production\t2\t%s\t%s\tdenied\n' \
  "$artifact_digest" "$production_actual_digest" \
  >> "$lab_dir/build/promotion-attempts.tsv"
test "$(awk -F '\t' 'NR > 1 && $5 == "denied" { count++ } END { print count + 0 }' "$lab_dir/build/promotion-attempts.tsv")" = 1
cp "$lab_dir/build/candidate-one.tar" "$lab_dir/production/application.tar"
production_recovered_digest="$(sha256_file "$lab_dir/production/application.tar")"
test "$production_recovered_digest" = "$artifact_digest"
printf 'production\t3\t%s\t%s\taccepted\n' \
  "$artifact_digest" "$production_recovered_digest" \
  >> "$lab_dir/build/promotion-attempts.tsv"
test "$(awk -F '\t' 'NR > 1 && $5 == "accepted" { accepted++ } END { print accepted + 0 }' "$lab_dir/build/promotion-attempts.tsv")" = 3

git -C "$lab_dir/seed" switch --quiet main
printf 'post-build main change\n' > "$lab_dir/seed/CHANGELOG.md"
git -C "$lab_dir/seed" add CHANGELOG.md
git -C "$lab_dir/seed" commit --quiet -m "docs: advance main after candidate build"
new_main="$(git -C "$lab_dir/seed" rev-parse HEAD)"
test "$new_main" != "$base_commit"
test "$new_main" != "$candidate_commit"
git -C "$lab_dir/seed" push --quiet origin main

git -C "$lab_dir/runner" fetch --quiet origin
test "$(git -C "$lab_dir/runner" rev-parse origin/main)" = "$new_main"
test "$(git -C "$lab_dir/runner" rev-parse HEAD)" = "$candidate_commit"
grep -Fqx "source_commit=$candidate_commit" "$lab_dir/staging/deployment.env"
test "$(awk -F '\t' 'NR > 1 && $5 == "denied" { denied++ } END { print denied + 0 }' "$lab_dir/build/promotion-attempts.tsv")" = 1
test "$(awk -F '\t' 'NR > 1 && $1 == "production" && $5 == "accepted" { latest = $2 } END { print latest }' "$lab_dir/build/promotion-attempts.tsv")" = 3

printf 'Detached CI checkout, reproducible archive, manifest, per-environment promotion, and deployment verification passed.\n'
