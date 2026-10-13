"""Compile modular Bicep sources/examples and test emitted ARM contracts offline."""

import copy
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from validate_parameters import validate

ROOT = Path(__file__).resolve().parents[1]


def resources(template):
    collection = template.get("resources", {})
    entries = collection.values() if isinstance(collection, dict) else collection
    for resource in entries:
        yield resource
        if resource["type"] == "Microsoft.Resources/deployments":
            yield from resources(resource["properties"]["template"])


def definition(template, schema):
    while "$ref" in schema:
        schema = template["definitions"][schema["$ref"].split("/")[-1]]
    return schema


class StaticContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = os.environ.get("BICEP_CLI") or shutil.which("bicep")
        if not compiler:
            candidate = Path.home() / ".azure/bin/bicep"
            compiler = str(candidate) if candidate.is_file() else None
        if not compiler:
            raise RuntimeError("Bicep CLI missing. Run the documented local compiler check; do not deploy.")
        cls.compiler = compiler
        cls.temp = tempfile.TemporaryDirectory(prefix=".private-review-bicep-", dir=Path.cwd())
        cls.addClassCleanup(cls.temp.cleanup)
        cls.templates = {}
        cls.examples = {}
        for path in sorted(ROOT.rglob("*.bicep")):
            destination = Path(cls.temp.name) / (str(path.relative_to(ROOT)).replace("/", "-") + ".json")
            cls.compile("build", path, destination)
            cls.templates[str(path.relative_to(ROOT))] = json.loads(destination.read_text())
        for path in sorted((ROOT / "examples").glob("*.example.bicepparam")):
            destination = Path(cls.temp.name) / (path.name + ".json")
            cls.compile("build-params", path, destination)
            cls.examples[path.name] = {key: spec["value"] for key, spec in json.loads(destination.read_text())["parameters"].items()}

    @classmethod
    def compile(cls, operation, source, destination):
        result = subprocess.run([cls.compiler, operation, str(source), "--outfile", str(destination)], capture_output=True, text=True, check=False)
        if result.returncode or result.stderr.strip():
            raise AssertionError(f"{source.name} failed clean compilation:\n{result.stderr}")

    def test_every_entry_has_a_compiled_example(self):
        required = {
            "main.bicep", "foundation/bootstrap-payloads.bicep",
            "identity/api-payload.bicep", "identity/spa-payload.bicep", "identity/finalize-payloads.bicep",
            "connectivity/main.bicep",
            "foundation/main.bicep",
            "scenario/platform.bicep", "scenario/private-links.bicep", "scenario/hosting.bicep",
            "scenario/runtime.bicep", "knowledge/payloads.bicep",
            "acr-build/main.bicep",
        }
        covered = set()
        for path in (ROOT / "examples").glob("*.example.bicepparam"):
            match = re.search(r"using '([^']+)'", path.read_text())
            covered.add(str((path.parent / match[1]).resolve().relative_to(ROOT)))
            self.assertEqual(validate(self.examples[path.name], allow_examples=True), [], path.name)
        self.assertEqual(required, covered)

    def test_new_solution_composition_has_no_state_or_existing_resource_prerequisite(self):
        template = self.templates["main.bicep"]
        modules = template["resources"]
        self.assertEqual(template["metadata"]["_generator"]["version"].split(".")[:2], ["0", "44"])
        self.assertIn("connectivity", modules["private_network"]["dependsOn"])
        self.assertIn("private_network", modules["foundation"]["dependsOn"])
        self.assertIn("connectivity", modules["foundation"]["dependsOn"])
        emitted = list(resources(template))
        types = {item["type"] for item in emitted if not item.get("existing")}
        for kind in ("Microsoft.Network/virtualNetworks", "Microsoft.Network/natGateways",
                     "Microsoft.Network/virtualNetworks/subnets", "Microsoft.Network/privateDnsZones",
                     "Microsoft.CognitiveServices/accounts", "Microsoft.Search/searchServices",
                     "Microsoft.Storage/storageAccounts"):
            self.assertIn(kind, types)
        self.assertNotIn("hosting", modules["foundation"]["properties"]["parameters"])
        self.assertIn("Microsoft.App/environments", json.dumps(modules["foundation"]))
        for key in ("network", "services", "resource_groups"):
            self.assertIn(key, template["outputs"])
        self.assertFalse(any("state" in key.lower() for key in template["parameters"]))
        serialized = json.dumps(template).lower()
        self.assertNotIn("terraform", serialized)
        self.assertNotIn("tfstate", serialized)
        for path in ROOT.rglob("*.bicep"):
            for reference in re.findall(r"(?:from|module\s+\w+|loadTextContent\(|loadJsonContent\()\s*'([^']+)'", path.read_text()):
                self.assertTrue((path.parent / reference).resolve().is_relative_to(ROOT), f"{path}: {reference}")

    def test_runtime_build_nat_and_exact_egress_are_wired_without_agent_subnet(self):
        network = self.templates["foundation/network.bicep"]["resources"]
        subnet = network["reservations"]["properties"]
        serialized = json.dumps(subnet)
        self.assertIn("nat_gateway_id", serialized)
        self.assertNotIn("'agent'", serialized)
        self.assertEqual(self.templates["foundation/network.bicep"]["variables"]["subnets"],
                         [{"name": "runtime", "number": 1, "delegated": True},
                          {"name": "build", "number": 4, "delegated": False}])
        rules = json.dumps(network["nsgs"]["properties"]["securityRules"])
        self.assertIn("deny-other-egress", rules)
        self.assertIn("outbound", rules)
        self.assertIn("destination_cidr", rules)
        foundation = self.templates["foundation/main.bicep"]
        self.assertIn("outbound", foundation["resources"]["reservations"]["properties"]["parameters"])
        self.assertNotIn("defaultValue", foundation["parameters"]["outbound"])

    def test_rai_policy_is_native_blocking_declared_only_and_associated_with_chat(self):
        template = self.templates["foundation/main.bicep"]
        policy = template["resources"]["chat_prompt_shields"]
        self.assertEqual(policy["apiVersion"], "2025-06-01")
        self.assertEqual(policy["properties"]["mode"], "Blocking")
        self.assertEqual(policy["properties"]["basePolicyName"], "Microsoft.Default")
        self.assertEqual(template["variables"]["harm_filter_pairs"], [
            {"name": name, "source": source}
            for name in ("Hate", "Sexual", "Violence", "Selfharm")
            for source in ("Prompt", "Completion")
        ])
        declared = (ROOT / "foundation/main.bicep").read_text()
        for name in ("Jailbreak", "Indirect Attack", "Protected Material Text", "Protected Material Code"):
            self.assertIn(name, declared)
        self.assertNotIn("Task Adherence", declared)
        self.assertIn("blocking: true", declared)
        association = json.dumps(template["resources"]["deployments"])
        self.assertIn("raiPolicyName", association)
        self.assertIn("'chat'", association)
        self.assertIn("chat_prompt_shields", association)
        self.assertIn("NoAutoUpgrade", association)

    def test_cu_bootstrap_only_preserves_defaults_without_prompt_agent_objects(self):
        template = self.templates["foundation/bootstrap-payloads.bicep"]
        self.assertEqual(template.get("resources", {}), {})
        outputs = template["outputs"]
        self.assertEqual(set(outputs), {"content_defaults_request", "verification_reference"})
        self.assertNotIn("DELETE", json.dumps(outputs))
        self.assertNotIn("/agents", json.dumps(template))
        self.assertEqual(outputs["content_defaults_request"]["value"]["method"], "PATCH")
        mappings = outputs["content_defaults_request"]["value"]["body"]["modelDeployments"]
        for alias in ("prebuilt-analyzer-completion", "prebuilt-analyzer-completion-mini", "prebuilt-analyzer-embedding"):
            self.assertIn(alias, mappings)
        self.assertIn("existing_model_deployments", mappings)

    def test_entra_native_payloads_are_single_tenant_delegated_user_roles_not_consent(self):
        api = self.templates["identity/api-payload.bicep"]
        body = api["outputs"]["api_request"]["value"]["body"]
        self.assertEqual(body["signInAudience"], "AzureADMyOrg")
        self.assertEqual(body["api"]["requestedAccessTokenVersion"], 2)
        self.assertEqual(body["api"]["oauth2PermissionScopes"][0]["value"], "access_as_user")
        role = next(item["input"] for item in api["variables"]["copy"] if item["name"] == "roles")
        self.assertEqual(role["allowedMemberTypes"], ["User"])
        spa = self.templates["identity/spa-payload.bicep"]["outputs"]["spa_request"]["value"]["body"]
        self.assertFalse(spa["web"]["implicitGrantSettings"]["enableAccessTokenIssuance"])
        self.assertFalse(spa["web"]["implicitGrantSettings"]["enableIdTokenIssuance"])
        self.assertIn("spa", spa)
        self.assertEqual(spa["requiredResourceAccess"][0]["resourceAccess"][0]["type"], "Scope")
        requests = self.templates["identity/finalize-payloads.bicep"]["outputs"]["graph_requests"]["value"]
        self.assertTrue(requests[1]["body"]["appRoleAssignmentRequired"])
        for name in ("identity/api-payload.bicep", "identity/spa-payload.bicep", "identity/finalize-payloads.bicep"):
            serialized = json.dumps(self.templates[name]).lower()
            self.assertNotIn("oauth2permissiongrants", serialized)
            self.assertNotIn("approleassignments", serialized)
            self.assertNotIn("directoryroles", serialized)

    def test_new_nested_egress_and_identity_semantic_guards(self):
        for name in ("main.example.bicepparam", "foundation.example.bicepparam"):
            values = copy.deepcopy(self.examples[name])
            targets = values.get("platform_destinations", values.get("outbound"))
            targets["runtime"] = [{"destination_cidr": cidr, "port": 443} for cidr in ("0.0.0.0/1", "128.0.0.0/1")]
            self.assertTrue(any("combined" in error for error in validate(values, allow_examples=True)))
        values = copy.deepcopy(self.examples["identity-spa.example.bicepparam"])
        for uri in ("http://localhost/", "https://*.example/", "https://user:password@internal.example/"):
            values["redirect_uris"] = [uri]
            self.assertTrue(validate(values, allow_examples=True))

    def test_platform_stage_has_no_hosting_runtime_or_knowledge(self):
        types = {r["type"] for r in resources(self.templates["scenario/platform.bicep"]) if not r.get("existing")}
        self.assertIn("Microsoft.ContainerRegistry/registries", types)
        self.assertIn("Microsoft.Storage/storageAccounts/blobServices/containers", types)
        self.assertFalse(any(t.startswith(("Microsoft.App/", "Microsoft.ContainerService/")) for t in types))
        self.assertNotIn("portal_url", self.templates["scenario/platform.bicep"].get("outputs", {}))
        self.assertNotIn("identity", self.templates["scenario/platform.bicep"]["parameters"])

    def test_direct_inference_has_no_managed_agent_resources_or_bootstrap_store_grants(self):
        for template in self.templates.values():
            for resource in resources(template):
                self.assertFalse(resource["type"].startswith("Microsoft.DocumentDB/"))
                self.assertNotIn("/projects", resource["type"])
                self.assertNotIn("/capabilityHosts", resource["type"])
                self.assertNotIn("/connections", resource["type"])
        foundation = self.templates["foundation/main.bicep"]
        self.assertNotIn("networkInjections", foundation["resources"]["account"]["properties"])
        self.assertNotIn("allowProjectManagement", foundation["resources"]["account"]["properties"])
        self.assertNotIn("caller_blob", foundation["resources"])
        self.assertNotIn("caller_cosmos", foundation["resources"])
        self.assertNotIn("agent_storage_name", foundation["outputs"])
        self.assertIn("openai.azure.com", foundation["outputs"]["service_endpoints"]["value"]["openai"])
        platform = self.templates["scenario/platform.bicep"]
        self.assertNotIn("project_role", platform["resources"])
        self.assertIn("5e0bd9bd-7b93-4f28-af87-19fc36ad61bd", json.dumps(platform["variables"]["grants"]))

    def test_application_direct_inference_configuration_has_no_agent_binding(self):
        application = self.templates["scenario/runtime.bicep"]
        schema = definition(application, application["parameters"]["application"])
        self.assertIn("openai_endpoint", schema["properties"])
        self.assertIn("chat_deployment", schema["properties"])
        self.assertNotIn("project_endpoint", schema["properties"])
        self.assertNotIn("agent_name", schema["properties"])
        declared = (ROOT / "scenario/application.bicep").read_text()
        self.assertIn("Portal__OpenAIEndpoint", declared)
        self.assertIn("Portal__ChatDeployment", declared)
        self.assertNotIn("Portal__AgentName", declared)
        self.assertNotIn("Portal__ProjectEndpoint", declared)

    def test_direct_inference_parameters_reject_nonroot_untrusted_or_missing_endpoint(self):
        base = self.examples["runtime.example.bicepparam"]
        for endpoint in (None, "", "http://account.openai.azure.com",
                         "https://account.openai.azure.com/openai/v1",
                         "https://account.openai.azure.com.foreign.example",
                         "https://user@account.openai.azure.com", "https://account.openai.azure.com?key=x",
                         "https://account.openai.azure.com:bad"):
            values = copy.deepcopy(base)
            values["application"]["openai_endpoint"] = endpoint
            self.assertTrue(any("openai_endpoint" in error for error in validate(values, allow_examples=True)))
        for deployment in (None, "", " "):
            values = copy.deepcopy(base)
            values["application"]["chat_deployment"] = deployment
            self.assertTrue(any("chat_deployment" in error for error in validate(values, allow_examples=True)))

    def test_hosting_is_only_private_container_apps_and_runtime_is_separate(self):
        template = self.templates["scenario/hosting.bicep"]
        self.assertNotIn("hosting", template["parameters"])
        self.assertNotIn("platform", template["parameters"])
        emitted = template["resources"]
        self.assertNotIn("condition", emitted["environment"])
        self.assertTrue(emitted["environment"]["properties"]["peerTrafficConfiguration"]["encryption"]["enabled"])
        self.assertNotIn("portal_url", template.get("outputs", {}))
        self.assertFalse(any(r["type"] == "Microsoft.App/containerApps" for r in resources(template)))
        self.assertFalse(any(r["type"].startswith("Microsoft.ContainerService/") for t in self.templates.values() for r in resources(t)))
        self.assertEqual(set(template["outputs"]), {"container_apps_environment_name", "container_apps_default_domain"})

    def test_public_ip_is_used_only_by_controlled_outbound_nat(self):
        connectivity = self.templates["connectivity/main.bicep"]["resources"]
        self.assertEqual(connectivity["ip"]["type"], "Microsoft.Network/publicIPAddresses")
        self.assertIn("publicIPAddresses", connectivity["nat"]["properties"]["publicIpAddresses"][0]["id"])
        self.assertNotIn("publicIPAddress", json.dumps(connectivity["nic"]))
        self.assertNotIn("publicIPAddress", json.dumps(connectivity["vm"]))
        for path, template in self.templates.items():
            if path not in ("main.bicep", "connectivity/main.bicep"):
                self.assertFalse(any(r["type"] == "Microsoft.Network/publicIPAddresses" for r in resources(template)), path)
        self.assertIn("deny-other-egress", json.dumps(connectivity["nsg"]))
        self.assertTrue(connectivity["router"]["properties"]["defaultOutboundAccess"] is False)

    def test_runtime_example_is_authorized_synthetic_deferral_not_acceptance(self):
        runtime = self.examples["runtime.example.bicepparam"]["runtime"]
        self.assertEqual(runtime["attestation_mode"], "synthetic_poc_attestation_deferred")
        self.assertIs(runtime["approved"], False)
        for evidence in ("platform_evidence", "image_evidence", "transport_evidence"):
            self.assertEqual(runtime[evidence], "")
        self.assertIs(runtime["knowledge"]["approved"], True)

    def test_runtime_gates_are_required_typed_and_no_mutable_image(self):
        for path in ("scenario/runtime.bicep",):
            template = self.templates[path]
            self.assertNotIn("defaultValue", template["parameters"]["runtime"])
            runtime = definition(template, template["parameters"]["runtime"])
            members = runtime["discriminator"]["mapping"]
            self.assertEqual(set(members), {"evidence_gated", "synthetic_poc_attestation_deferred"})
            accepted = definition(template, members["evidence_gated"])
            deferred = definition(template, members["synthetic_poc_attestation_deferred"])
            self.assertEqual(accepted["properties"]["approved"]["allowedValues"], [True])
            self.assertEqual(deferred["properties"]["approved"]["allowedValues"], [False])
            for evidence in ("platform_evidence", "image_evidence", "transport_evidence"):
                self.assertEqual(accepted["properties"][evidence]["minLength"], 1)
                self.assertEqual(deferred["properties"][evidence]["allowedValues"], [""])
            for branch in (accepted, deferred):
                self.assertEqual(branch["properties"]["encryption_standard"]["allowedValues"], ["FIPS140-3"])
                self.assertEqual(branch["properties"]["image_algorithm"]["allowedValues"], ["sha256"])
                self.assertEqual(branch["properties"]["image_hash"]["minLength"], 64)
                self.assertNotIn("nullable", branch["properties"]["identity"])
                knowledge = definition(template, branch["properties"]["knowledge"])
                self.assertEqual(knowledge["properties"]["approved"]["allowedValues"], [True])
            self.assertEqual(template["outputs"]["runtime_attestation_status"]["value"]["production_readiness"], "not_established")
        app = self.templates["scenario/runtime.bicep"]["resources"]["app"]
        image = app["properties"]["template"]["containers"][0]["image"]
        self.assertIn("/review-portal@", image)
        self.assertIn("image_algorithm", image)
        self.assertFalse(app["properties"]["configuration"]["ingress"]["allowInsecure"])
        self.assertEqual(app["properties"]["template"]["scale"]["minReplicas"], 1)
        self.assertEqual(app["properties"]["template"]["scale"]["maxReplicas"], 1)

    def test_container_apps_ingress_uses_private_endpoint_not_ilb(self):
        hosting = self.templates["scenario/hosting.bicep"]["resources"]
        for name in ("endpoint", "dns", "private_link_zone", "private_link_vnet"):
            self.assertNotIn("condition", hosting[name])
        env = hosting["environment"]["properties"]
        self.assertTrue(env["vnetConfiguration"]["internal"])
        self.assertEqual(env["publicNetworkAccess"], "Disabled")
        self.assertEqual(env["workloadProfiles"], [{"name": "Consumption", "workloadProfileType": "Consumption"}])
        endpoint_params = hosting["endpoint"]["properties"]["parameters"]
        self.assertEqual(endpoint_params["group_id"]["value"], "managedEnvironments")
        self.assertEqual(endpoint_params["subnet_id"]["value"], "[parameters('network').endpoint_subnet_id]")
        self.assertIn("Microsoft.App/managedEnvironments", endpoint_params["target_id"]["value"])
        self.assertIn("privatelink.{0}.azurecontainerapps.io", endpoint_params["dns_zone_ids"]["value"][0])
        self.assertEqual(hosting["private_link_zone"]["name"], "[format('privatelink.{0}.azurecontainerapps.io', parameters('location'))]")
        self.assertIn("parameters('network').vnet", json.dumps(hosting["private_link_vnet"]))
        dns = hosting["dns"]
        self.assertIn("endpoint", dns["dependsOn"])
        self.assertIn("network_interface_id", dns["properties"]["parameters"])
        self.assertNotIn("staticIp", json.dumps(dns))
        endpoint = self.templates["modules/private-endpoint.bicep"]
        self.assertIn("networkInterfaces[0].id", endpoint["outputs"]["network_interface_id"]["value"])
        self.assertIn("privateLinkServiceConnections", endpoint["resources"]["endpoint"]["properties"])
        self.assertNotIn("manualPrivateLinkServiceConnections", endpoint["resources"]["endpoint"]["properties"])
        runtime_dns = self.templates["scenario/runtime-dns.bicep"]
        emitted_dns = list(resources(runtime_dns))
        self.assertFalse(any(r["type"] == "Microsoft.Network/networkInterfaces" for r in emitted_dns))
        record = next(r for r in emitted_dns if r["type"] == "Microsoft.Network/privateDnsZones/A")
        self.assertEqual(record["name"], "[format('{0}/{1}', parameters('domain'), '*')]")
        self.assertIn("ipConfigurations[0].properties.privateIPAddress", record["properties"]["aRecords"][0]["ipv4Address"])
        self.assertIn("Microsoft.Network/networkInterfaces", record["properties"]["aRecords"][0]["ipv4Address"])
        self.assertIn("'2024-05-01'", record["properties"]["aRecords"][0]["ipv4Address"])
        self.assertNotIn("customDnsConfigs", json.dumps(runtime_dns))

    def test_hosting_endpoint_subnet_contract(self):
        for example in ("hosting.example.bicepparam",):
            values = copy.deepcopy(self.examples[example])
            self.assertEqual(validate(values, allow_examples=True), [])
            del values["network"]["endpoint_subnet_id"]
            self.assertTrue(any("network.endpoint_subnet_id" in error for error in validate(values, allow_examples=True)))
            values["network"]["endpoint_subnet_id"] = values["network"]["runtime_subnet_id"]
            self.assertTrue(any("separate endpoint subnet" in error for error in validate(values, allow_examples=True)))
            values["network"]["endpoint_subnet_id"] = self.examples[example]["network"]["endpoint_subnet_id"].replace("vnet-review-demo/", "vnet-foreign/")
            self.assertTrue(any("selected runtime VNet" in error for error in validate(values, allow_examples=True)))

    def test_private_keyless_storage_foundry_search_registry(self):
        store = self.templates["modules/storage.bicep"]["resources"]["account"]["properties"]
        for key in ("allowBlobPublicAccess", "allowSharedKeyAccess", "isLocalUserEnabled", "allowCrossTenantReplication"):
            self.assertFalse(store[key])
        self.assertEqual(store["networkAcls"]["bypass"], "None")
        self.assertEqual(store["publicNetworkAccess"], "Disabled")
        foundation = self.templates["foundation/main.bicep"]["resources"]
        account = foundation["account"]
        self.assertTrue(account["properties"]["disableLocalAuth"])
        self.assertEqual(account["apiVersion"], "2025-06-01")
        self.assertNotIn("networkInjections", account["properties"])
        self.assertNotIn("capabilitySettings", json.dumps(foundation))
        self.assertTrue(foundation["search"]["properties"]["disableLocalAuth"])
        self.assertEqual(foundation["search"]["properties"]["networkRuleSet"]["bypass"], "None")
        registry = self.templates["scenario/platform.bicep"]["resources"]["registry"]["properties"]
        self.assertFalse(registry["adminUserEnabled"])
        self.assertEqual(registry["publicNetworkAccess"], "Disabled")
        self.assertEqual(registry["networkRuleBypassOptions"], "None")

    def test_private_links_existing_pairs_are_not_created_twice(self):
        template = self.templates["scenario/private-links.bicep"]
        self.assertEqual(template["resources"]["requests"]["condition"], "[equals(variables('names')[copyIndex()], null())]")
        missing = self.examples["private-links.example.bicepparam"].get("existing_content_links", {"foundry_account": None, "cognitiveservices_account": None})
        existing = self.examples["private-links-existing.example.bicepparam"]["existing_content_links"]
        self.assertEqual(sum(name is None for name in missing.values()), 2)
        self.assertEqual(sum(name is None for name in existing.values()), 0)
        self.assertEqual(sum(name is None for name in {"foundry_account": "verified", "cognitiveservices_account": None}.values()), 1)

    def test_shared_link_requests_are_serialized_on_search(self):
        requests = self.templates["scenario/private-links.bicep"]["resources"]["requests"]
        self.assertEqual(requests["copy"]["mode"], "serial")
        self.assertEqual(requests["copy"]["batchSize"], 1)

    def test_roles_are_scoped_deterministic_and_unused_resource_grants_removed(self):
        roles = self.templates["modules/service-roles.bicep"]
        allowed = roles["parameters"]["role_id"]["allowedValues"]
        self.assertNotIn("8e3af657-a8ff-443c-a75c-2fe8c4bcb635", allowed)
        self.assertNotIn("b24988ac-6180-42a0-ab88-20f7382dd24c", allowed)
        for resource in resources(roles):
            if resource["type"] == "Microsoft.Authorization/roleAssignments":
                self.assertIn("guid(", resource["name"])
                self.assertIn("resourceId(", resource["scope"])
            else:
                self.assertIn("condition", resource)
        containers = self.templates["modules/storage-bindings.bicep"]["resources"]
        self.assertIn("/containers", containers["roles"]["scope"])
        self.assertIn("container_names", self.templates["modules/storage-bindings.bicep"]["parameters"])
        self.assertNotIn("cluster", roles["parameters"]["kind"]["allowedValues"])
        self.assertNotIn("cosmos", roles["parameters"]["kind"]["allowedValues"])
        for role in ("230815da-be43-4aae-9cb4-875f7bd000aa", "17d1049b-9a84-46fb-8f53-869881c3d3ab",
                     "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b", "4d97b98b-1d4f-4787-a291-c67834d212e7",
                     "ba92f5b4-2d11-453d-a403-e96b0029c9fe"):
            self.assertNotIn(role, allowed)

    def test_no_fake_arm_data_plane_resources_or_deployment_scripts(self):
        for template in self.templates.values():
            for resource in resources(template):
                self.assertNotIn("deploymentScripts", resource["type"])
                self.assertFalse(resource["type"].startswith(("Microsoft.Search/searchServices/indexes", "Microsoft.Search/searchServices/knowledge", "Microsoft.KubernetesConfiguration/")))
        self.assertEqual(self.templates["knowledge/payloads.bicep"].get("resources", {}), {})

    def test_two_indexers_human_review_and_case_owner_evidence_contract(self):
        template = self.templates["knowledge/payloads.bicep"]
        requests = template["outputs"]["search_requests"]["value"]
        self.assertEqual(len(requests), 8)
        fields = template["variables"]["metadata_fields"]
        self.assertIn("case_id", fields)
        self.assertIn("owner_id", fields)
        for name in ("pdf_indexer", "fields_indexer"):
            indexer = template["variables"][name]
            self.assertEqual(indexer["parameters"]["configuration"]["executionEnvironment"], "private")
            self.assertEqual(indexer["parameters"]["maxFailedItems"], 0)
        skill = template["variables"]["skillset"]["skills"][0]
        self.assertNotIn("analyzerId", skill)
        self.assertEqual(skill["@odata.type"], "#Microsoft.Skills.Util.ContentUnderstandingSkill")
        self.assertEqual(template["variables"]["fields_indexer"]["parameters"]["configuration"]["parsingMode"], "json")
        analyzer = template["outputs"]["analyzer_request"]["value"]
        self.assertTrue(analyzer["body"]["config"]["estimateFieldSourceAndConfidence"])
        self.assertIn("case_id", template["variables"]["source_fields"])
        self.assertIn("owner_id", template["variables"]["source_fields"])
        self.assertIn("source_fields", template["variables"]["source"]["searchIndexParameters"]["sourceDataFields"])
        self.assertEqual(template["variables"]["base"]["outputMode"], "extractiveData")

    def test_build_pool_changes_no_registry_settings(self):
        template = self.templates["acr-build/main.bicep"]
        created = [r for r in resources(template) if not r.get("existing")]
        self.assertEqual([r["type"] for r in created], ["Microsoft.ContainerRegistry/registries/agentPools"])
        self.assertIn("virtualNetworkSubnetResourceId", created[0]["properties"])

    def test_no_secrets_or_service_wide_browser_access_outputs(self):
        for path, template in self.templates.items():
            for name in template.get("parameters", {}):
                self.assertNotRegex(name.lower(), r"password|access_token|auth_key|client_secret")
            serialized = json.dumps(template.get("outputs", {})).lower()
            self.assertNotRegex(serialized, r"listkeys|listcredentials|access_token|adminpassword|client_secret")

    def test_semantic_rejections(self):
        base = self.examples["runtime.example.bicepparam"]
        for field, value in (("encryption_standard", "FIPS140-2"), ("encryption_standard", None), ("image_hash", "g" * 64), ("identity", None), ("knowledge", {"approved": False}), ("image_evidence", "claimed")):
            candidate = copy.deepcopy(base)
            candidate["runtime"][field] = value
            self.assertTrue(validate(candidate, allow_examples=True), field)
        self.assertTrue(validate(base, allow_examples=True, expected_tenant_id="77777777-7777-4777-8777-777777777777"))
        self.assertTrue(validate(base), "fixtures must not pass the default deployment-configuration check")
        self.assertTrue(validate({"runtime": None}, allow_examples=True))
        for cidr in ("0.0.0.0/0", "AzureCloud", "Internet", "*", "::/0"):
            self.assertTrue(validate({"approved_https_cidrs": [cidr]}, allow_examples=True), cidr)
        self.assertTrue(validate({"location": "westeurope"}, allow_examples=True))
        self.assertTrue(validate({"models": {"chat": {"sku": "GlobalStandard"}}}, allow_examples=True))

    def test_compiler_rejects_unsafe_stage_parameter_shapes(self):
        source = (ROOT / "examples/runtime.example.bicepparam").read_text()
        source = source.replace("using '../scenario/runtime.bicep'", f"using '{os.path.relpath(ROOT / 'scenario/runtime.bicep', self.temp.name)}'")
        source = source.replace("attestation_mode: 'synthetic_poc_attestation_deferred'", "attestation_mode: 'evidence_gated'")
        source = source.replace("  approved: false", "  approved: true", 1)
        source = re.sub(r"(  (?:platform|image|transport)_evidence:) ''", r"\1 'EXAMPLE-ACCEPTANCE'", source)
        accepted = Path(self.temp.name) / "accepted.bicepparam"
        accepted.write_text(source)
        self.compile("build-params", accepted, accepted.with_suffix(".json"))
        cases = {
            "unknown-mode": source.replace("attestation_mode: 'evidence_gated'", "attestation_mode: 'production_ready'"),
            "missing-mode": source.replace("  attestation_mode: 'evidence_gated'\n", ""),
            "contradictory-deferral": source.replace("attestation_mode: 'evidence_gated'", "attestation_mode: 'synthetic_poc_attestation_deferred'"),
            "wrong-encryption-standard": source.replace("encryption_standard: 'FIPS140-3'", "encryption_standard: 'FIPS140-2'"),
            "unapproved": source.replace("approved: true", "approved: false", 1),
            "missing-evidence": source.replace("  transport_evidence: 'EXAMPLE-ACCEPTANCE'\n", ""),
            "null-browser": re.sub(r"  identity: \{.*?\n  \}", "  identity: null", source, flags=re.S),
            "mutable-image": source.replace("image_algorithm: 'sha256'", "image_algorithm: 'tag'"),
            "non-us": source.replace("location = 'eastus2'", "location = 'westeurope'"),
            "obsolete-agent-binding": source.replace("openai_endpoint:", "project_endpoint:").replace("chat_deployment:", "agent_name:"),
        }
        for name, text in cases.items():
            path = Path(self.temp.name) / f"{name}.bicepparam"
            path.write_text(text)
            result = subprocess.run([self.compiler, "build-params", str(path), "--outfile", str(path.with_suffix(".json"))], capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0, f"{name} unexpectedly compiled")

    def test_deferred_attestations_preserve_all_other_runtime_gates(self):
        for example in ("runtime.example.bicepparam",):
            candidate = copy.deepcopy(self.examples[example])
            runtime = candidate["runtime"]
            runtime.update(attestation_mode="synthetic_poc_attestation_deferred", approved=False,
                           platform_evidence="", image_evidence="", transport_evidence="")
            self.assertEqual(validate(candidate, allow_examples=True), [])
            for field, value in (("approved", True), ("platform_evidence", "claimed-evidence"), ("image_evidence", " "),
                                 ("transport_evidence", None), ("identity", None), ("image_hash", "g" * 64),
                                 ("knowledge", {"approved": False}), ("encryption_standard", "FIPS140-2")):
                invalid = copy.deepcopy(candidate)
                invalid["runtime"][field] = value
                self.assertTrue(validate(invalid, allow_examples=True), field)
            source = (ROOT / "examples" / example).read_text()
            entry = "runtime.bicep"
            source = source.replace(f"using '../scenario/{entry}'", f"using '{os.path.relpath(ROOT / 'scenario' / entry, self.temp.name)}'")
            source = source.replace("attestation_mode: 'evidence_gated'", "attestation_mode: 'synthetic_poc_attestation_deferred'")
            source = source.replace("  approved: true", "  approved: false", 1)
            source = re.sub(r"(  (?:platform|image|transport)_evidence:) '[^']*'", r"\1 ''", source)
            path = Path(self.temp.name) / example
            path.write_text(source)
            self.compile("build-params", path, path.with_suffix(".json"))
            for name, text in {
                "approved": source.replace("  approved: false", "  approved: true", 1),
                "evidence": source.replace("  image_evidence: ''", "  image_evidence: 'claimed'"),
                "knowledge": source.replace("knowledge: { approved: true", "knowledge: { approved: false"),
                "identity": re.sub(r"  identity: \{.*?\n  \}", "  identity: null", source, flags=re.S),
                "digest": source.replace("image_algorithm: 'sha256'", "image_algorithm: 'tag'"),
            }.items():
                path.write_text(text)
                result = subprocess.run([self.compiler, "build-params", str(path), "--outfile", str(path.with_suffix(".json"))], capture_output=True, text=True, check=False)
                self.assertNotEqual(result.returncode, 0, f"deferred {entry} {name} unexpectedly compiled")

    def test_custom_analyzer_ids_reject_hyphens(self):
        for analyzer in ("application-review", "", "a" * 65):
            self.assertTrue(validate({"analyzer_id": analyzer}, allow_examples=True))
        self.assertEqual(validate({"analyzer_id": "application_review"}, allow_examples=True), [])
        self.assertTrue(validate({"application": {"analyzer_id": "application-review", "confidence_threshold": 0.9, "processing_location": "geography", "field_names": ["ApplicantName"]}}, allow_examples=True))

    def test_egress_cannot_split_all_internet_across_cidrs(self):
        split = ["0.0.0.0/1", "128.0.0.0/1"]
        self.assertTrue(validate({"approved_https_cidrs": split}, allow_examples=True))
        self.assertTrue(validate({"approved_egress": [{"destination_cidr": cidr, "port": 443} for cidr in split]}, allow_examples=True))
        quarters = ["0.0.0.0/2", "64.0.0.0/2", "128.0.0.0/2", "192.0.0.0/2"]
        self.assertTrue(validate({"approved_https_cidrs": quarters}, allow_examples=True))
        self.assertEqual(validate({"approved_https_cidrs": ["10.80.2.0/24", "10.80.2.10/32"]}, allow_examples=True), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
