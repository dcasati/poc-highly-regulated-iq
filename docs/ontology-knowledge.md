# Seeded ontologies in Foundry IQ

The template includes a Git-owned **Site/Asset ontology**, seeded lakehouse data, and a deployment-plan action that binds them in the target workspace. Terraform can register this and additional DEV ontologies in the **same Foundry IQ knowledge base** as the OneLake documents.

This uses the native [`fabricOntology` knowledge source (preview)](https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-fabric-ontology), not document export or a custom MCP proxy. The source queries Fabric at retrieval time; it doesn't create an index, copy table rows to Search, or use the file indexer's five-minute schedule.

## Included scenario

| Ontology definition | Backing data |
| --- | --- |
| `Site`: SiteId, SiteName, Region | `Scenario.dbo.demo_sites` |
| `Asset`: AssetId, AssetSiteId, AssetName, Status | `Scenario.dbo.demo_assets` |
| `LocatedAt`: Asset -> Site | `demo_assets.site_id -> demo_sites.site_id` |

[`ScenarioOntology.Ontology`](../workspace/ScenarioOntology.Ontology) uses the [new-experience TMDL definition](https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/ontology-definition), with stable logical and lineage IDs. The initial backing tables deliberately have **no partitions**: they define the shape without embedding someone else's workspace/SQL endpoint. The ontology is not data-query-ready until binding completes.

The [`Bootstrap` plan](../workspace/Bootstrap.DeploymentPlan/plan.yml) runs this sequence:

1. Deploy `Scenario`, then deploy and execute `SeedScenario` to insert missing synthetic rows and `Files/starter.txt`.
2. Deploy `ScenarioOntology` with its entities, properties and relationship.
3. Deploy and execute `BindScenario`. It resolves both items in the **current workspace**, refreshes SQL metadata for only `dbo.demo_sites` and `dbo.demo_assets`, and checks both per-table results.
4. The binder adds the sample's Direct Lake partitions and `ScenarioLakehouse` expression, using `AzureStorage.DataLake` with the current workspace/lakehouse GUID-based OneLake URL in an M `let ... in ...` block. It also pins Fabric's `ONT_*` partition annotations, then reads back the definition and prints the lakehouse/ontology GUIDs.

The native binding needs both the OneLake expression and the partition's Fabric source identity. `ONT_ItemId` is the physical **lakehouse** GUID and `ONT_ItemKind` is `Lakehouse`; `ONT_SqlDatabase` is the lakehouse's **display name**, not its SQL endpoint GUID. The SQL endpoint GUID is used only for scoped metadata refresh. The binder refreshes these pins for each target and preserves their timestamp on an unchanged rerun. A SQL-only expression without the pins can pass definition validation while the UI reports that the source's Fabric item kind cannot be identified.

Fabric Git normalizes `ONT_WorkspaceId` to a zero GUID, `ONT_ItemId` to the lakehouse's logical ID, and `ONT_WorkspaceName` to a placeholder. These are Git representations, not runtime source values. Rebind each target and inspect its live definition and data-backed query; do not treat the exported placeholders or an unchanged OneLake expression as proof of target readiness.

[`BindScenario`](../workspace/BindScenario.Notebook/notebook-content.py) has a 15-minute default deadline, honors throttling/polling delays and surfaces failures. It uses the Fabric runtime's `notebookutils` credential; no token is in Git or Terraform. Its identity needs workspace Contributor or higher and the API permissions to list/read items, refresh SQL metadata, and read/write ontology definitions.

**Run the bundled binding action as an authorized Fabric user.** [NotebookUtils `pbi` tokens have restricted scopes under service principals](https://learn.microsoft.com/fabric/data-engineering/notebookutils/notebookutils-credentials#considerations), omitting the full Fabric scopes needed here. Unattended service-principal execution needs an explicitly designed authentication flow in the derived project; the notebook does not switch identities or fall back to stored credentials on a permission failure.

The binder is intentionally **sample-specific**, not a generic TMDL rewriter. It checks the logical ID and generation in ontology item metadata, the `BootstrapBinding` annotations on both entities, and the source expression's lineage tag. It preserves unrelated definition parts and refuses custom partitions or source expressions rather than guessing how to overwrite them. Use the default definition endpoint and verify its TMDL parts: an explicit `format=TMDL` can be rejected, exported `.platform` can contain a placeholder logical ID, and model-level annotations can be omitted. Entity-level annotations survive the round trip. A correctly bound rerun does not update the ontology again. It neither seeds data nor materializes graphs.

### Review the generated binding

Binding updates the live ontology definition, so the first run can leave it **modified in Fabric source control**. Review and commit the generated partitions, expression and any service-normalized TMDL in the derived DEV repository before promotion. Endpoint IDs are configuration, not credentials. Preserve the binding markers when accepting that export.

Native promotion copies those definitions, including their source references. Always attach the plan so `BindScenario` rebinds the target to its **own** lakehouse before it is used. Target-specific binding differences are expected; don't mistake them for unreviewed business-model changes or overwrite them with DEV values.

Serialize deployment and ontology authoring. The public `updateDefinition` API replaces the definition and has no conditional-update header; the notebook checks for an intervening change before updating, but cannot eliminate a concurrent-edit race. If an operation fails or times out, inspect its status before rerunning. Don't expose a partially deployed/unbound ontology to consumers.

## Register the bound ontology

After bootstrap, check the entities and a data-backed question in Fabric. Then put the **physical DEV item GUIDs** printed by the notebooks into the same local tfvars file used for platform setup:

```hcl
knowledge_lakehouse_id = "<dev-Scenario-lakehouse-guid>"
knowledge_ontologies = {
  scenario = {
    ontology_id = "<dev-ScenarioOntology-guid>"
    description = "Current sites, assets, their status, and which site each asset belongs to."
  }
}
```

Run the normal knowledge plan/apply from [getting started](getting-started.md). Terraform looks up each ontology in DEV without owning its definition, creates a native `fabricOntology` source, and includes it alongside the indexed OneLake source in `knowledgeSources`. The description helps the retrieval model select the right source.

Use a separate stable map key for each additional ontology. Export its real definition to `workspace/`, supply its seed/binding actions and plan dependencies, then add its physical DEV GUID and domain description to `knowledge_ontologies`. Don't duplicate the sample logical ID for a different ontology. The reusable Terraform registration is not limited to the Site/Asset schema.

Leave the map empty to use only indexed documents. Nonempty registrations require `knowledge_lakehouse_id`; they are part of the second setup stage. Removing an entry removes its Search knowledge-source registration, **not** the Fabric ontology or data. Ontology parameter changes update the live source in place; no index rebuild is needed.

Outputs `ontology_knowledge_sources` and `knowledge_base_requires_user_token` identify the sources and the runtime authorization requirement. Terraform registration is not evidence that a user can successfully query the ontology.

## Supply the end user's identity at query time

There are two separate authentication layers:

| Layer | Requirement |
| --- | --- |
| Caller -> Azure AI Search knowledge base | Normal Search authentication and `Search Index Data Reader` for an Entra caller. The existing Foundry project connection uses its managed identity for this hop. |
| Knowledge base -> Fabric ontology | An **end-user** token in `x-ms-query-source-authorization`, scoped to `https://search.azure.com/.default`. Search exchanges it for a Fabric-scoped token on the user's behalf. The user must be allowed to read the ontology and its bound data. |

The Search and Fabric resources must share an Entra tenant. Enable the Fabric ontology tenant settings and complete any tenant consent required for the documented delegated flow. **Do not use the Search or Foundry managed identity token as a substitute for the end-user token.** Ontology retrieval does not inherit access from the seeding identity or Search's workspace Contributor grant.

For a direct retrieval request, the header arrangement is:

```http
POST <search-endpoint>/knowledgebases/<knowledge-base-name>/retrieve?api-version=2026-08-01-preview
Authorization: Bearer <search-caller-access-token>
x-ms-query-source-authorization: <end-user-search-audience-access-token>
Content-Type: application/json

{
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Using ScenarioOntology, which assets are in Maintenance and at which site?"
        }
      ]
    }
  ]
}
```

Tokens are placeholders, **not configuration values to store in tfvars or source control**. Acquire the user's token in your application's approved sign-in/OBO flow, not from a chat prompt. Forward it per request, protect logs, and refuse an ontology query if the required identity is missing.

For a consuming Foundry agent, keep the knowledge-base MCP connection and add this per-request header to its MCP tool using [structured inputs or supported OAuth identity passthrough](https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect#optional-enforce-permissions-with-per-request-headers). The template doesn't provision that consuming agent or user sign-in flow. Creating the managed-identity connection alone does not complete ontology authentication.

For an untouched seed, the example question should identify **Pump B at North Works**. Inspect the retrieval response for an `activity` entry and `references` of type `fabricOntology`, with the expected workspace and ontology IDs. A correct-sounding answer from `starter.txt` alone is **not** proof of ontology integration. Include a user without Fabric access in your derived project's authorization checks and surface denied/failed sources rather than silently substituting the document snapshot.

## Extending and promoting

Put consumers that need bound data after the completed **BindScenario** group, not merely after the lakehouse/seed group. For a different schema, adapt a separate binder with explicit source mappings and preserve the public definition format; don't turn the sample into an unrestricted find/replace script.

`BindScenario` waits for the two tables' SQL metadata, but does not perform a graph load or semantic-model refresh. Those consumers still need their own readiness/refresh steps. PROD should normally omit demo seeding and use approved data ingestion; binding to a target-local lakehouse remains necessary.

Both ontology and Foundry IQ source integration are preview features. Review Fabric/Foundry availability, costs and compliance boundaries for the deployment region. No live deployment or query is performed as a template-maintenance check.
