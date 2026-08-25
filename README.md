<!--
SPDX-FileCopyrightText: 2023 Slavi Pantaleev
SPDX-FileCopyrightText: 2025 spatterlight
SPDX-FileCopyrightText: 2025, 2026 Suguru Hirahara

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Seerr Ansible role

This is an [Ansible](https://www.ansible.com/) role which installs [Seerr](https://github.com/seerr-team/seerr), a media request management application, to run as a [Docker](https://www.docker.com/) container wrapped in a systemd service.

This role *implicitly* depends on:

- [`com.devture.ansible.role.playbook_help`](https://github.com/devture/com.devture.ansible.role.playbook_help)
- [`com.devture.ansible.role.systemd_docker_base`](https://github.com/devture/com.devture.ansible.role.systemd_docker_base)

Check [`defaults/main.yml`](defaults/main.yml) for the full list of supported options.

💡 For an Ansible playbook which integrates this role and makes it easier to use, see the [Mother-of-All-Self-Hosting Ansible playbook](https://github.com/mother-of-all-self-hosting/mash-playbook).

## Development

### pre-commit

You can optionally install a Git pre-commit hook (via [mise](https://mise.jdx.dev/) + [prek](https://prek.j178.dev/)) that runs formatting and linting checks before each commit. See [`.pre-commit-config.yaml`](./.pre-commit-config.yaml) for which hooks are to be executed.

To install the hook, run the [`just`](https://github.com/casey/just) command below:

```sh
just prek-install-git-pre-commit-hook
```

### Molecule

This role supports [Molecule](https://docs.ansible.com/projects/molecule/), an Ansible testing framework designed for developing and testing Ansible collections, playbooks, and roles.

Refer to [this page](./molecule/README.md) for details about how to utilize it.

### Releases

Release tags (`v<Seerr version>-<release>`) are cut automatically by [`.github/workflows/autotag.yml`](./.github/workflows/autotag.yml) when a commit lands on the `main` branch. The tag is derived from the state of the repository — the `seerr_version` value in [`defaults/main.yml`](defaults/main.yml) and the tags that already exist — rather than from commit messages, so it does not depend on the order in which pull requests get merged:

- a `seerr_version` that has never been released is tagged `-0`
- otherwise the release counter is incremented, but only when something under `defaults/`, `meta/`, `tasks/` or `templates/` actually changed since the previous release; documentation and CI changes do not create a release

To see what the current checkout would be released as, run [`bin/compute-next-tag.sh`](./bin/compute-next-tag.sh). Its behavior is covered by `bin/test-compute-next-tag.sh`, which runs as a pre-commit hook whenever that script or `defaults/main.yml` changes.
