# Changelog

## 2.1.0 Release

### Improvements

- Added Ubuntu 26.04 support to OpenCRVS infrastructure [#13111](https://github.com/opencrvs/opencrvs-core/issues/13111)
- Upgraded Kubernetes to v1.36 [#13177](https://github.com/opencrvs/opencrvs-core/issues/13177)
- Upgraded Traefik helm chart to 41.0.2 [#13291](https://github.com/opencrvs/opencrvs-core/issues/13291)
- Retrieve ENCRYPTION_KEY from backup server [#10927](https://github.com/opencrvs/opencrvs-core/issues/10927)

## 2.0.1 Release

### New features

- Migration script to convert backup files taken by OS cronjob into k8s compatible format [#13099](https://github.com/opencrvs/opencrvs-core/issues/13099)

### Bug fixes

- Always restart the Kubernetes self-hosted runner during deployment to ensure the latest runner image and configuration changes are applied. [#332](https://github.com/opencrvs/infrastructure/pull/332)
- Testing outbound HTTPS connectivity instead of ping [#338](https://github.com/opencrvs/infrastructure/pull/338)
- Run differencial backup as non-root user after pgbackrest upgrade [#360](https://github.com/opencrvs/infrastructure/pull/360) [#13370](https://github.com/opencrvs/opencrvs-core/pull/13370)