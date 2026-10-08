resource "restful_resource" "analyzer" {
  count           = var.deploy_knowledge ? 1 : 0
  provider        = restful.content
  path            = "/contentunderstanding/analyzers/${var.analyzer_id}"
  check_existance = true
  body = {
    description        = "Structured application evidence for human review; not an eligibility decision."
    baseAnalyzerId     = "prebuilt-document"
    models             = var.analyzer_models
    processingLocation = var.processing_location
    config = {
      returnDetails                    = true
      estimateFieldSourceAndConfidence = true
      enableSegment                    = false
    }
    fieldSchema = { fields = var.analyzer_fields }
  }
  update_query = { api-version = ["2025-11-01"], allowReplace = ["true"] }
  poll_create = {
    url_locator    = "header.Operation-Location"
    status_locator = "body.status"
    status         = { success = "Succeeded", pending = ["NotStarted", "Running"] }
  }
  poll_update = {
    url_locator    = "header.Operation-Location"
    status_locator = "body.status"
    status         = { success = "Succeeded", pending = ["NotStarted", "Running"] }
  }
  depends_on = [terraform_data.gates, terraform_data.private_dependencies]
}

resource "restful_resource" "index" {
  count           = var.deploy_knowledge ? 1 : 0
  path            = "/indexes/${local.index_name}"
  check_existance = true
  body = {
    name = local.index_name
    fields = concat([
      { name = "id", type = "Edm.String", key = true, searchable = true, analyzer = "keyword" },
      { name = "parent_id", type = "Edm.String", filterable = true },
      { name = "content", type = "Edm.String", searchable = true },
      { name = "title", type = "Edm.String", searchable = true },
      { name = "page_from", type = "Edm.Int32", filterable = true },
      { name = "page_to", type = "Edm.Int32", filterable = true }
    ], [for name in ["case_id", "owner_id", "source_kind"] : { name = name, type = "Edm.String", filterable = true }])
    semantic = {
      defaultConfiguration = "evidence"
      configurations = [{
        name              = "evidence"
        prioritizedFields = { titleField = { fieldName = "title" }, prioritizedContentFields = [{ fieldName = "content" }], prioritizedKeywordsFields = [] }
      }]
    }
  }
  depends_on = [terraform_data.gates, terraform_data.private_dependencies]
}
resource "restful_resource" "data_source" {
  for_each        = var.deploy_knowledge ? { pdf = local.containers.approved, fields = local.containers["reviewed-evidence"] } : {}
  path            = "/datasources/${local.index_name}-${each.key}"
  check_existance = true
  ephemeral_body = {
    credentials = { connectionString = "ResourceId=${data.azurerm_storage_account.existing.id};" }
  }
  body = {
    name      = "${local.index_name}-${each.key}"
    type      = "azureblob"
    container = { name = each.value }
  }
  depends_on = [azurerm_role_assignment.search_storage]
}
resource "restful_resource" "skillset" {
  count           = var.deploy_knowledge ? 1 : 0
  path            = "/skillsets/${local.index_name}-cu"
  check_existance = true
  body = {
    name = "${local.index_name}-cu"
    cognitiveServices = {
      "@odata.type" = "#Microsoft.Azure.Search.AIServicesByIdentity"
      subdomainUrl  = var.content_endpoint
      identity      = null
    }
    skills = [{
      "@odata.type"      = "#Microsoft.Skills.Util.ContentUnderstandingSkill"
      name               = "document-layout"
      context            = "/document"
      extractionOptions  = ["locationMetadata"]
      chunkingProperties = { unit = "characters", maximumLength = 2000, overlapLength = 200 }
      inputs             = [{ name = "file_data", source = "/document/file_data" }]
      outputs            = [{ name = "text_sections", targetName = "sections" }]
    }]
    indexProjections = {
      selectors = [{
        targetIndexName    = restful_resource.index[0].body.name
        parentKeyFieldName = "parent_id"
        sourceContext      = "/document/sections/*"
        mappings = [
          { name = "content", source = "/document/sections/*/content" },
          { name = "page_from", source = "/document/sections/*/locationMetadata/pageNumberFrom" },
          { name = "page_to", source = "/document/sections/*/locationMetadata/pageNumberTo" },
          { name = "case_id", source = "/document/case_id" },
          { name = "owner_id", source = "/document/owner_id" },
          { name = "source_kind", source = "/document/source_kind" },
          { name = "title", source = "/document/metadata_storage_name" }
        ]
      }]
      parameters = { projectionMode = "skipIndexingParentDocuments" }
    }
  }
}
resource "restful_resource" "pdf_indexer" {
  count           = var.deploy_knowledge ? 1 : 0
  path            = "/indexers/${local.index_name}-pdf"
  check_existance = true
  body = {
    name            = "${local.index_name}-pdf"
    dataSourceName  = restful_resource.data_source["pdf"].body.name
    targetIndexName = restful_resource.index[0].body.name
    skillsetName    = restful_resource.skillset[0].body.name
    schedule        = { interval = "PT5M" }
    parameters = {
      maxFailedItems = 0, maxFailedItemsPerBatch = 0
      configuration  = { executionEnvironment = "private", allowSkillsetToReadFileData = true, dataToExtract = "allMetadata", indexedFileNameExtensions = ".pdf" }
    }
    fieldMappings       = []
    outputFieldMappings = []
  }
}
resource "restful_resource" "fields_indexer" {
  count           = var.deploy_knowledge ? 1 : 0
  path            = "/indexers/${local.index_name}-fields"
  check_existance = true
  body = {
    name            = "${local.index_name}-fields"
    dataSourceName  = restful_resource.data_source["fields"].body.name
    targetIndexName = restful_resource.index[0].body.name
    schedule        = { interval = "PT5M" }
    parameters = {
      maxFailedItems = 0, maxFailedItemsPerBatch = 0
      configuration  = { executionEnvironment = "private", parsingMode = "json", indexedFileNameExtensions = ".json" }
    }
    fieldMappings = [for name in ["id", "case_id", "owner_id", "content", "title", "page_from", "page_to", "source_kind"] :
    { sourceFieldName = name, targetFieldName = name }]
  }
}
resource "restful_resource" "source" {
  count           = var.deploy_knowledge ? 1 : 0
  path            = "/knowledgesources/${local.source_name}"
  check_existance = true
  force_new_attrs = ["name", "kind"]
  body = {
    name        = local.source_name
    kind        = "searchIndex"
    description = "Private human-reviewed application evidence. Callers must enforce case and owner filters."
    searchIndexParameters = {
      searchIndexName           = restful_resource.index[0].body.name
      semanticConfigurationName = "evidence"
      searchFields              = [{ name = "content" }]
      sourceDataFields          = [for name in ["id", "case_id", "owner_id", "content", "title", "page_from", "page_to", "source_kind"] : { name = name }]
    }
  }
}
resource "restful_resource" "base" {
  count           = var.deploy_knowledge ? 1 : 0
  path            = "/knowledgebases/${local.base_name}"
  check_existance = true
  body = {
    name                     = local.base_name
    description              = "Case-scoped application evidence; application enforces caller authorization."
    knowledgeSources         = [{ name = restful_resource.source[0].body.name }]
    outputMode               = "extractiveData"
    retrievalReasoningEffort = { kind = "minimal" }
  }
  lifecycle {
    replace_triggered_by = [restful_resource.source[0]]
  }
}
resource "azapi_resource" "connection" {
  count                     = var.deploy_knowledge ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview"
  name                      = "${var.project_name}-review"
  parent_id                 = data.azapi_resource.project.id
  schema_validation_enabled = false
  body = {
    properties = {
      category      = "RemoteTool"
      authType      = "ProjectManagedIdentity"
      target        = "${data.azurerm_search_service.existing.endpoint}/knowledgebases/${local.base_name}/mcp?api-version=2026-08-01-preview"
      audience      = "https://search.azure.com/"
      isSharedToAll = false
      metadata      = { ApiType = "Azure" }
    }
  }
  depends_on = [restful_resource.base]
}
