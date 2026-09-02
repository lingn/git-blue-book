#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part6.XXXXXX")"
trap 'rm -rf "$lab_root"' EXIT
repo="$lab_root/project"
mkdir "$repo"

git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Git Blue Book Test"
git -C "$repo" config user.email "git-blue-book@example.invalid"
printf 'base\n' > "$repo/app.txt"
git -C "$repo" add app.txt
git -C "$repo" commit --quiet -m "feat: initialize project"

printf 'unfinished tracked work\n' >> "$repo/app.txt"
printf 'new untracked work\n' > "$repo/new.txt"
git -C "$repo" stash push --quiet -u -m "wip: engineering test"
test -z "$(git -C "$repo" status --short)"
test "$(git -C "$repo" stash list | wc -l | tr -d ' ')" = "1"
stash_oid="$(git -C "$repo" rev-parse stash@{0})"
test "$(git -C "$repo" cat-file -t "$stash_oid")" = "commit"
git -C "$repo" stash show --stat stash@{0} >/dev/null
git -C "$repo" stash apply --quiet stash@{0}
test -f "$repo/new.txt"
test -n "$(git -C "$repo" diff)"
git -C "$repo" restore app.txt
rm "$repo/new.txt"
git -C "$repo" stash drop --quiet stash@{0}

git -C "$repo" worktree add --quiet "$lab_root/hotfix" -b hotfix/payment main
test "$(git -C "$lab_root/hotfix" branch --show-current)" = "hotfix/payment"
common_dir() {
  local worktree="$1"
  local raw
  raw="$(git -C "$worktree" rev-parse --git-common-dir)"
  case "$raw" in
    /*) printf '%s\n' "$raw" ;;
    *) (cd "$worktree/$raw" && pwd -P) ;;
  esac
}
test "$(common_dir "$repo")" = "$(common_dir "$lab_root/hotfix")"
hotfix_real="$(cd "$lab_root/hotfix" && pwd -P)"
grep -F "$hotfix_real" <(git -C "$repo" worktree list --porcelain) >/dev/null
printf 'hotfix\n' > "$lab_root/hotfix/FIX.md"
git -C "$lab_root/hotfix" add FIX.md
git -C "$lab_root/hotfix" commit --quiet -m "fix: add payment correction"
hotfix_sha="$(git -C "$lab_root/hotfix" rev-parse HEAD)"
test "$(git -C "$repo" rev-parse hotfix/payment)" = "$hotfix_sha"
git -C "$repo" worktree remove "$lab_root/hotfix"

git -C "$repo" switch --quiet -c bisect-lab main
good_sha=""
bad_sha=""
for number in 1 2 3 4 5 6 7 8; do
  printf '%s\n' "$number" > "$repo/value.txt"
  git -C "$repo" add value.txt
  git -C "$repo" commit --quiet -m "value: $number"
  if test "$number" = "1"; then
    good_sha="$(git -C "$repo" rev-parse HEAD)"
  fi
  if test "$number" = "5"; then
    bad_sha="$(git -C "$repo" rev-parse HEAD)"
  fi
done

cat > "$repo/.git/bisect-test.sh" <<'SCRIPT'
#!/usr/bin/env bash
test "$(cat value.txt)" -lt 5
SCRIPT
chmod +x "$repo/.git/bisect-test.sh"
git -C "$repo" bisect start >/dev/null
git -C "$repo" bisect bad >/dev/null
git -C "$repo" bisect good "$good_sha" >/dev/null
git -C "$repo" bisect run "$repo/.git/bisect-test.sh" >/dev/null
test "$(git -C "$repo" rev-parse HEAD)" = "$bad_sha"
git -C "$repo" bisect log > "$lab_root/bisect-session.log"
grep -F "$good_sha" "$lab_root/bisect-session.log" >/dev/null
grep -F "$bad_sha" "$lab_root/bisect-session.log" >/dev/null
git -C "$repo" bisect reset >/dev/null

git -C "$repo" switch --quiet -c release/1.x main
printf 'release context\n' > "$repo/RELEASE.md"
git -C "$repo" add RELEASE.md
git -C "$repo" commit --quiet -m "docs: add release context"
git -C "$repo" cherry-pick --quiet "$hotfix_sha"
picked_sha="$(git -C "$repo" rev-parse HEAD)"
test "$picked_sha" != "$hotfix_sha"
test -f "$repo/FIX.md"
test -z "$(git -C "$repo" status --short)"

printf 'Part 6 stash, worktree, bisect, and hotfix migration experiments passed.\n'
