# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {}
# META }

# MARKDOWN ********************

# # Seed the scenario
# Run after the Scenario lakehouse is deployed. No default lakehouse attachment
# is required: the target is resolved only in this notebook's current workspace.
# Missing synthetic keys are inserted; existing rows and starter.txt are preserved.
# By default, only workspaces ending in -dev or -test may receive demo data.

# PARAMETERS CELL ********************

lakehouse_name = "Scenario"
allow_other_workspaces = False

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

from uuid import UUID

import notebookutils
from delta.tables import DeltaTable
from pyspark.sql import SparkSession

context = notebookutils.runtime.context
workspace_id = str(UUID(context["currentWorkspaceId"]))
workspace_name = context["currentWorkspaceName"]

if not isinstance(workspace_name, str) or not workspace_name:
    raise ValueError("The runtime must identify the current workspace name.")
if not isinstance(lakehouse_name, str) or not lakehouse_name.strip():
    raise ValueError("lakehouse_name must name a lakehouse in the current workspace.")
if type(allow_other_workspaces) is not bool:
    raise ValueError("allow_other_workspaces must be a Boolean, not a string.")
if not workspace_name.endswith(("-dev", "-test")) and not allow_other_workspaces:
    raise ValueError(
        "Demo seeding is restricted to -dev/-test workspaces. For an intentional "
        "exception, explicitly set allow_other_workspaces=True for this run."
    )

lakehouse = notebookutils.lakehouse.get(lakehouse_name, workspace_id)
if str(UUID(lakehouse.workspaceId)) != workspace_id:
    raise ValueError("Refusing to seed a lakehouse outside the current workspace.")

lakehouse_id = str(UUID(lakehouse.id))
lakehouse_path = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/{lakehouse_id}"
)
spark = SparkSession.builder.getOrCreate()

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

sites = [
    ("demo-site-001", "North Works", "North"),
    ("demo-site-002", "South Works", "South"),
]
assets = [
    ("demo-asset-001", "demo-site-001", "Pump A", "Operational"),
    ("demo-asset-002", "demo-site-001", "Pump B", "Maintenance"),
    ("demo-asset-003", "demo-site-002", "Conveyor A", "Operational"),
]


def seed_table(name, rows, schema, key):
    source = spark.createDataFrame(rows, schema=schema)
    path = f"{lakehouse_path}/Tables/dbo/{name}"
    if notebookutils.fs.exists(path):
        if not DeltaTable.isDeltaTable(spark, path):
            raise ValueError(f"Refusing to replace a non-Delta path: {path}")
        target = DeltaTable.forPath(spark, path)
        if target.toDF().schema.simpleString() != source.schema.simpleString():
            raise ValueError(f"Existing schema differs from the seed schema: {name}")
        (
            target.alias("target")
            .merge(source.alias("source"), f"target.{key} = source.{key}")
            .whenNotMatchedInsertAll()
            .execute()
        )
    else:
        source.write.format("delta").mode("errorifexists").save(path)
    print(f"{name}: inserted missing demo keys; retained all existing rows.")


seed_table(
    "demo_sites",
    sites,
    "site_id STRING, site_name STRING, region STRING",
    "site_id",
)
seed_table(
    "demo_assets",
    assets,
    "asset_id STRING, site_id STRING, asset_name STRING, status STRING",
    "asset_id",
)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

starter_document = """Synthetic asset operations starter knowledge

This is fictional demonstration data, not operational guidance.

North Works (demo-site-001) is in the North region. It has two assets:
Pump A (demo-asset-001), which is Operational, and Pump B (demo-asset-002),
which is in Maintenance.

South Works (demo-site-002) is in the South region. Its asset is
Conveyor A (demo-asset-003), which is Operational.

The demo_sites table defines sites. The demo_assets table defines assets.
demo_assets.site_id references demo_sites.site_id. ScenarioOntology maps these
tables to Site and Asset entities and their LocatedAt relationship.
BindScenario configures the target-specific binding.

This starter document is indexed from the lakehouse Files area by Foundry IQ.
The Delta tables and ontology are not indexed by that OneLake Files knowledge
source. Register ScenarioOntology as a separate fabricOntology knowledge source
to query its bound data live, with a delegated end-user token.
The facts above describe the original seed, not current operational status.
Use the ontology source, not this document, for current entity values and counts.

Git versions item definitions and this notebook. The notebook materializes
the sample data in each target workspace; Git does not copy OneLake data.
Reruns preserve existing rows and this file, including any local edits.
"""

files_path = f"{lakehouse_path}/Files"
starter_path = f"{files_path}/starter.txt"
if notebookutils.fs.exists(starter_path):
    print("Preserving existing Files/starter.txt.")
else:
    if not notebookutils.fs.mkdirs(files_path):
        raise RuntimeError(f"Could not create the Files directory: {files_path}")
    if not notebookutils.fs.put(starter_path, starter_document, False):
        raise RuntimeError(f"Could not write starter knowledge: {starter_path}")
    print("Created Files/starter.txt.")

print(f"Seed completed in {workspace_name}; lakehouse GUID: {lakehouse_id}")
print("SQL endpoint discovery, graph loading and semantic-model refresh are separate.")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
