#!/usr/bin/env python3
"""Set verified DEV item IDs in the starter's local tfvars without deploying."""

import argparse
import json
import os
from pathlib import Path
import re
import tempfile
from uuid import UUID


DESCRIPTION = "Current sites, assets, their status, and which site each asset belongs to."


def physical_id(value, logical_ids):
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value):
        raise ValueError("Supply physical DEV item GUIDs in hyphenated UUID format.")
    item_id = UUID(value)
    if item_id.int == 0 or str(item_id) in logical_ids:
        raise ValueError("A zero GUID or Git logical ID cannot be used as a physical DEV item ID.")
    return str(item_id)


def configure(text, lakehouse_id, ontology_id):
    newline = "\r\n" if "\r\n" in text else "\n"
    ontology_value = newline.join((
        "{",
        "  scenario = {",
        f'    ontology_id = "{ontology_id}"',
        f"    description = {json.dumps(DESCRIPTION)}",
        "  }",
        "}",
    ))
    settings = (
        ("knowledge_lakehouse_id", rf'null|{re.escape(json.dumps(lakehouse_id))}', json.dumps(lakehouse_id)),
        ("knowledge_ontologies", rf"\{{\}}|{re.escape(ontology_value)}", ontology_value),
    )
    changes = []
    for name, allowed, replacement in settings:
        if len(re.findall(rf"(?m)^{name}[ \t]*=", text)) != 1:
            raise ValueError(f"Expected exactly one top-level {name} assignment.")
        match = re.search(
            rf"(?m)^{name}[ \t]*=[ \t]*(?P<value>{allowed})[ \t]*(?:#[^\r\n]*)?\r?$",
            text,
        )
        if not match:
            raise ValueError(
                f"{name} is already customized or points to different items. "
                "Review it without overwriting existing registrations."
            )
        changes.append((match.start("value"), match.end("value"), replacement))
    for start, end, replacement in sorted(changes, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lakehouse-id", required=True)
    parser.add_argument("--ontology-id", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    infra = root / "infra"
    target = infra / "terraform.tfvars"
    temporary_path = None

    try:
        if infra.is_symlink() or target.is_symlink():
            raise ValueError("Refusing to update symlinked configuration.")
        if any(
            path.name == "terraform.tfvars.json"
            or path.name.endswith((".auto.tfvars", ".auto.tfvars.json"))
            for path in infra.iterdir()
        ):
            raise ValueError("Additional auto-loaded tfvars exist; review precedence before editing.")
        logical_ids = {
            str(UUID(json.loads(path.read_text(encoding="utf-8"))["config"]["logicalId"]))
            for path in (root / "workspace").glob("*/.platform")
        }
        if not logical_ids:
            raise ValueError("Workspace logical identities are missing.")
        lakehouse_id = physical_id(args.lakehouse_id, logical_ids)
        ontology_id = physical_id(args.ontology_id, logical_ids)
        if lakehouse_id == ontology_id:
            raise ValueError("The lakehouse and ontology must have different physical IDs.")
        original = target.read_bytes()
        updated = configure(original.decode("utf-8"), lakehouse_id, ontology_id).encode("utf-8")
        if updated == original:
            print("The starter knowledge settings already match; no files changed.")
            return
        if args.dry_run:
            print("Would update only the two starter knowledge settings; no files changed.")
            return

        with tempfile.NamedTemporaryFile(
            mode="wb", dir=infra, prefix="terraform.tfvars.", suffix=".tmp", delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(updated)
            temporary.flush()
            os.fsync(temporary.fileno())
        if target.is_symlink() or target.read_bytes() != original:
            raise ValueError("The configuration changed during preparation; review before retrying.")
        os.replace(temporary_path, target)
        temporary_path = None
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Knowledge configuration failed: {error}\n")
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)

    print("Updated only the starter knowledge settings with owner-only permissions.")
    print("No cloud changes made. Review a new Terraform knowledge plan before applying.")


if __name__ == "__main__":
    main()
