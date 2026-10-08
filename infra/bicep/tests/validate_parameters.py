"""Offline semantic checks supplement ARM's typed parameter constraints.

No authentication, resource discovery, request rendering or deployment is done.
"""

import argparse
import ipaddress
import json
import re
import uuid
from pathlib import Path

US_REGIONS = {
    "westus", "westus2", "westus3", "westcentralus", "centralus",
    "northcentralus", "southcentralus", "eastus", "eastus2",
}


def validate(values, *, allow_examples=False, expected_tenant_id=None):
    errors = []

    def reject(path, message):
        errors.append(f"{path}: {message}")

    project = values.get("project_name")
    if project and (not re.fullmatch(r"[a-z][a-z0-9-]{1,14}[a-z0-9]", project) or "--" in project):
        reject("project_name", "use 3-16 lowercase letters/digits/single hyphens")
    if "location" in values and values["location"] not in US_REGIONS:
        reject("location", "regional resources must be US-only")
    if "vnet_cidr" in values and not re.fullmatch(r"10\.(?:0|[1-9][0-9]{0,2})\.0\.0/16", values["vnet_cidr"]):
        reject("vnet_cidr", "use the canonical PoC 10.x.0.0/16")
    for name in ("models",):
        for model in values.get(name, {}).values():
            if model["sku"] not in ("Standard", "DataZoneStandard"):
                reject(name, "Global model SKUs are forbidden")

    def walk(value, path=""):
        if isinstance(value, dict):
            if "approved" in value:
                if value["approved"] is not True:
                    reject(path, "a gated stage needs explicit approval; omit that entry point to defer it")
                for key, evidence in value.items():
                    if key.endswith("_evidence") or key == "evidence_reference":
                        if not isinstance(evidence, str) or not evidence.strip():
                            reject(f"{path}.{key}", "evidence reference must be nonempty")
            for key, item in value.items():
                child = f"{path}.{key}" if path else key
                if key == "analyzer_id" and (not isinstance(item, str) or not re.fullmatch(r"[a-zA-Z0-9._]{1,64}", item)):
                    reject(child, "use 1-64 letters/digits/underscores/dots; custom analyzer IDs cannot contain hyphens")
                if key in {
                    "principal_id", "caller_principal_id", "deployment_principal_id",
                    "deployer_principal_id", "tenant_id", "spa_client_id", "api_client_id",
                    "identity_client_id",
                }:
                    try:
                        if uuid.UUID(item).int == 0:
                            raise ValueError("zero")
                    except (ValueError, TypeError, AttributeError):
                        reject(child, "supply an actual nonzero principal/application/directory GUID")
                if key.endswith("_endpoint") or key in ("target", "blob", "cosmos", "search") and path == "endpoints":
                    if isinstance(item, str) and not item.startswith("https://"):
                        reject(child, "use a verified private HTTPS endpoint")
                walk(item, child)
        elif isinstance(value, list):
            for i, item in enumerate(value):
                walk(item, f"{path}[{i}]")
        elif isinstance(value, str):
            if not allow_examples and any(marker in value.upper() for marker in ("EXAMPLE", "REPLACE-WITH", "SYNTHETIC-ONLY-EXAMPLE")):
                reject(path, "sanitized examples are not deployment configuration or approval")

    walk(values)
    runtime = values.get("runtime")
    if "runtime" in values and not isinstance(runtime, dict):
        reject("runtime", "runtime cannot be null or omit the typed acceptance record")
    elif runtime is not None:
        identity = runtime.get("identity")
        if not identity:
            reject("runtime.identity", "runtime cannot use a null browser identity")
        elif expected_tenant_id and identity["tenant_id"].lower() != expected_tenant_id.lower():
            reject("runtime.identity.tenant_id", "must match the separately verified deployment directory")
        if runtime.get("image_algorithm") != "sha256" or not re.fullmatch(r"[0-9a-f]{64}", runtime.get("image_hash", "")):
            reject("runtime.image_hash", "use exactly 64 lowercase hex characters from the reviewed registry digest")
        if runtime.get("knowledge", {}).get("approved") is not True:
            reject("runtime.knowledge", "private knowledge readiness must be independently verified")
    if "image_version" in values and values["image_version"].lower() == "latest":
        reject("image_version", "pin the approved administration image version")
    if "application" in values:
        app = values["application"]
        try:
            if not 0 <= float(app["confidence_threshold"]) <= 1:
                raise ValueError("range")
        except (KeyError, ValueError, TypeError):
            reject("application.confidence_threshold", "use a threshold in [0,1]; all fields still need human confirmation")
        if app.get("processing_location") not in ("geography", "dataZone"):
            reject("application.processing_location", "Global processing is forbidden")
        if not app.get("field_names") or len(app["field_names"]) != len(set(app["field_names"])):
            reject("application.field_names", "provide distinct fields matching the reviewed analyzer")
    egress_by_port = {}
    for i, rule in enumerate(values.get("approved_egress", [])):
        network = check_cidr(rule["destination_cidr"], f"approved_egress[{i}]", reject)
        if network is not None:
            egress_by_port.setdefault(rule["port"], []).append(network)
    for networks in egress_by_port.values():
        check_egress_union(networks, "approved_egress", reject)
    https_networks = []
    for i, cidr in enumerate(values.get("approved_https_cidrs", [])):
        network = check_cidr(cidr, f"approved_https_cidrs[{i}]", reject)
        if network is not None:
            https_networks.append(network)
    check_egress_union(https_networks, "approved_https_cidrs", reject)
    if "vnet_cidr" in values:
        check_cidr(values["vnet_cidr"], "vnet_cidr", reject, private_only=True)
    discovered = values.get("discovered", {})
    if discovered and discovered["files_container"] == discovered["intermediate_container"]:
        reject("discovered", "native file/intermediate containers must be distinct and discovered")
    extras = values.get("extra_principal_ids", [])
    if len(extras) != len(set(p.lower() for p in extras)):
        reject("extra_principal_ids", "duplicate principals would create colliding role assignments")
    for i, principal in enumerate(extras):
        try:
            if uuid.UUID(principal).int == 0:
                raise ValueError("zero")
        except (ValueError, TypeError, AttributeError):
            reject(f"extra_principal_ids[{i}]", "supply a verified nonzero runtime principal GUID")
    hosting = values.get("hosting", {})
    if hosting.get("kind") == "aks":
        try:
            pod = ipaddress.ip_network(hosting["pod_cidr"], strict=True)
            service = ipaddress.ip_network(hosting["service_cidr"], strict=True)
            if pod.overlaps(service) or ipaddress.ip_address(hosting["dns_service_ip"]) not in service:
                raise ValueError("overlap")
        except (ValueError, KeyError):
            reject("hosting", "use nonoverlapping pod/service ranges with DNS inside the service range")
    return errors


def check_cidr(cidr, path, reject, *, private_only=False):
    try:
        network = ipaddress.ip_network(cidr, strict=True)
        if network.version != 4 or network.prefixlen == 0:
            raise ValueError("broad")
        if private_only and not network.is_private:
            raise ValueError("public")
        return network
    except (ValueError, TypeError):
        reject(path, "use an explicit reviewed IPv4 CIDR, never Internet/AzureCloud/* or all-address egress")
        return None


def check_egress_union(networks, path, reject):
    if any(network.prefixlen == 0 for network in ipaddress.collapse_addresses(networks)):
        reject(path, "combined destination CIDRs must not cover all IPv4 addresses on the same port")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parameters", type=Path, help="Local compiled ARM parameter JSON; values are never printed")
    parser.add_argument("--allow-examples", action="store_true", help="Static fixtures only, not a deployment gate")
    parser.add_argument("--expected-tenant-id", help="Separately verified directory GUID; no Azure discovery")
    args = parser.parse_args()
    document = json.loads(args.parameters.read_text())
    errors = validate(
        {key: spec["value"] for key, spec in document["parameters"].items()},
        allow_examples=args.allow_examples,
        expected_tenant_id=args.expected_tenant_id,
    )
    if errors:
        parser.exit(1, "\n".join(errors) + "\n")
    print("Offline parameter checks passed; no live readiness or approval was established.")


if __name__ == "__main__":
    main()
