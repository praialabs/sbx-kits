# Praia Labs Docker Sandbox Kits

This repository contains custom Docker Sandbox Kits developed by [Praia Labs](https://praialabs.com) ([GitHub](https://github.com/praialabs)).

> [!WARNING]
> **Experimental Feature & Active Development**: Docker Sandboxes (`sbx`) and Kits are experimental features under active development. Syntax, CLI commands, and features may change regularly.

## Overview

Docker Sandbox Kits are declarative configurations used to customize and extend AI agent sandbox environments. This repository serves as a collection of custom kits tailored for various agent workflows.

To learn more about Docker Sandboxes and Kits, refer to the following official resources:
- [Docker Sandboxes Documentation](https://docs.docker.com/ai/sandboxes/)
- [Docker Sandbox Custom Kits Guide](https://docs.docker.com/ai/sandboxes/customize/kits/)
- [Official Contrib Repository (`docker/sbx-kits-contrib`)](https://github.com/docker/sbx-kits-contrib)

## Usage

You can run sandboxes with these custom kits either by referencing the local directory path or directly via the remote Git repository URL.

### Local Development / Usage

If you have cloned this repository locally, you can spin up a sandbox with a specific kit using:

```bash
sbx run --kit agents/<kit-dir> <agent-name>
```

For example, to run the `agy` (Google Antigravity CLI) kit:

```bash
sbx run --kit agents/agy agy
```

### Remote Git Reference

Docker Sandbox supports fetching kits directly from remote Git repositories. You can reference kits in this repository using the following syntax pattern:

```bash
sbx run --kit "git+https://github.com/praialabs/sbx-kits.git#dir=agents/<kit-dir>" <agent-name>
```

For more details on Git remote references, see the [Docker Sandboxes Git Repository Documentation](https://docs.docker.com/ai/sandboxes/customize/kits/#git-repository).
