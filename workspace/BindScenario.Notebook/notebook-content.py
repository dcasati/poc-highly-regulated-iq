# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {}
# META }

# MARKDOWN ********************

# # Bind the scenario ontology
# Run after SeedScenario and ScenarioOntology deploy. This notebook does not seed
# data or create items. It binds only the sample ontology to its current workspace.
# Run as an authorized Fabric user; service-principal NotebookUtils tokens lack
# the full Fabric scopes needed for these definition/metadata operations.
# Serialize runs and authoring: updateDefinition replaces the item's definition.
# Review and commit the generated DEV binding through Fabric source control.

# PARAMETERS CELL ********************

lakehouse_name = "Scenario"
ontology_name = "ScenarioOntology"
timeout_seconds = 900

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import base64
import copy
import json
import re
import time
from datetime import datetime, timezone
from uuid import UUID

import notebookutils
import requests

if type(timeout_seconds) is not int or not 1 <= timeout_seconds <= 3600:
    raise ValueError("timeout_seconds must be an integer from 1 to 3600.")
if not all(isinstance(name, str) and name.strip() for name in (lakehouse_name, ontology_name)):
    raise ValueError("Supply lakehouse and ontology display names in the current workspace.")

workspace_id = str(UUID(notebookutils.runtime.context["currentWorkspaceId"]))
workspace_name = notebookutils.runtime.context["currentWorkspaceName"]
deadline = time.monotonic() + timeout_seconds
api_root = "https://api.fabric.microsoft.com"
sample_logical_id = "e6a99499-e3f5-4a9b-8288-3985c73a05e5"
table_names = ("demo_sites", "demo_assets")
binding_marker = "annotation BootstrapBinding = site-asset-v1"
source_lineage_tag = "afcdf5a6-abb9-4722-81d6-c540ac4b4433"


def remaining_seconds():
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("Ontology binding timed out; inspect Fabric operations before rerunning.")
    return remaining


def wait_for_poll(seconds):
    if seconds < 0:
        raise ValueError("A polling delay cannot be negative.")
    if seconds >= remaining_seconds():
        raise TimeoutError("The next Fabric poll exceeds the ontology binding timeout.")
    time.sleep(seconds)


def fabric_request(method, path, **kwargs):
    if not path.startswith("/v1/") or "://" in path:
        raise ValueError("Fabric requests must use a relative v1 API path.")
    while True:
        response = requests.request(
            method,
            f"{api_root}{path}",
            headers={"Authorization": f"Bearer {notebookutils.credentials.getToken('pbi')}"},
            timeout=min(30, remaining_seconds()),
            allow_redirects=False,
            **kwargs,
        )
        if response.status_code == 429:
            wait_for_poll(int(response.headers.get("Retry-After", "5")))
            continue
        if response.status_code not in (200, 201, 202, 204):
            raise RuntimeError(
                f"Fabric {method} {path} failed ({response.status_code}): {response.text[:1000]}"
            )
        return response


def fabric_operation(path, body=None, has_result=True):
    response = fabric_request("POST", path, json=body)
    if response.status_code == 202:
        operation_id = str(UUID(response.headers["x-ms-operation-id"]))
        print(f"Waiting for Fabric operation {operation_id}: {path}")
        while True:
            wait_for_poll(int(response.headers.get("Retry-After", "5")))
            response = fabric_request("GET", f"/v1/operations/{operation_id}")
            operation = response.json()
            if operation["status"] == "Succeeded":
                break
            if operation["status"] not in ("NotStarted", "Running"):
                raise RuntimeError(f"Fabric operation {operation_id} failed: {operation}")
        if has_result:
            response = fabric_request("GET", f"/v1/operations/{operation_id}/result")
    return response.json() if has_result else None


def find_item(item_type, display_name):
    matches = []
    params = {"type": item_type}
    seen_tokens = set()
    while True:
        page = fabric_request("GET", f"/v1/workspaces/{workspace_id}/items", params=params).json()
        matches.extend(item for item in page["value"] if item["displayName"] == display_name)
        token = page.get("continuationToken")
        if not token:
            break
        if token in seen_tokens:
            raise RuntimeError("Fabric item listing repeated its continuation token.")
        seen_tokens.add(token)
        params = {"type": item_type, "continuationToken": token}
    if len(matches) != 1:
        raise ValueError(f"Expected one {item_type} named {display_name} in the current workspace.")
    item = matches[0]
    if item["type"] != item_type or str(UUID(item["workspaceId"])) != workspace_id:
        raise ValueError("Fabric returned an item outside the requested workspace/type.")
    return str(UUID(item["id"]))


def get_definition(ontology_id):
    item = fabric_request(
        "GET", f"/v1/workspaces/{workspace_id}/ontologies/{ontology_id}"
    ).json()
    if (
        item["type"] != "Ontology"
        or str(UUID(item["workspaceId"])) != workspace_id
        or str(UUID(item["logicalId"])) != sample_logical_id
        or item["properties"]["generation"] != 2
    ):
        raise ValueError("BindScenario requires the current workspace's new-experience sample ontology.")
    # The definition export can return a placeholder logical ID; item metadata is authoritative.
    definition = fabric_operation(
        f"/v1/workspaces/{workspace_id}/ontologies/{ontology_id}/getDefinition"
    )["definition"]
    parts = {part["path"]: part for part in definition["parts"]}
    if len(parts) != len(definition["parts"]):
        raise ValueError("The ontology definition contains duplicate part paths.")
    required_parts = {
        ".platform", "database.tmdl", "model.tmdl",
        "entities/Site.tmdl", "entities/Asset.tmdl",
        "tables/demo_sites.tmdl", "tables/demo_assets.tmdl",
    }
    if not required_parts.issubset(parts):
        raise ValueError("The ontology did not return the required sample TMDL parts.")
    return parts


def part_text(parts, path):
    part = parts[path]
    if part["payloadType"] != "InlineBase64":
        raise ValueError(f"Unsupported ontology payload type: {path}")
    return base64.b64decode(part["payload"], validate=True).decode("utf-8")


def set_part(parts, path, text):
    parts[path] = {
        "path": path,
        "payload": base64.b64encode(text.encode("utf-8")).decode("ascii"),
        "payloadType": "InlineBase64",
    }


def bind_partition_annotations(text, values):
    lines = text.splitlines(keepends=True)
    starts = [index for index, line in enumerate(lines) if line.startswith("\tpartition ")]
    if len(starts) != 1:
        raise ValueError("Expected one canonically indented sample partition.")
    start = starts[0]
    end = next(
        (index for index in range(start + 1, len(lines))
         if lines[index].strip() and not lines[index].startswith("\t\t")),
        len(lines),
    )
    pattern = r"^\t\tannotation[ \t]+(ONT_[A-Za-z0-9_]+)[ \t]*=[ \t]*(.*?)\r?\n?$"
    existing = {}
    for line in lines[start:end]:
        match = re.match(pattern, line)
        if match:
            name, value = match.groups()
            if name in existing:
                raise ValueError(f"Duplicate partition annotation: {name}")
            existing[name] = value
    if existing.get("ONT_ItemKind", "Lakehouse") != "Lakehouse":
        raise ValueError("Refusing to replace a non-Lakehouse source binding.")
    if all(existing.get(name) == value for name, value in values.items()) and existing.get("ONT_PinnedAtUtc"):
        return text

    updates = {
        **values,
        "ONT_PinnedAtUtc": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
    }
    newline = "\r\n" if "\r\n" in text else "\n"
    block = []
    for line in lines[start:end]:
        match = re.match(pattern, line)
        if match and match[1] in updates:
            line = f"\t\tannotation {match[1]} = {updates[match[1]]}{newline}"
        block.append(line)
    missing = [name for name in updates if name not in existing]
    body = "".join(block)
    if missing:
        body = body.rstrip("\r\n") + newline * 2
        body += (newline * 2).join(f"\t\tannotation {name} = {updates[name]}" for name in missing)
        body += newline * 2
    return "".join(lines[:start]) + body + "".join(lines[end:])


def bound_definition(original, lakehouse, target_workspace_name):
    target_workspace_id = str(UUID(lakehouse["workspaceId"]))
    lakehouse_id = str(UUID(lakehouse["id"]))
    if target_workspace_id != workspace_id or lakehouse["type"] != "Lakehouse":
        raise ValueError("Refusing to bind to a lakehouse outside the current workspace.")
    sql_host = lakehouse["properties"]["sqlEndpointProperties"]["connectionString"]
    if not re.fullmatch(r"[A-Za-z0-9.-]+(?:,1433)?", sql_host):
        raise ValueError("The lakehouse returned an unexpected SQL endpoint hostname.")
    annotations = {
        "ONT_WorkspaceId": target_workspace_id,
        "ONT_ItemId": lakehouse_id,
        "ONT_ItemKind": "Lakehouse",
        "ONT_ItemName": lakehouse["displayName"],
        "ONT_WorkspaceName": target_workspace_name,
        "ONT_SqlEndpoint": sql_host,
        "ONT_SqlDatabase": lakehouse["displayName"],
    }
    if any(
        not isinstance(value, str) or not value or value != value.strip()
        or any(character in value for character in ("\r", "\n", "\0"))
        for value in annotations.values()
    ):
        raise ValueError("Source metadata must contain nonempty, single-line values.")

    parts = copy.deepcopy(original)
    platform = json.loads(part_text(parts, ".platform"))
    if platform["metadata"]["type"] != "Ontology":
        raise ValueError("The selected item is not an ontology.")
    for entity_name in ("Site", "Asset"):
        if binding_marker not in (
            line.strip() for line in part_text(parts, f"entities/{entity_name}.tmdl").splitlines()
        ):
            raise ValueError(f"The {entity_name} entity is missing its site-asset-v1 binding marker.")

    for table_name in table_names:
        path = f"tables/{table_name}.tmdl"
        text = part_text(parts, path)
        partitions = re.findall(r"(?m)^[ \t]+partition[ \t]+([^\r\n]+)", text)
        if partitions:
            expected = {
                "mode": "directLake",
                "entityName": table_name,
                "schemaName": "dbo",
                "expressionSource": "ScenarioLakehouse",
            }
            if len(partitions) != 1 or partitions[0].strip() not in (
                f"{table_name} = entity", f"'{table_name}' = entity"
            ):
                raise ValueError(f"Refusing to replace custom partitions in {path}.")
            for field, value in expected.items():
                values = re.findall(rf"(?m)^[ \t]+{field}:[ \t]+([^\r\n]+)", text)
                if [entry.strip().strip("'") for entry in values] != [value]:
                    raise ValueError(f"Unexpected {field} in {path}; review the binding manually.")
        else:
            text = (
                f"{text.rstrip()}\n\n"
                f"\tpartition {table_name} = entity\n"
                "\t\tmode: directLake\n"
                "\t\tsource\n"
                f"\t\t\tentityName: {table_name}\n"
                "\t\t\tschemaName: dbo\n"
                "\t\t\texpressionSource: ScenarioLakehouse\n"
            )
        annotated = bind_partition_annotations(text, annotations)
        if annotated != part_text(parts, path):
            set_part(parts, path, annotated)

    onelake_root = f"https://onelake.dfs.fabric.microsoft.com/{target_workspace_id}/{lakehouse_id}"
    source_call = f'AzureStorage.DataLake("{onelake_root}", [HierarchicalNavigation=true])'
    expression = (
        "expression ScenarioLakehouse =\n"
        "\t\tlet\n"
        f"\t\t\tSource = {source_call}\n"
        "\t\tin\n"
        "\t\t\tSource\n"
        f"\tlineageTag: {source_lineage_tag}\n"
    )
    path = "expressions.tmdl"
    if path not in parts:
        set_part(parts, path, expression)
    else:
        text = part_text(parts, path)
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        if (
            len(lines) != 6
            or lines[0] not in ("expression ScenarioLakehouse =", "expression 'ScenarioLakehouse' =")
            or lines[1] != "let" or lines[3:5] != ["in", "Source"]
            or lines[5] != f"lineageTag: {source_lineage_tag}"
        ):
            raise ValueError("Refusing to overwrite an unrecognized source expression.")
        native = re.fullmatch(
            r'Source\s*=\s*AzureStorage\.DataLake\(\s*"'
            r'(https://onelake\.dfs\.fabric\.microsoft\.com/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36})'
            r'"\s*,\s*\[\s*HierarchicalNavigation\s*=\s*true\s*\]\s*\)',
            lines[2],
        )
        # Repair only the SQL expression previously generated by this same marked binder.
        previous_sql = re.fullmatch(
            r'Source\s*=\s*Sql\.Database\(\s*"[A-Za-z0-9.-]+(?:,1433)?"\s*,\s*"[0-9a-fA-F-]{36}"\s*\)',
            lines[2],
        )
        if not native and not previous_sql:
            raise ValueError("Refusing to overwrite a custom source connector or transformation.")
        if not native or native[1] != onelake_root:
            set_part(parts, path, expression)
    return parts

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

lakehouse_id = find_item("Lakehouse", lakehouse_name)
ontology_id = find_item("Ontology", ontology_name)
original = get_definition(ontology_id)

while True:
    lakehouse = fabric_request(
        "GET", f"/v1/workspaces/{workspace_id}/lakehouses/{lakehouse_id}"
    ).json()
    if str(UUID(lakehouse["workspaceId"])) != workspace_id:
        raise ValueError("Refusing to bind to a different workspace.")
    if lakehouse["properties"].get("defaultSchema") != "dbo":
        raise ValueError("Scenario must be a schema-enabled lakehouse with default schema dbo.")
    sql_endpoint = lakehouse["properties"]["sqlEndpointProperties"]
    if sql_endpoint["provisioningStatus"] == "Success":
        break
    if sql_endpoint["provisioningStatus"] != "InProgress":
        raise RuntimeError(f"SQL endpoint provisioning failed: {sql_endpoint['provisioningStatus']}")
    wait_for_poll(5)

sql_id = str(UUID(sql_endpoint["id"]))
updated = bound_definition(original, lakehouse, workspace_name)

sync = fabric_operation(
    f"/v1/workspaces/{workspace_id}/sqlEndpoints/{sql_id}/refreshMetadata",
    {
        "recreateTables": False,
        "tables": [{"schema": "dbo", "tableNames": list(table_names)}],
        "timeout": {"timeUnit": "Seconds", "value": int(remaining_seconds())},
    },
)
statuses = {}
for result in sync["value"]:
    name = result["tableName"].removeprefix("dbo.")
    if name in statuses or name not in table_names:
        raise RuntimeError(f"Unexpected SQL metadata refresh result: {result}")
    statuses[name] = result
if set(statuses) != set(table_names):
    raise RuntimeError(f"SQL metadata refresh did not report both seeded tables: {statuses}")
for name, result in statuses.items():
    if result["status"] == "Success" or (
        result["status"] == "NotRun" and result.get("lastSuccessfulSyncDateTime")
    ):
        print(f"SQL metadata ready: dbo.{name}")
    else:
        raise RuntimeError(f"SQL metadata is not ready for dbo.{name}: {result}")

if updated != original:
    if get_definition(ontology_id) != original:
        raise RuntimeError("The ontology changed during binding. Serialize authoring and rerun.")
    fabric_operation(
        f"/v1/workspaces/{workspace_id}/ontologies/{ontology_id}/updateDefinition",
        {"definition": {"parts": list(updated.values())}},
        has_result=False,
    )
    verified = get_definition(ontology_id)
    if bound_definition(verified, lakehouse, workspace_name) != verified:
        raise RuntimeError("The ontology update completed without the expected target binding.")
    print("Bound ScenarioOntology. Review and commit the generated DEV definition in Git.")
else:
    print("ScenarioOntology is already bound to the current workspace's lakehouse.")

print(f"Lakehouse GUID: {lakehouse_id}")
print(f"Ontology GUID: {ontology_id}")
print("Register this physical ontology GUID in knowledge_ontologies after checking a Fabric query.")
print("Foundry IQ ontology retrieval also requires the signed-in user's delegated token.")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
