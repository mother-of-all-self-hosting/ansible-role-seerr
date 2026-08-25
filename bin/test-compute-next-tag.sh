#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Exercises bin/compute-next-tag.sh against throwaway git repositories.
#
# Usage: bin/test-compute-next-tag.sh
#
# Every scenario creates a repository in a temporary directory, gives it role
# files and a release history, and then replays a series of merges through the
# real script, tagging as it goes just like the autotag workflow does. This
# repository is never touched and no network access is needed.

set -euo pipefail

script_under_test="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/compute-next-tag.sh"

failures=0
workdir=''

cleanup() {
	cd /
	if [ -n "$workdir" ]; then
		rm -rf "$workdir"
		workdir=''
	fi
}

trap cleanup EXIT

# Starts a scenario with a repository at Seerr v3.4.1 which has already seen one
# release of it (v3.4.1-0), plus the `v3.14.6-0` tag this repository really
# carries from the era when the version was read out of Renovate's commit
# subjects - it was cut off "Update python Docker tag to v3.14.6", the
# `.python-version` bump. It is not a release of anything and must never be
# counted as one, which matters more than usual here: under semver ordering
# 3.14.6 outranks every version Seerr has ever had.
#
# The defaults file deliberately carries the traps this role's real one has: the
# `# renovate:` annotation that Renovate rewrites, and an image tag derived from
# the version variable. Neither may be picked up as the version.
scenario() {
	echo "$1"

	cleanup
	workdir="$(mktemp -d)"

	mkdir -p "$workdir/bin" "$workdir/defaults" "$workdir/tasks" "$workdir/templates"
	cp "$script_under_test" "$workdir/bin/"
	cd "$workdir"

	git init -q -b main .
	git config user.email 'test@example.com'
	git config user.name 'Test'
	git config commit.gpgsign false

	cat > defaults/main.yml <<-'YAML'
		# renovate: datasource=docker depName=ghcr.io/seerr-team/seerr versioning=semver
		seerr_version: v3.4.1

		seerr_container_image: "{{ seerr_container_image_registry_prefix }}seerr-team/seerr:{{ seerr_container_image_tag }}"
		seerr_container_image_tag: "{{ seerr_version }}"
	YAML
	printf 'placeholder\n' > tasks/main.yml
	printf 'placeholder\n' > templates/env.j2
	printf 'placeholder\n' > README.md

	git add -A
	git commit -qm 'Initial commit'

	local tag
	for tag in v3.14.6-0 v3.4.1-0; do
		git tag "$tag"
	done
}

# Applies a change, commits it, and tags whatever the script says it should be.
# Prints the tag, or nothing when the script decided against a release.
merge() {
	local change="$1" tag

	eval "$change"
	git add -A
	git commit -qm 'Merge'

	tag="$(bin/compute-next-tag.sh 2>/dev/null)"

	if [ -n "$tag" ]; then
		git tag "$tag"
	fi

	printf '%s' "$tag"
}

expect() {
	local description="$1" expected="$2" actual="$3"

	if [ "$actual" = "$expected" ]; then
		printf '  ok   | %s -> %s\n' "$description" "${actual:-no release}"
	else
		printf '  FAIL | %s -> expected %s, got %s\n' "$description" "${expected:-no release}" "${actual:-no release}"
		failures=$((failures + 1))
	fi
}

bump_version="sed -i 's|^seerr_version: v3.4.1|seerr_version: v3.5.0|' defaults/main.yml"
revert_version="sed -i 's|^seerr_version: v3.5.0|seerr_version: v3.4.1|' defaults/main.yml"
edit_task="printf 'a task\n' >> tasks/main.yml"
edit_template="printf 'a line\n' >> templates/env.j2"
edit_readme="printf 'documentation\n' >> README.md"
edit_script="printf '# a comment\n' >> bin/compute-next-tag.sh"

# The two merge orders below apply the same updates and must each end up with
# every update released exactly once, whichever order they arrive in.

scenario 'A version bump merged before other role changes'
expect 'version bump' v3.5.0-0 "$(merge "$bump_version")"
expect 'task edit'    v3.5.0-1 "$(merge "$edit_task")"
expect 'template'     v3.5.0-2 "$(merge "$edit_template")"

scenario 'A version bump merged after other role changes'
expect 'task edit'    v3.4.1-1 "$(merge "$edit_task")"
expect 'version bump' v3.5.0-0 "$(merge "$bump_version")"

# `v3.14.6-0` exists in every scenario. Nothing may ever continue its counter,
# and the version must keep coming from defaults/main.yml rather than from
# whichever tag happens to sort highest.
scenario 'The bogus tag left over from the commit-message era'
expect 'a task' v3.4.1-1 "$(merge "$edit_task")"

# The version variable is not the only version-shaped thing in defaults/main.yml,
# and the image tag is derived from it with Jinja. Pinning the image tag to a
# literal of its own is the shape a refactor that read the wrong line would take,
# so the release must still be numbered off `seerr_version:`.
scenario 'The derived image tag is not mistaken for the version'
pin_image_tag="sed -i 's|^seerr_container_image_tag: .*|seerr_container_image_tag: v9.9.9|' defaults/main.yml"
expect 'image tag pinned' v3.4.1-1 "$(merge "$pin_image_tag")"

scenario 'Commits that do not affect the role'
expect 'README'   ''        "$(merge "$edit_readme")"
expect 'a script' ''        "$(merge "$edit_script")"
expect 'a task'   v3.4.1-1  "$(merge "$edit_task")"

scenario 'Release numbers past 9'
for release_number in 1 2 3 4 5 6 7 8 9 10; do
	git tag "v3.4.1-$release_number"
done
expect 'a task' v3.4.1-11 "$(merge "$edit_task")"

scenario 'Reverting to an already released version'
merge "$bump_version" > /dev/null
# The role is now identical to what v3.4.1-0 already published, so there is
# nothing new to release.
expect 'a revert' ''        "$(merge "$revert_version")"

scenario 'Reverting to an already released version, with a change'
merge "$bump_version" > /dev/null
expect 'a revert' v3.4.1-1 "$(merge "$revert_version && $edit_task")"

if [ "$failures" -gt 0 ]; then
	echo >&2 "$failures scenario(s) behaved unexpectedly"
	exit 1
fi

echo 'All scenarios behaved as expected'
