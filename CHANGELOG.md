# Changelog

## 2.1.0 Release

### Improvements

- Added Ubuntu 26.04 support to OpenCRVS infrastructure [#13111](https://github.com/opencrvs/opencrvs-core/issues/13111)
- Upgraded Kubernetes to v1.36 [#13177](https://github.com/opencrvs/opencrvs-core/issues/13177)

## 2.0.1 Release

### New features

- Migration script to convert backup files taken by OS cronjob into k8s compatible format [#13099](https://github.com/opencrvs/opencrvs-core/issues/13099)

### Bug fixes

- Always restart the Kubernetes self-hosted runner during deployment to ensure the latest runner image and configuration changes are applied. [#332](https://github.com/opencrvs/infrastructure/pull/332)
- Testing outbound HTTPS connectivity instead of ping [#338](https://github.com/opencrvs/infrastructure/pull/338)
