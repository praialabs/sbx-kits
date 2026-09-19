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
sbx run agents/<kit-dir>
```

For example, to run the `agy` (Google Antigravity CLI) kit:

```bash
sbx run agents/agy
```

### Remote Git Reference

Docker Sandbox supports fetching kits directly from remote Git repositories. You can reference kits in this repository using the following syntax pattern:

> [!IMPORTANT]
> As of [`sbx` v0.34.0](https://github.com/docker/sbx-releases/releases/tag/v0.34.0#:~:text=Breaking%3A%20installing%20a%20kit%20from%20another%20registry%20or%20a%20Git%20URL%20fails%20until%20you%20add%20its%20prefix%20with%20sbx%20settings%20set%20kit.allowedSources), you need to explicitly allow the kit source before using it:
> ```
> sbx settings set kit.allowedSources '["docker.io/","github.com/praialabs/"]'
> ```

```bash
sbx run 'git+https://github.com/praialabs/sbx-kits.git#dir=agents/<kit-dir>'
```

Example (composing the `agy` agent kit with the `default-allow-policies` mixin kit):

```bash
sbx run 'git+https://github.com/praialabs/sbx-kits.git#dir=agents/agy' \
  --kit 'git+https://github.com/praialabs/sbx-kits.git#dir=mixins/default-allow-policies'
```

For more details on Git remote references, see the [Docker Sandboxes Git Repository Documentation](https://docs.docker.com/ai/sandboxes/customize/kits/#git-repository).

## Custom Template

This repository provides a custom sandbox template tailored for Elixir development with the Google Antigravity CLI (`agy`).

The [agy-elixir/Dockerfile](./templates/agy-elixir/Dockerfile) extends `docker/sandbox-templates:shell-docker` and pre-bakes the Elixir runtime environment, the Antigravity CLI, and additional tooling into the image to avoid repetitive installation steps.

### Building the Template Locally

We manage building the template image using **Docker Bake**, which ships with Docker and automatically handles building the image using a declarative file:

```bash
docker buildx bake
```

You can use environment variables to override specific tool versions during the build process:

```bash
ERLANG_VERSION=latest:28 ELIXIR_VERSION=1.19-otp-28 docker buildx bake
```

Once built, you can stream the image directly into the local `sbx` runtime image store:

```bash
docker image save praialabs/sandbox-templates:agy-elixir-docker | sbx template load /dev/stdin
```

### Combining Kits and Templates

To spin up the Google Antigravity CLI sandbox with Elixir, Erlang, and pre-configured network allow-policies, run:

```bash
sbx run 'git+https://github.com/praialabs/sbx-kits.git#dir=agents/agy' \
  --kit 'git+https://github.com/praialabs/sbx-kits.git#dir=mixins/default-allow-policies' \
  --template praialabs/sandbox-templates:agy-elixir-docker
```
