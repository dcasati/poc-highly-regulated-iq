"""Compile all parallel sources/examples and test their emitted ARM contracts offline."""

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
        cls.temp = tempfile.TemporaryDirectory(prefix="private-review-bicep-")
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
            "groups.bicep", "connectivity/main.bicep", "state-backend/main.bicep", "state-backend/grant.bicep",
            "foundation/main.bicep", "foundation/project.bicep", "foundation/provisioning.bicep",
            "foundation/capability.bicep", "foundation/runtime-bindings.bicep",
            "scenario/platform.bicep", "scenario/private-links.bicep", "scenario/hosting.bicep",
            "scenario/runtime.bicep", "scenario/aks-manifests.bicep", "knowledge/payloads.bicep",
            "acr-build/main.bicep",
        }
        covered = set()
        for path in (ROOT / "examples").glob("*.example.bicepparam"):
            match = re.search(r"using '([^']+)'", path.read_text())
            covered.add(str((path.parent / match[1]).resolve().relative_to(ROOT)))
            self.assertEqual(validate(self.examples[path.name], allow_examples=True), [], path.name)
        self.assertEqual(required, covered)

    def test_platform_stage_has_no_hosting_runtime_or_knowledge(self):
        types = {r["type"] for r in resources(self.templates["scenario/platform.bicep"]) if not r.get("existing")}
        self.assertIn("Microsoft.ContainerRegistry/registries", types)
        self.assertIn("Microsoft.Storage/storageAccounts/blobServices/containers", types)
        self.assertFalse(any(t.startswith(("Microsoft.App/", "Microsoft.ContainerService/")) for t in types))
        self.assertNotIn("portal_url", self.templates["scenario/platform.bicep"].get("outputs", {}))
        self.assertNotIn("identity", self.templates["scenario/platform.bicep"]["parameters"])

    def test_foundation_stages_are_separate_and_native_stores_never_created(self):
        initial = list(resources(self.templates["foundation/main.bicep"]))
        self.assertFalse(any("/projects" in r["type"] for r in initial))
        project = self.templates["foundation/project.bicep"]["resources"]["project"]
        self.assertEqual(project["apiVersion"], "2025-06-01")
        self.assertEqual(project["identity"]["type"], "SystemAssigned")
        connections = self.templates["foundation/provisioning.bicep"]["resources"]["connections"]
        self.assertEqual(connections["apiVersion"], "2025-06-01")
        self.assertEqual(connections["properties"]["authType"], "AAD")
        self.assertFalse(connections["properties"]["isSharedToAll"])
        host = self.templates["foundation/capability.bicep"]["resources"]["host"]
        self.assertEqual(host["apiVersion"], "2025-04-01-preview")
        self.assertEqual(host["properties"]["capabilityHostKind"], "Agents")
        for r in resources(self.templates["foundation/runtime-bindings.bicep"]):
            if r["type"].endswith("/sqlDatabases"):
                self.assertTrue(r.get("existing"))
            if r["type"].endswith("/containers") and not r.get("existing"):
                self.assertEqual(r["condition"], "[parameters('create_containers')]")
        modules = self.templates["foundation/runtime-bindings.bicep"]["resources"]
        self.assertFalse(modules["blob_roles"]["properties"]["parameters"]["create_containers"]["value"])
        self.assertTrue(self.templates["foundation/runtime-bindings.bicep"]["outputs"]["bootstrap_revocation_required"]["value"])

    def test_hosting_choices_are_mutually_exclusive_and_deferred(self):
        template = self.templates["scenario/hosting.bicep"]
        self.assertEqual(template["parameters"]["hosting"]["defaultValue"], {"kind": "container_apps"})
        emitted = template["resources"]
        self.assertEqual(emitted["environment"]["condition"], "[equals(parameters('hosting').kind, 'container_apps')]")
        self.assertEqual(emitted["aks"]["condition"], "[equals(parameters('hosting').kind, 'aks')]")
        for kind in ("container_apps", "aks"):
            self.assertEqual(sum(kind == selected for selected in ("container_apps", "aks")), 1)
        self.assertNotIn("portal_url", template.get("outputs", {}))
        self.assertFalse(any(r["type"] == "Microsoft.App/containerApps" for r in resources(template)))
        cluster = self.templates["scenario/hosting-aks.bicep"]["resources"]["cluster"]
        self.assertTrue(cluster["properties"]["disableLocalAccounts"])
        self.assertTrue(cluster["properties"]["apiServerAccessProfile"]["enablePrivateCluster"])
        self.assertEqual(cluster["properties"]["networkProfile"]["outboundType"], "userDefinedRouting")
        self.assertTrue(all(pool["enableFIPS"] for pool in cluster["properties"]["agentPoolProfiles"]))
        self.assertEqual(cluster["properties"]["serviceMeshProfile"]["istio"]["components"]["ingressGateways"], [{"mode": "Internal", "enabled": True}])

    def test_runtime_gates_are_required_typed_and_no_mutable_image(self):
        for path in ("scenario/runtime.bicep", "scenario/aks-manifests.bicep"):
            template = self.templates[path]
            self.assertNotIn("defaultValue", template["parameters"]["runtime"])
            runtime = definition(template, template["parameters"]["runtime"])
            self.assertEqual(runtime["properties"]["approved"]["allowedValues"], [True])
            self.assertEqual(runtime["properties"]["image_algorithm"]["allowedValues"], ["sha256"])
            self.assertEqual(runtime["properties"]["image_hash"]["minLength"], 64)
            for evidence in ("platform_evidence", "image_evidence", "transport_evidence"):
                self.assertEqual(runtime["properties"][evidence]["minLength"], 1)
            self.assertNotIn("nullable", runtime["properties"]["identity"])
            knowledge = definition(template, runtime["properties"]["knowledge"])
            self.assertEqual(knowledge["properties"]["approved"]["allowedValues"], [True])
        app = self.templates["scenario/runtime.bicep"]["resources"]["app"]
        image = app["properties"]["template"]["containers"][0]["image"]
        self.assertIn("/review-portal@", image)
        self.assertIn("image_algorithm", image)
        self.assertFalse(app["properties"]["configuration"]["ingress"]["allowInsecure"])
        self.assertEqual(app["properties"]["template"]["scale"]["minReplicas"], 1)

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
        self.assertFalse(account["properties"]["networkInjections"][0]["useMicrosoftManagedNetwork"])
        self.assertNotIn("capabilitySettings", json.dumps(foundation))
        self.assertTrue(foundation["search"]["properties"]["disableLocalAuth"])
        self.assertEqual(foundation["search"]["properties"]["networkRuleSet"]["bypass"], "None")
        self.assertTrue(foundation["cosmos"]["properties"]["disableLocalAuth"])
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

    def test_roles_are_scoped_deterministic_and_native_data_remains_read_only(self):
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
        self.assertFalse(self.templates["modules/storage-bindings.bicep"]["parameters"]["create_containers"]["defaultValue"])
        cosmos = list(resources(self.templates["modules/cosmos-data-role.bicep"]))
        self.assertEqual([r["type"] for r in cosmos if not r.get("existing")], ["Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments"])
        self.assertIn("/dbs/", cosmos[0]["properties"]["scope"])
        self.assertIn("reference(", cosmos[0]["properties"]["scope"])

    def test_no_fake_arm_data_plane_resources_or_deployment_scripts(self):
        for template in self.templates.values():
            for resource in resources(template):
                self.assertNotIn("deploymentScripts", resource["type"])
                self.assertFalse(resource["type"].startswith(("Microsoft.Search/searchServices/indexes", "Microsoft.Search/searchServices/knowledge", "Microsoft.KubernetesConfiguration/")))
        self.assertEqual(self.templates["knowledge/payloads.bicep"].get("resources", {}), {})
        self.assertEqual(self.templates["scenario/aks-manifests.bicep"].get("resources", {}), {})

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
        manifests = self.templates["scenario/aks-manifests.bicep"]["variables"]
        self.assertEqual(manifests["peer"]["spec"]["mtls"]["mode"], "STRICT")
        self.assertTrue(manifests["deployment"]["spec"]["template"]["spec"]["containers"][0]["securityContext"]["readOnlyRootFilesystem"])
        self.assertNotIn("0.0.0.0/0", json.dumps(manifests))

    def test_semantic_rejections(self):
        base = self.examples["runtime.example.bicepparam"]
        for field, value in (("image_hash", "g" * 64), ("identity", None), ("knowledge", {"approved": False}), ("image_evidence", "")):
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
        source = source.replace("using '../scenario/runtime.bicep'", f"using '{ROOT / 'scenario/runtime.bicep'}'")
        cases = {
            "unapproved": source.replace("approved: true", "approved: false", 1),
            "missing-evidence": source.replace("  transport_evidence: 'EXAMPLE-NOT-TRANSPORT-ACCEPTANCE'\n", ""),
            "null-browser": re.sub(r"  identity: \{.*?\n  \}", "  identity: null", source, flags=re.S),
            "mutable-image": source.replace("image_algorithm: 'sha256'", "image_algorithm: 'tag'"),
            "non-us": source.replace("location = 'eastus2'", "location = 'westeurope'"),
        }
        for name, text in cases.items():
            path = Path(self.temp.name) / f"{name}.bicepparam"
            path.write_text(text)
            result = subprocess.run([self.compiler, "build-params", str(path), "--outfile", str(path.with_suffix(".json"))], capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0, f"{name} unexpectedly compiled")

    def test_extra_runtime_principals_are_verified_guid_shapes(self):
        for principal in ("-" * 36, "not-a-guid", "00000000-0000-0000-0000-000000000000"):
            self.assertTrue(validate({"extra_principal_ids": [principal]}, allow_examples=True))
        valid = "11111111-1111-4111-8111-111111111111"
        self.assertEqual(validate({"extra_principal_ids": [valid]}, allow_examples=True), [])
        self.assertTrue(validate({"extra_principal_ids": [valid, valid.upper()]}, allow_examples=True))

    def test_egress_cannot_split_all_internet_across_cidrs(self):
        split = ["0.0.0.0/1", "128.0.0.0/1"]
        self.assertTrue(validate({"approved_https_cidrs": split}, allow_examples=True))
        self.assertTrue(validate({"approved_egress": [{"destination_cidr": cidr, "port": 443} for cidr in split]}, allow_examples=True))
        quarters = ["0.0.0.0/2", "64.0.0.0/2", "128.0.0.0/2", "192.0.0.0/2"]
        self.assertTrue(validate({"approved_https_cidrs": quarters}, allow_examples=True))
        self.assertEqual(validate({"approved_https_cidrs": ["10.80.2.0/24", "10.80.2.10/32"]}, allow_examples=True), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
