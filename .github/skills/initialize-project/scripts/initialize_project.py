#!/usr/bin/env python3
"""Create first-use local Terraform inputs without deploying or changing Fabric items."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def hcl_string(value):
    return json.dumps(value.replace("${", "$${").replace("%{", "%%{"))


def render_configuration(args, example):
    if (
        not re.fullmatch(r"[a-z][a-z0-9-]{1,14}[a-z0-9]", args.project_name)
        or "--" in args.project_name
    ):
        raise ValueError(
            "project-name must be 3-16 lowercase letters, digits or single hyphens, "
            "starting with a letter and ending with a letter or digit."
        )
    if not re.fullmatch(r"[a-z][a-z0-9]+", args.location):
        raise ValueError("location must be an explicit Azure region short name.")
    repository = re.fullmatch(
        r"([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9_.-]+)", args.github_repository
    )
    if not repository or repository[2] in (".", "..") or repository[2].endswith(".git"):
        raise ValueError("github-repository must be OWNER/REPO, without a URL or .git suffix.")
    for admin in args.capacity_admin:
        if not (
            re.fullmatch(r"[^@\s]+@[^@\s]+", admin)
            or re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", admin)
        ):
            raise ValueError("Each capacity-admin must be a user UPN or service-principal object ID.")
    branch_check = subprocess.run(
        ["git", "check-ref-format", f"refs/heads/{args.github_branch}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if (
        args.github_branch.startswith("-")
        or args.github_branch == "HEAD"
        or branch_check.returncode
    ):
        raise ValueError("github-branch must be a valid, explicit Git branch name.")

    replacements = {
        '"<project-name>"': hcl_string(args.project_name),
        '"<azure-region>"': hcl_string(args.location),
        '["<your-user-principal-name>"]': (
            "[" + ", ".join(hcl_string(admin) for admin in args.capacity_admin) + "]"
        ),
        '"<github-organization-or-user>"': hcl_string(repository[1]),
        '"<new-repository-name>"': hcl_string(repository[2]),
        '"<published-bootstrap-branch>"': hcl_string(args.github_branch),
    }
    for placeholder, value in replacements.items():
        if example.count(placeholder) != 1:
            raise ValueError(
                f"The sanitized example must contain exactly one {placeholder} placeholder."
            )
        example = example.replace(placeholder, value)
    return example


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--location", required=True)
    parser.add_argument("--capacity-admin", required=True, action="append")
    parser.add_argument("--github-repository", required=True, metavar="OWNER/REPO")
    parser.add_argument("--github-branch", required=True)
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs without creating a file.")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[4]
    infra = root / "infra"
    output = infra / "terraform.tfvars"
    try:
        if infra.is_symlink():
            raise ValueError("Refusing to initialize a symlinked infra directory.")
        for path in infra.iterdir():
            if path.name.endswith((".tfvars", ".tfvars.json")) or re.search(
                r"\.tfstate(?:\.|$)", path.name
            ):
                raise ValueError(
                    "Local Terraform inputs or state already exist. "
                    "Review them manually; nothing was overwritten."
                )
        content = render_configuration(
            args, (infra / "terraform.tfvars.example").read_text(encoding="utf-8")
        )
        if args.dry_run:
            print("Inputs and example are valid. No files written; cloud access and quota are not checked.")
            return

        # Publish a complete, private file without replacing an existing file or symlink.
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=infra, prefix="terraform.tfvars.", suffix=".tmp"
        ) as temporary:
            temporary.write(content)
            temporary.flush()
            os.link(temporary.name, output)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Initialization failed: {error}\n")

    print("Created infra/terraform.tfvars with owner-only permissions; knowledge setup remains disabled.")
    print("No cloud or workspace changes made. Continue with docs/getting-started.md.")


if __name__ == "__main__":
    main()
