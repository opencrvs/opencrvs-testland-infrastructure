
> [!NOTE]
> Please keep your infrastructure repository up to date with OpenCRVS Core version.
> Always update infrastructure to same version as OpenCRVS Core.

---

# General Information

This document provides guidance on running OpenCRVS on server environments using Kubernetes. It is intended for System Administrators and DevOps engineers deploying OpenCRVS in various environments.

> [!WARNING]
> For comprehensive documentation, installation guides, and infrastructure setup instructions, please refer to the **[Official OpenCRVS Documentation](https://documentation.opencrvs.org/)**.

# Repository content

- **[infrastructure](infrastructure): Infrastructure-as-code scripts (ansible) and resources for provisioning and managing foundational services (such as databases, networks, or storage).**
- [environments](environments): Template folder to store helm values configurations for different environments (e.g., development, staging, production).
- [examples](examples): Pre-defined values for Helm charts and additional documentation or deployment scenarios for OpenCRVS.
- [scripts](scripts): Utility scripts for OpenCRVS bootstrap and some one time maintenance tasks.

> [!NOTE]
> The OpenCRVS Core and Country config template repositories each have their own Tiltfile.


# Additional resources

- [Official documentation](https://documentation.opencrvs.org/)
- [OpenCRVS Helm Chart README](https://github.com/opencrvs/opencrvs-core/blob/develop/charts/opencrvs-services/README.md)
- [Dependencies Helm Chart README](https://github.com/opencrvs/opencrvs-core/blob/develop/charts/dependencies/README.md)
- [Cloud Infrastructure](https://github.com/opencrvs/cloud-infrastructure), Additional repository with terraform templates and other tools to deploy OpenCRVS on Cloud Providers.
