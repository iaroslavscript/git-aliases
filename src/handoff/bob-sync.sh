#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/bob/repos/project}" # bob's clone (work tree clone is fine)
HANDOFF_REMOTE="${HANDOFF_REMOTE:-handoff}" # local bare repo remote
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}" # GitHub remote

# Mirror directions
MIRROR_WORK_TO_ORIGIN="${MIRROR_WORK_TO_ORIGIN:-1}" # 1 = push handoff branches -> GitHub (for PRs)
MIRROR_PROTECTED_TO_HANDOFF="${MIRROR_PROTECTED_TO_HANDOFF:-1}" # 1 = push protected branches GitHub -> handoff# Work-branch selection (optional)
BRANCH_PREFIX="${BRANCH_PREFIX:-}" # e.g. "tom/" to only mirror tom/*

# Protected branches (space-separated globs, bash-style)
PROTECTED_BRANCH_GLOBS="${PROTECTED_BRANCH_GLOBS:-main master release/* hotfix/*}"

# If tom rewrites branch history and you want to mirror it exactly, enable force-with-lease
PUSH_FORCE="${PUSH_FORCE:-0}" # 1 = use --force-with-lease for work branches

# Signed attestation tags for protected branches (bob signing key)
PUSH_TAGS="${PUSH_TAGS:-0}" # 1 = create signed tags on protected branch updates
TAG_PREFIX="${TAG_PREFIX:-approved/}" # e.g. approved/main/20260216T120000Z

# State tracking to avoid resurrecting branches deleted on origin.
STATE_DIR="${STATE_DIR:-$REPO_DIR/.sign-bot}"
PUBLISHED_FILE="$STATE_DIR/origin-published.txt" # branches we've seen existing on origin at least once
TOMBSTONE_FILE="$STATE_DIR/origin-tombstoned.txt" # branches seen deleted on origin after being published
ALLOW_RESURRECT_DELETED_BRANCHES="${ALLOW_RESURRECT_DELETED_BRANCHES:-0}" # 1 = allow recreating deleted origin branches
DELETE_TOMBSTONED_FROM_HANDOFF="${DELETE_TOMBSTONED_FROM_HANDOFF:-0}" # 1 = delete tombstoned work branches from handoff

cd "$REPO_DIR"

mkdir -p "$STATE_DIR"
touch "$PUBLISHED_FILE" "$TOMBSTONE_FILE"

is_protected_branch() {
	local branch="$1"
	local pat

	for pat in $PROTECTED_BRANCH_GLOBS; do
		[[ "$branch" == $pat ]] && return 0
	done
	return 1
}

is_sane_branch_name() {
	local branch="$1"

	[[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
	[[ "$branch" != *".."* ]] || return 1
	[[ "$branch" != *"@{"* ]] || return 1
	return 0
}

state_contains() {
	local file="$1"
	local value="$2"

	[[ -f "$file" ]] || return 1
	grep -Fxq -- "$value" "$file"
}

state_add() {
	local file="$1"
	local value="$2"

	mkdir -p "$(dirname "$file")"
	touch "$file"
	state_contains "$file" "$value" || printf '%s\n' "$value" >>"$file"
}

state_remove() {
	local file="$1"
	local value="$2"

	[[ -f "$file" ]] || return 0
	state_contains "$file" "$value" || return 0

	# Only attempt removal if the value exists to avoid unnecessary file writes.
	if grep -Fxq -- "$value" "$file"; then
		local tmp
		tmp="$(mktemp)"
		grep -Fxv -- "$value" "$file" >"$tmp" || true
		mv "$tmp" "$file"
	fi
}

# Hardening: never run hooks from this repo content
git config core.hooksPath /dev/null >/dev/null
git config fetch.fsckObjects true >/dev/null || true
git config transfer.fsckObjects true >/dev/null || true

# If PUSH_TAGS=1, ensure signing is on (SSH signing configured elsewhere via gpg.format=ssh)
if [[ "$PUSH_TAGS" == "1" ]]; then
	git config tag.gpgsign true >/dev/null
fi

git fetch --prune "$ORIGIN_REMOTE"
git fetch --prune "$HANDOFF_REMOTE"

# Record current origin work branches as "seen" so that if they are later deleted on origin,
# we can treat that deletion as intentional and avoid resurrecting them from handoff.
mapfile -t _origin_branches_seen < <(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$ORIGIN_REMOTE/" | sort)
for _branch in "${_origin_branches_seen[@]}"; do
	[[ "$_branch" == "HEAD" ]] && continue
	[[ -n "$BRANCH_PREFIX" && "$_branch" != "$BRANCH_PREFIX"* ]] && continue
	is_protected_branch "$_branch" && continue
	is_sane_branch_name "$_branch" || continue
	state_add "$PUBLISHED_FILE" "$_branch"
	state_remove "$TOMBSTONE_FILE" "$_branch"
done
unset _origin_branches_seen _branch

failed=0

# 1) Mirror work branches from handoff -> origin (for PRs)
if [[ "$MIRROR_WORK_TO_ORIGIN" == "1" ]]; then
	mapfile -t handoff_branches < <(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$HANDOFF_REMOTE/" | sort)
	for branch in "${handoff_branches[@]}"; do
		[[ "$branch" == "HEAD" ]] && continue
		[[ -n "$BRANCH_PREFIX" && "$branch" != "$BRANCH_PREFIX"* ]] && continue
		if ! is_sane_branch_name "$branch"; then
			echo "Skip suspicious branch name from handoff: $branch" >&2
			continue
		fi
	
		if is_protected_branch "$branch"; then
			echo "Skip protected branch from handoff -> origin: $branch"
			continue
		fi
		
		if [[ "$ALLOW_RESURRECT_DELETED_BRANCHES" != "1" ]] && state_contains "$TOMBSTONE_FILE" "$branch"; then
			echo "Skip tombstoned branch (deleted on origin): $branch"
			continue
		fi

		src_ref="refs/remotes/$HANDOFF_REMOTE/$branch"
		dst_ref="refs/heads/$branch"
		src_sha="$(git rev-parse "$src_ref")"
		dst_sha=""

		if git show-ref --verify --quiet "refs/remotes/$ORIGIN_REMOTE/$branch"; then
			dst_sha="$(git rev-parse "refs/remotes/$ORIGIN_REMOTE/$branch")"
		fi

		# If we have previously published this branch to origin and it is now missing on origin,
		# treat it as intentionally deleted and do not recreate it from handoff.
		if [[ -z "$dst_sha" ]] && state_contains "$PUBLISHED_FILE" "$branch" && [[ "$ALLOW_RESURRECT_DELETED_BRANCHES" != "1" ]]; then
			echo "Origin branch missing; tombstoning to avoid resurrection: $branch"
			state_add "$TOMBSTONE_FILE" "$branch"
			if [[ "$DELETE_TOMBSTONED_FROM_HANDOFF" == "1" ]]; then
				echo "Deleting tombstoned branch from handoff: $branch"
				git push "$HANDOFF_REMOTE" ":refs/heads/$branch" || failed=1
			fi
			continue
		fi

		if [[ -n "$dst_sha" && "$src_sha" == "$dst_sha" ]]; then
			echo "No change (work) $branch"
			continue
		fi

		echo "Mirror work branch: $HANDOFF_REMOTE/$branch -> $ORIGIN_REMOTE/$branch"
		push_ok=1

		if [[ "$PUSH_FORCE" == "1" ]]; then
			git push --force-with-lease="$dst_ref" "$ORIGIN_REMOTE" "$src_ref:$dst_ref" || push_ok=0
		else
			git push "$ORIGIN_REMOTE" "$src_ref:$dst_ref" || push_ok=0
		fi

		if [[ "$push_ok" == "1" ]]; then
			state_add "$PUBLISHED_FILE" "$branch" state_remove "$TOMBSTONE_FILE" "$branch"
		else
			failed=1
		fi
	done
fi

# 2) Mirror protected branches from origin -> handoff (so tom can fetch without GitHub)
if [[ "$MIRROR_PROTECTED_TO_HANDOFF" == "1" ]]; then
	mapfile -t origin_branches < <(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$ORIGIN_REMOTE/" | sort)
	for branch in "${origin_branches[@]}"; do
		[[ "$branch" == "HEAD" ]] && continue
		is_protected_branch "$branch" || continue

		if ! is_sane_branch_name "$branch"; then
			echo "Skip suspicious branch name from origin: $branch" >&2
			continue
		fi

		src_ref="refs/remotes/$ORIGIN_REMOTE/$branch"
		dst_ref="refs/heads/$branch"

		src_sha="$(git rev-parse "$src_ref")"
		dst_sha=""

		if git show-ref --verify --quiet "refs/remotes/$HANDOFF_REMOTE/$branch"; then
			dst_sha="$(git rev-parse "refs/remotes/$HANDOFF_REMOTE/$branch")"
		fi

		if [[ -n "$dst_sha" && "$src_sha" == "$dst_sha" ]]; then
			echo "No change (protected) $branch"
			continue
		fi

		echo "Mirror protected branch: $ORIGIN_REMOTE/$branch -> $HANDOFF_REMOTE/$branch"
		git push "$HANDOFF_REMOTE" "$src_ref:$dst_ref" || failed=1

		if [[ "$PUSH_TAGS" == "1" ]]; then

			# Check if the commit already has an 'approved/' tag
			if ! git tag --points-at "$src_sha" | grep -q "^${TAG_PREFIX}${branch}/"; then
				ts="$(date -u +"%Y%m%dT%H%M%SZ")"
				tag="${TAG_PREFIX}${branch}/${ts}"
			
				git tag -s -m "Bob approves $branch at $ts" "$tag" "$src_sha"
				git push "$ORIGIN_REMOTE" "$tag" || failed=1
				git push "$HANDOFF_REMOTE" "$tag" || failed=1
			else
				echo "Commit $(git rev-parse --short "$src_sha") on $branch already tagged. Skiping."
			fi
		fi
	done
fi

exit "$failed"


