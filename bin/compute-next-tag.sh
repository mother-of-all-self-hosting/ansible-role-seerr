#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Prints the tag that the currently checked out commit should be released as,
# or nothing at all if it does not warrant a release.
#
# Usage: bin/compute-next-tag.sh
#
# Tags look like `v<seerr version>-<release>`, which is what this repository has
# always published (v3.1.0-0 ... v3.4.1-0):
#
# - if defaults/main.yml points at a Seerr version that has never been released,
#   the release counter restarts at 0 (`v3.5.0-0`)
# - otherwise the counter is incremented (`v3.5.0-1`), but only if something
#   that actually affects the role has changed since the last release
#
# Determining the version from defaults/main.yml, rather than from the commit
# message of the pull request that got merged, makes the result independent of
# the order in which pull requests get merged, and lets any change to the role
# (bugfix, feature, dependency bump) release itself without a human tagging.
#
# The commit-message approach this replaced read a version out of any Renovate
# subject of the shape "Update ... Docker tag to ...". It published `v3.14.6-0`
# off "Update python Docker tag to v3.14.6" - the `.python-version` bump for the
# Molecule tooling - while defaults/main.yml said 3.3.0 all along. That tag is
# still in this repository, and under semver ordering it outranks every real
# release, so the test suite keeps it as a fixture.

set -euo pipefail

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repository_path"

defaults_path='defaults/main.yml'

# Paths that shape the behavior of the role for its consumers. A commit
# touching only other paths (a README fix, CI configuration, Molecule tests)
# does not change what a playbook run does, and releasing it would only create
# churn in the repositories that consume this role.
role_defining_paths=(
	'defaults'
	'meta'
	'tasks'
	'templates'
)

# Anchored on `seerr_version:` so that `seerr_container_image_tag`, which is
# derived from it, cannot be mistaken for it.
version="$(sed -nE 's|^seerr_version:[[:space:]]*"?([^"[:space:]]+)"?.*$|\1|p' "$defaults_path" | head -n1)"

if [ -z "$version" ]; then
	echo >&2 "Could not determine the Seerr version from $defaults_path"
	exit 1
fi

# Seerr's version is carried with a leading `v` here (`seerr_version: v3.4.1`),
# and the tags carry one too. Strip it before rebuilding the prefix, so that
# neither convention can produce a doubled or a missing `v`.
tag_prefix="v${version#v}-"

# Of all releases of this version, the highest release number. Sorted
# numerically, so that -10 is recognized as newer than -9.
last_release="$(git tag --list "${tag_prefix}*" | sed -e "s|^${tag_prefix}||" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"

if [ -z "$last_release" ]; then
	echo >&2 "Version $version has never been released"
	echo "${tag_prefix}0"
	exit 0
fi

previous_tag="${tag_prefix}${last_release}"

if git diff --quiet "$previous_tag" HEAD -- "${role_defining_paths[@]}"; then
	echo >&2 "Nothing affecting the role has changed since $previous_tag"
	exit 0
fi

echo >&2 "The role has changed since $previous_tag"
echo "${tag_prefix}$((last_release + 1))"
