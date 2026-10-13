"""Offline semantic checks supplement ARM's typed parameter constraints.

No authentication, resource discovery, request rendering or deployment is done.
"""

import argparse
import ipaddress
import json
import re
import uuid
from pathlib import Path
from urllib.parse import urlparse

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
            if "sku" in model and model["sku"] not in ("Standard", "DataZoneStandard"):
                reject(name, "Global model SKUs are forbidden")

    def walk(value, path=""):
        if isinstance(value, dict):
            if "approved" in value:
                deferred = path == "runtime" and value.get("attestation_mode") == "synthetic_poc_attestation_deferred"
                if deferred:
                    if value["approved"] is not False:
                        reject(path, "synthetic PoC deferral must remain unapproved, not certified")
                    for key in ("platform_evidence", "image_evidence", "transport_evidence"):
                        if value.get(key) != "":
                            reject(f"{path}.{key}", "deferred evidence must be exactly empty")
                elif value["approved"] is not True:
                    reject(path, "a gated stage needs explicit approval; omit that entry point to defer it")
                for key, evidence in value.items():
                    if not deferred and (key.endswith("_evidence") or key == "evidence_reference"):
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
                    "owner_object_id", "object_id", "client_id",
                }:
                    try:
                        if uuid.UUID(item).int == 0:
                            raise ValueError("zero")
                    except (ValueError, TypeError, AttributeError):
                        reject(child, "supply an actual nonzero principal/application/directory GUID")
                if key.endswith("_endpoint") or key in ("target", "blob", "search") and path == "endpoints":
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
    if expected_tenant_id and values.get("tenant_id", expected_tenant_id).lower() != expected_tenant_id.lower():
        reject("tenant_id", "must match the separately verified Graph deployment directory")
    runtime = values.get("runtime")
    if "runtime" in values and not isinstance(runtime, dict):
        reject("runtime", "runtime cannot be null or omit the typed acceptance record")
    elif runtime is not None:
        if runtime.get("attestation_mode") not in ("evidence_gated", "synthetic_poc_attestation_deferred"):
            reject("runtime.attestation_mode", "require evidence_gated or explicit synthetic_poc_attestation_deferred")
        if "approved" not in runtime:
            reject("runtime.approved", "explicit approval state is required even in deferred mode")
        if runtime.get("encryption_standard") != "FIPS140-3":
            reject("runtime.encryption_standard", "require FIPS140-3 encryption evidence, not FIPS140-2 or algorithms alone")
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
        try:
            endpoint = urlparse(app.get("openai_endpoint", ""))
            endpoint_valid = (endpoint.scheme == "https" and endpoint.hostname
                              and endpoint.hostname.endswith(".openai.azure.com")
                              and endpoint.path in ("", "/") and not endpoint.username
                              and not endpoint.password and endpoint.port in (None, 443)
                              and not endpoint.query and not endpoint.fragment)
        except (ValueError, TypeError, AttributeError):
            endpoint_valid = False
        if not endpoint_valid:
            reject("application.openai_endpoint", "use the verified Azure OpenAI HTTPS root endpoint")
        if not isinstance(app.get("chat_deployment"), str) or not app["chat_deployment"].strip():
            reject("application.chat_deployment", "use the actual JSON-capable chat model deployment name")
    egress_sets = {
        "approved_egress": values.get("approved_egress", []),
        "administration_egress": values.get("administration_egress", []),
        "outbound.runtime": values.get("outbound", {}).get("runtime", []),
        "outbound.build": values.get("outbound", {}).get("build", []),
        "platform_destinations.runtime": values.get("platform_destinations", {}).get("runtime", []),
        "platform_destinations.build": values.get("platform_destinations", {}).get("build", []),
    }
    for path, rules in egress_sets.items():
        egress_by_port = {}
        for i, rule in enumerate(rules):
            if path.endswith(".build") and is_build_service_tag(rule["destination_cidr"]):
                continue
            network = check_cidr(rule["destination_cidr"], f"{path}[{i}]", reject)
            if network is not None:
                egress_by_port.setdefault(rule["port"], []).append(network)
        for networks in egress_by_port.values():
            check_egress_union(networks, path, reject)
    for i, uri in enumerate(values.get("redirect_uris", [])):
        parsed = urlparse(uri)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.hostname == "localhost"
                or "*" in uri or parsed.username or parsed.password or parsed.query or parsed.fragment):
            reject(f"redirect_uris[{i}]", "use an exact approved private HTTPS SPA redirect URI")
    https_networks = []
    for i, cidr in enumerate(values.get("approved_https_cidrs", [])):
        network = check_cidr(cidr, f"approved_https_cidrs[{i}]", reject)
        if network is not None:
            https_networks.append(network)
    check_egress_union(https_networks, "approved_https_cidrs", reject)
    if "vnet_cidr" in values:
        check_cidr(values["vnet_cidr"], "vnet_cidr", reject, private_only=True)
    if "hosting_dependencies" in values:
        network = values.get("network", {})
        runtime_subnet = network.get("runtime_subnet_id", "")
        endpoint_subnet = network.get("endpoint_subnet_id", "")
        subnet_pattern = r"/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+/subnets/[^/]+"
        if not isinstance(endpoint_subnet, str) or not re.fullmatch(subnet_pattern, endpoint_subnet, re.IGNORECASE):
            reject("network.endpoint_subnet_id", "require the verified existing endpoint subnet ARM ID")
        elif isinstance(runtime_subnet, str) and (
            endpoint_subnet.lower().rsplit("/subnets/", 1)[0] != runtime_subnet.lower().rsplit("/subnets/", 1)[0]
            or endpoint_subnet.lower() == runtime_subnet.lower()
        ):
            reject("network.endpoint_subnet_id", "use a separate endpoint subnet in the selected runtime VNet")
    return errors


# Reviewed Azure service tags for the ACR agent pool (build subnet only).
# Global-only tags, plus tags that must be region-scoped so the pool cannot reach other regions' services.
BUILD_GLOBAL_TAGS = {"AzureActiveDirectory", "AzureMonitor", "AzureFrontDoor.FirstParty"}
BUILD_REGIONAL_TAG = re.compile(r"^(AzureKeyVault|Storage|EventHub|MicrosoftContainerRegistry)\.[A-Za-z0-9]+$")


def is_build_service_tag(value):
    return isinstance(value, str) and (value in BUILD_GLOBAL_TAGS or BUILD_REGIONAL_TAG.fullmatch(value) is not None)


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
