FROM mcr.microsoft.com/devcontainers/base:3.0.8-ubuntu24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends jq python3 python3-venv ripgrep \
    && apt-get clean

ARG COPILOT_VERSION=1.0.92
RUN set -eu; \
    case "$(uname -m)" in \
        x86_64) arch=x64 ;; \
        aarch64) arch=arm64 ;; \
        *) echo "Unsupported Copilot CLI architecture" >&2; exit 1 ;; \
    esac; \
    mkdir /opt/copilot-cli-install; \
    cd /opt/copilot-cli-install; \
    curl -fsSL --retry 3 -O "https://github.com/github/copilot-cli/releases/download/v${COPILOT_VERSION}/copilot-linux-${arch}.tar.gz"; \
    curl -fsSL --retry 3 -O "https://github.com/github/copilot-cli/releases/download/v${COPILOT_VERSION}/SHA256SUMS.txt"; \
    sha256sum --check --ignore-missing SHA256SUMS.txt; \
    tar -xzf "copilot-linux-${arch}.tar.gz" -C /usr/local/bin; \
    chmod 0755 /usr/local/bin/copilot; \
    copilot --version; \
    rm -- "copilot-linux-${arch}.tar.gz" SHA256SUMS.txt; \
    cd /; \
    rmdir /opt/copilot-cli-install
