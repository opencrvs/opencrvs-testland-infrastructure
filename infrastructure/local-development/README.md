# Developing Ansible playbooks & other infrastructure locally

In this directory, you will find all tooling, setup and guidance needed for developing OpenCRVS locally. This means you can iterate on Ansible playbooks without having to run slow Github pipelines again and again.

Currently, the setup supports MacOS and Ubuntu. For more instructions, start by opening the [provision.ipynb](./provision.ipynb) playbook.

## Prerequisites

### MacOS
1. Install [OrbStack](https://orbstack.dev)
2. Confirm the `orb` command is available on your command line
3. Install [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

### Ubuntu
1. Install [multipass](https://canonical.com/multipass/install)
2. Confirm installation with `multipass --version`
3. Install [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html#installing-ansible-on-debian)

## Not using provision.ipynb?

If you'd rather not use the Jupyter notebook, you can run the same steps manually from the command line. This is also useful if you want to see live output while provisioning.

### 1. Create and provision the VMs

- **MacOS**: `./provision-macos.sh`
- **Ubuntu**: `./provision-linux.sh`

Both scripts create `master` and `worker` VMs, set up a `provision` user on each, and generate an SSH keypair for Ansible to use. The private key is pulled to `./.ssh/ssh-key` automatically.

`provision-linux.sh` also updates `local.linux.yml` with the new VM IP addresses. On MacOS, `local.macos.yml` already points at `manager.orb.local` / `worker.orb.local`, so no update is needed.

### 2. Run the Ansible playbook

Pick the inventory file matching your OS (`local.macos.yml` or `local.linux.yml`) and the private key path from step 1:

```bash
ansible-playbook -i local.linux.yml ../server-setup/playbook.yml -vv --private-key ./.ssh/ssh-key
```

## Connecting to the VMs

### MacOS

```bash
orb shell master   # or worker
```

Or over SSH with the generated key:

```bash
ssh -i ./.ssh/ssh-key provision@master.orb.local   # or worker.orb.local
```

### Ubuntu

Get VM IP address
```bash
multipass info master   # or worker
```
Use ssh to connect:
```bash
ssh -i .ssh/ssh-key provision@<ip address>
```


Or same with single command:

```bash
ssh -i ./.ssh/ssh-key provision@$(multipass info master | awk '/IPv4/{print $2}')
```
