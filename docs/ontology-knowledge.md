# Knowledge boundaries

The private document-review application indexes **human-approved PDFs and corrected field JSON** in Azure AI Search. Its API enforces case/owner filters before using Foundry IQ retrieval. Follow [getting started](getting-started.md) for native Search registration and [the scenario](highly-regulated-scenario.md) for authorization and publication.

## Disconnected Fabric sample

`workspace/` retains an inherited Site/Asset ontology, lakehouse and notebooks. They are not connected to the review application's retrieval path, and do not need deployment, Git sync or execution to run this PoC.

For explicitly requested Fabric work, use the [fabric-workspace skill](../.github/skills/fabric-workspace/SKILL.md). Preserve `.platform` logical identities, TMDL lineage tags and binding markers. Resolve physical lakehouse/ontology IDs only in the chosen workspace; do not substitute logical IDs or IDs from another project.

Preserve `ONT_*` binding pins and resolve them in the target workspace. The SQL database pin is the lakehouse display name, not the SQL endpoint GUID. Git-normalized zero/logical IDs and workspace-name placeholders are not valid runtime bindings.

Native `fabricOntology` queries require an end-user Search-audience token in `x-ms-query-source-authorization`; a managed identity does not replace that delegated authorization. Keep this separate from the application's approved-document sources. A seeded or bound sample is not evidence that application indexing or retrieval is ready.
