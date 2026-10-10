# Native Fabric bootstrap and promotion

This is inherited upstream reference material, not the private document-review
deployment path. Do not connect Fabric Git, apply the legacy `infra/` root or
execute these notebooks for the application; use [getting started](../docs/getting-started.md).

Use [Git integration](https://learn.microsoft.com/fabric/cicd/git-integration/intro-to-git-integration) for DEV and [native deployment pipelines](https://learn.microsoft.com/fabric/cicd/deployment-pipelines/intro-to-deployment-pipelines) for promotion. Attach a [deployment plan (preview)](https://learn.microsoft.com/fabric/cicd/deployment-plan/deployment-plan-overview) when item deployment must run seed notebooks or follow an explicit order.

```text
Terraform platform -> Git /workspace + Bootstrap -> seeded DEV -> Terraform knowledge
                                      reviewed DEV -> TEST -> approved TEST -> PROD
```

There is no fabric-cicd dependency, `fab deploy` configuration, or custom deployment wrapper. For a separately authorized Fabric deployment, start with [the upstream template's getting-started guide](https://github.com/dcasati/private-iq-template/blob/main/docs/getting-started.md); infrastructure still uses plain Terraform and one local tfvars file. Derived repositories own unattended automation, tests and approval gates.

## Ownership and included items

Terraform owns capacity, workspaces, permissions, the GitHub credentials connection, the DEV/TEST deployment pipeline, Foundry and Search. Git owns workspace item definitions. The seeder owns only the insertion of missing demo keys and initial starter content. Do not manage the same lakehouse or notebook with both Terraform and Git.

| Git item | Purpose |
| --- | --- |
| [`Scenario.Lakehouse`](../workspace/Scenario.Lakehouse) | Schema-enabled lakehouse with default schema `dbo`; Git does not contain its data. |
| [`SeedScenario.Notebook`](../workspace/SeedScenario.Notebook/notebook-content.py) | Synthetic sites/assets and a starter document, embedded in code so they travel through Git and native promotion. |
| [`ScenarioOntology.Ontology`](../workspace/ScenarioOntology.Ontology) | New-experience TMDL Site/Asset entities and their LocatedAt relationship, initially without environment-specific partitions. |
| [`BindScenario.Notebook`](../workspace/BindScenario.Notebook/notebook-content.py) | Wait for scoped SQL metadata refresh and bind the sample ontology to the current workspace's lakehouse. |
| [`Bootstrap.DeploymentPlan`](../workspace/Bootstrap.DeploymentPlan/plan.yml) | Deploy the lakehouse, run the seed notebook, deploy the ontology, then run its binding notebook. |

The generic item names are local to each project's workspaces. Preserve each `.platform` logical ID across environments. If you rename `Scenario` or `ScenarioOntology`, update notebook parameters and plan actions together. The plan uses logical IDs, while Terraform's `knowledge_lakehouse_id` and `knowledge_ontologies` inputs require physical DEV item GUIDs.

Keep notebook defaults in executable `# PARAMETERS CELL` sections. This delimiter preserves the parameter-cell role through Fabric Git; a `tags` entry in the language metadata does not. A `# PARAMETERS` heading alone is not a code-cell delimiter and can cause Fabric to import the defaults as Markdown.

The seeder uses the current runtime workspace, never a saved DEV workspace ID or default lakehouse attachment. It writes `Tables/dbo/demo_sites`, `Tables/dbo/demo_assets` and `Files/starter.txt`. Existing rows (including edited demo rows) and the existing file are retained. Incompatible table schemas/non-Delta paths and write failures stop the run; no data is silently replaced. Serialize seed runs per workspace.

## Initial Git synchronization

After the first Terraform apply, use **Connect and sync with deployment plan** in DEV and select the incoming `Bootstrap` plan. Connect to the configured GitHub branch and `/workspace` directory. Include all five starter items. Each notebook is itself a deployment group, so it exists before its post-action runs even in an empty workspace.

The first binding run modifies the live ontology definition. Review and commit that generated DEV binding and service-normalized TMDL through Fabric Git before promotion. The binder must run in each target to replace those environment-specific source details. See [seeded ontologies](../docs/ontology-knowledge.md) for the ownership, concurrency and authentication constraints.

**Committing a plan doesn't activate it.** Attach it to each initial sync, update, branch operation or pipeline deployment that needs its actions. A Git push alone doesn't synchronize Fabric or run a notebook.

Git connection initialization is intentionally outside Terraform: the pinned Fabric provider's `fabric_workspace_git` resource automatically initializes/syncs but cannot attach a plan. Do not add it alongside the native bootstrap operation.

### Automating the same operation

Use the documented [Git automation APIs](https://learn.microsoft.com/fabric/cicd/git-integration/git-automation) and [deployment-plan API extension](https://learn.microsoft.com/fabric/cicd/deployment-plan/deployment-plan-automation), not another Terraform provisioner:

1. Authenticate to Fabric with Entra. The caller needs workspace permissions, the original API scopes, and `Item.Execute.All` when attaching a plan. The bundled binder uses a user-context NotebookUtils token; service-principal automation needs an explicitly configured authentication flow in the derived project, in addition to tenant/item support. See [binding authentication](../docs/ontology-knowledge.md#included-scenario).
2. Read `terraform -chdir=infra output -json github_connect_request` and submit that body to `POST /v1/workspaces/{devWorkspaceId}/git/connect`. It contains the repository, branch, directory and credentials connection ID, not the PAT.
3. Call `POST /v1/workspaces/{devWorkspaceId}/git/initializeConnection` with `{"initializationStrategy":"PreferRemote"}`. Follow the returned required action. Initialize Connection itself does not accept a plan.
4. When an update is required, call `POST /v1/workspaces/{devWorkspaceId}/git/updateFromGit?beta=true` with the returned workspace head, the reviewed remote commit hash and the plan option below. For later updates, read current Git status first. Stop on conflicts rather than unconditionally overriding workspace changes.
5. Poll asynchronous operations to their terminal result, respecting `Retry-After`, and propagate item/action failures. A `202` response is not completion. Stop the workflow on failure; Fabric doesn't roll back earlier successful groups.

The plan option belongs inside the **existing request's `options`** object:

```json
{
  "options": {
    "deploymentPlan": {
      "logicalId": "17fca947-7a9f-4822-91ac-cd6aa8256e75",
      "referenceType": "ByLogicalId"
    }
  }
}
```

This is only the options fragment, not a full Update From Git request. Keep its required commit/head fields. The logical ID comes from [`Bootstrap.DeploymentPlan/.platform`](../workspace/Bootstrap.DeploymentPlan/.platform). Do not replace it with a physical item ID for Git updates.

A no-op Git update is not a reliable reseed trigger. Run the notebook separately when data needs bootstrapping again.

## Running only the seeder

Open `SeedScenario` and run all cells, or invoke it through the [notebook Job Scheduler APIs](https://learn.microsoft.com/fabric/data-engineering/notebook-public-api). Resolve the notebook's physical item ID in the target workspace; poll the job to completion and surface its failure reason. This path doesn't require a new commit or a deployment plan.

The parameter defaults target `Scenario` and allow only workspace names ending in `-dev` or `-test`. This is a demo-data guard, not an authorization boundary. For a deliberate exception, supply the Boolean `allow_other_workspaces=true` for that run; never a truthy string. The included plan explicitly passes `false`.

Seed code is bootstrap, not continuous data synchronization: changing an existing fixture in Git doesn't overwrite the corresponding existing row or file. Add reviewed data migrations/ingestion to your derived project when updates are needed.

## Adding ontologies, graphs and semantic models

The template supplies a complete **Site/Asset ontology example**, its seed data and target-binding action. It does not include a separate graph or Power BI semantic model. Author additional items in DEV, then commit their real Fabric-exported definitions and `.platform` files through Git. Register additional DEV ontologies with the knowledge base using `knowledge_ontologies`; see [the ontology guide](../docs/ontology-knowledge.md).

The sample relationship is `demo_assets.site_id -> demo_sites.site_id`. It can back Site/Asset ontology entities, graph nodes and located-at edges, or a semantic model counting assets by site/status.

Add each new item as a deployment group in `Bootstrap` (or an appropriately named release plan) with its real prerequisites. Use `SeedScenario` for raw Delta data, or **BindScenario** for consumers that require the sample's SQL metadata or bound ontology. Supply a separate explicit binding action for a different ontology schema. A dependency covers the whole group, including its post-actions; file order alone is not ordering. Commit the changed plan with the items it references and select those items in the operation.

| Item | Additional work beyond deploying its definition |
| --- | --- |
| Ontology (preview) | The sample's binder configures its target lakehouse. For additional ontologies, provide their own target-specific bindings; if generated from a semantic model, order them after that model. |
| Graph model/query set | Map node/edge sources to target tables and arrange loading/refresh. [API-created graph models currently require a first portal open](https://learn.microsoft.com/fabric/graph/manage-data) to initialize loading infrastructure; do not assume definition import alone makes them queryable. |
| Semantic model | Set target data-source/connection parameters and arrange refresh or Direct Lake framing as applicable. Workspace-specific SQL endpoint URLs and database IDs don't automatically rebind through Git. |

Review [cross-workspace dependency binding](https://learn.microsoft.com/fabric/cicd/cross-workspace-dependency-binding) for every reference. A plan's logical IDs identify items; they do not rewrite every dependency inside those items. Connections, credentials, workspace identities and other workspace settings are configured separately. Keep tokens and passwords out of item files and plan parameters.

Only [supported executable items](https://learn.microsoft.com/fabric/cicd/deployment-plan/deployment-plan-actions#item-types-you-can-run-as-an-action) can be plan actions: notebooks, data pipelines, Dataflow Gen2, copy jobs and user data functions. Ontologies, graphs and semantic models can be deployed as groups; they are not generic `Execute` actions. A refresh step can instead run a supported data pipeline/notebook using the target item's documented API and permissions.

An action finishes when its own run finishes, not when downstream services catch up. The seeder completes Delta writes; `BindScenario` explicitly refreshes and checks SQL metadata for **only the two sample tables**. Neither notebook loads a graph or refreshes a separate semantic model. Add bounded readiness/refresh actions for other consumers and fail on timeout; do not substitute an arbitrary sleep.

Prefer small synthetic fixtures embedded in notebook code or an authenticated data source. Notebook `Resources/builtin/` files can be [tracked by Git](https://learn.microsoft.com/fabric/data-engineering/notebook-source-control-deployment#notebooks-resources-folder-support-in-git), but deployment-pipeline/public-API support is currently limited; the starter doesn't depend on this feature.

The indexed Foundry IQ source remains scoped to the selected DEV lakehouse's **Files** area. Ontologies registered through `knowledge_ontologies` are separate live `fabricOntology` sources in the same knowledge base; they require an end-user token at retrieval time. Creating a table/ontology/graph without registration does not expose it automatically.

## Promoting through TEST and PROD

Terraform creates a native deployment pipeline with DEV and TEST assigned. Find it using `deployment_pipeline_id` and `deployment_pipeline_stage_ids`. It doesn't deploy items.

1. Synchronize and bind DEV, review/commit any generated binding and normalization changes, and confirm no uncommitted workspace changes remain. Record the reviewed commit and freeze source edits during promotion. Native pipelines copy live definitions, not a Git checkout.
2. In the deployment pipeline, select the starter items and any added consumers. For the first TEST deployment, choose the **incoming source `Bootstrap` plan** and include it in the selection; TEST doesn't yet contain a plan. Configure required target connections/settings before actions depend on them.
3. Deploy to TEST, wait for the plan/actions, then verify data, bindings and consumer readiness. TEST gets its own data and SQL endpoint binding, not DEV's contents. Target-binding differences are expected; other business-definition changes require review. Subsequent deployments may default to the target plan: explicitly choose the reviewed version.
4. After approval, promote the same reviewed business definitions from TEST to your separately provisioned PROD, rebinding to PROD's sources. Freeze TEST after validation and don't promote later edits accidentally. Provision/assign PROD and define its reviewed release plan and approval policy in the derived project first.

PROD should normally use ingestion from approved production sources, not synthetic fixtures. The bundled plan fails its seeder action outside `*-dev`/`*-test`. Define a separate production release plan that omits/replaces the demo action but retains the necessary target binding, or explicitly authorize demo seeding for a deliberate demo environment. The binding notebook itself does not insert demo data. Version and review both plans with the same release; don't silently weaken the default guard.

For automation, use Fabric's [Deploy Stage Content API with a deployment plan](https://learn.microsoft.com/fabric/cicd/deployment-plan/deployment-plan-automation#deploy-content-between-pipeline-stages): add `beta=true` and `options.deploymentPlan` with the plan's physical `itemId` and `referenceType: "ByItemId"`. Retain the normal source/target stage fields and selected items, and poll the operation. This is different from Git's logical-ID reference.

The pinned Terraform provider treats changes to the pipeline's `stages` as replacement. Review the plan when extending it for PROD; don't change Terraform-owned stage assignments only in the portal and expect Terraform to preserve that drift.

Native pipeline promotion leaves items absent from the source in place; this template does not automate orphan deletion. Git synchronization can apply reviewed item deletions, and deleting a lakehouse/workspace can destroy its data. Treat deletions as explicit changes, not cleanup. A failed deployment can leave partial changes; inspect them before rerunning. The insert-only seeder is safe to rerun after resolving the failure.
