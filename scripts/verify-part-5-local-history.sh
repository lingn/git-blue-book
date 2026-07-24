#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part5-local.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

git -C "$lab_dir" init --quiet --initial-branch=main
git -C "$lab_dir" config user.name "Git Blue Book Test"
git -C "$lab_dir" config user.email "git-blue-book@example.invalid"

printf 'version A\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: add version A"

printf 'discard me\n' > "$lab_dir/README.md"
git -C "$lab_dir" restore README.md
test "$(cat "$lab_dir/README.md")" = "version A"

printf 'version B\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
printf 'version C\n' > "$lab_dir/README.md"
git -C "$lab_dir" restore README.md
test "$(cat "$lab_dir/README.md")" = "version B"

git -C "$lab_dir" restore --staged README.md
test -z "$(git -C "$lab_dir" diff --staged)"
test -n "$(git -C "$lab_dir" diff)"
test "$(cat "$lab_dir/README.md")" = "version B"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: add version B"

before_amend="$(git -C "$lab_dir" rev-parse HEAD)"
printf 'amend test\n' > "$lab_dir/TEST.md"
git -C "$lab_dir" add TEST.md
git -C "$lab_dir" commit --quiet --amend --no-edit
after_content_amend="$(git -C "$lab_dir" rev-parse HEAD)"
test "$after_content_amend" != "$before_amend"
test "$(git -C "$lab_dir" show --format= --name-only HEAD | tr -d '\n')" = "README.mdTEST.md"

git -C "$lab_dir" commit --quiet --amend -m "docs: add version B with test"
after_message_amend="$(git -C "$lab_dir" rev-parse HEAD)"
test "$after_message_amend" != "$after_content_amend"
test "$(git -C "$lab_dir" log -1 --format=%s)" = "docs: add version B with test"

for number in 1 2 3; do
  printf 'step %s\n' "$number" > "$lab_dir/step-$number.txt"
  git -C "$lab_dir" add "step-$number.txt"
  git -C "$lab_dir" commit --quiet -m "docs: step $number"
done

cat > "$lab_dir/.git/sequence-editor.sh" <<'SCRIPT'
#!/usr/bin/env bash
sed -i.bak '1s/^pick /reword /' "$1"
rm "$1.bak"
SCRIPT
cat > "$lab_dir/.git/message-editor.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'docs: corrected step 1\n' > "$1"
SCRIPT
chmod +x "$lab_dir/.git/sequence-editor.sh" "$lab_dir/.git/message-editor.sh"

old_tip="$(git -C "$lab_dir" rev-parse HEAD)"
GIT_SEQUENCE_EDITOR="$lab_dir/.git/sequence-editor.sh" GIT_EDITOR="$lab_dir/.git/message-editor.sh" \
  git -C "$lab_dir" rebase --quiet -i HEAD~3
new_tip="$(git -C "$lab_dir" rev-parse HEAD)"
test "$new_tip" != "$old_tip"
test "$(git -C "$lab_dir" log -3 --format=%s | tail -1)" = "docs: corrected step 1"
test -z "$(git -C "$lab_dir" status --short)"

printf 'Part 5 restore, unstage, amend, and interactive rebase experiments passed.\n'
