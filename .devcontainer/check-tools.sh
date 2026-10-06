#!/usr/bin/env bash
set -euo pipefail

for tool in az terraform copilot git gh node npm python3 jq rg curl ssh sshd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required tool is missing: %s\n' "$tool" >&2
        exit 1
    fi
done

az version
terraform version
copilot --version
git --version
gh --version
node --version
npm --version
python3 --version
python3 -m venv --help >/dev/null
jq --version
rg --version

printf '\nToolchain ready. No sign-in or deployment was performed. Start with docs/getting-started.md.\n'
