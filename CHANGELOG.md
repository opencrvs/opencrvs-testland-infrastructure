# Changelog

## 2.2.0 Release Candidate

### New features

- Container registry other than Docker Hub. The `DOCKERHUB_ACCOUNT`, `DOCKERHUB_REPO`, `DOCKER_USERNAME` and `DOCKER_TOKEN` secrets are renamed to `REGISTRY_ORGANISATION`, `REGISTRY_REPOSITORY`, `REGISTRY_USERNAME` and `REGISTRY_TOKEN`, the new variable `REGISTRY_HOST` (default `docker.io`) sets the registry, and the pull secret is now `registry-credentials`. The secrets migration workflow copies the secrets, and `dockerhub-credentials` is still created next to the new pull secret [#14209](https://github.com/opencrvs/opencrvs-core/issues/14209)

### Improvements

- The manual approval of GitHub Actions workflows is now required unless the `APPROVAL_REQUIRED` environment variable is explicitly set to `false`, and the user who started a workflow can no longer approve it. The `GH_APPROVERS` variable must list at least one user other than the person starting the workflow (at least 3 for `Clear all environment data`, so 4 users in total)

### Bug fixes

- Backup and restore workflows no longer read the non-existent `job-name` input in the approval step, the approval issue title and text now describe the operation
- `convert-backup.sh` no longer leaves decrypted backup data on the backup server (all plaintext is kept in a private temporary directory that is always removed on exit) and no longer passes the passphrase on the command line
- Backup rotation on the backup server no longer runs as root. The script is installed root-owned as `/usr/local/sbin/opencrvs-rotate-backups.sh`, the cron job runs as `backup`, and directory names are matched strictly and passed to `rm` NUL-delimited.
- Restore, Deploy OpenCRVS, Validate pre/post deploy, Reset 2FA and Start a new release workflows check their text inputs (backup date, image tags, stage, user name, release version and target branch) against the expected format and pass them to scripts as environment variables. The backup date check in Restore now reads the `backup-date` input, and the `reset-2fa.yml` playbook checks the user name as well
- Pre-deploy validation in the Deploy OpenCRVS workflow now starts after the approval step
- Two-factor authentication set-up is now done by sshd (`ForceCommand`, `/usr/local/sbin/opencrvs-require-2fa.sh`) and not by `.profile`. A user that has not set it up yet can only open an interactive login, where the set-up starts. Commands, `scp`, `sftp` and `ssh -T` ask the user to log in interactively first. The provisioning user, the backup user and users with `two_factor: false` are not affected. A script that logs in as any other user must use a user with `two_factor: false`
- Users with the `operator` role no longer get sudo rules for `cat`, `less` and `tail`, which could be escalated to a root shell or used to read any file. Operators are now members of the `adm` group, so `less`, `tail` and `cp` read system logs in `/var/log` and the journal without sudo. Container logs are available with `kubectl logs`, and `/opt/opencrvs` is already readable by everyone. Access to `/data` through sudo is removed, and previously created operator sudoers files are deleted when the playbook runs
- SSH keys of users are now exactly the `ssh_keys` of the inventory, so a removed key loses access when the playbook runs with the `users` tag. When `additional_keys_for_provisioning_user` is set, it replaces all keys of the provisioning user and must include the key the provisioning connects with. Removed users lose their sudo rules, `~/.ssh` and `~/.kube`

## 2.1.0 Release

### Improvements

- Added Ubuntu 26.04 support to OpenCRVS infrastructure [#13111](https://github.com/opencrvs/opencrvs-core/issues/13111)
- Upgraded Kubernetes to v1.36 [#13177](https://github.com/opencrvs/opencrvs-core/issues/13177)
- Upgraded Traefik helm chart to 41.0.2 [#13291](https://github.com/opencrvs/opencrvs-core/issues/13291)
- Retrieve ENCRYPTION_KEY from backup server [#10927](https://github.com/opencrvs/opencrvs-core/issues/10927)

### Bug fixes

- Make provision user and group ids not rely on hardcoded values [#13192](https://github.com/opencrvs/opencrvs-core/issues/13192)

## 2.0.2 Release

## 2.0.1 Release

### New features

- Migration script to convert backup files taken by OS cronjob into k8s compatible format [#13099](https://github.com/opencrvs/opencrvs-core/issues/13099)

### Bug fixes

- Always restart the Kubernetes self-hosted runner during deployment to ensure the latest runner image and configuration changes are applied. [#332](https://github.com/opencrvs/infrastructure/pull/332)
- Testing outbound HTTPS connectivity instead of ping [#338](https://github.com/opencrvs/infrastructure/pull/338)
- Run differencial backup as non-root user after pgbackrest upgrade [#360](https://github.com/opencrvs/infrastructure/pull/360) [#13370](https://github.com/opencrvs/opencrvs-core/pull/13370)