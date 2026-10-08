import { approval, reference } from '../types.bicep'
@description('Generic PoC branding. Outputs are reviewable data-plane request bodies, NOT ARM-managed Search/CU resources.')
param project_name string
@description('Selected existing application storage reference.')
param storage reference
@description('Verified private Content Understanding endpoint.')
param content_endpoint string
@description('Approved existing model names whose supported CU defaults have already been verified.')
param analyzer_models { completion: string, embedding: string }
@description('Approved US CU boundary; independent native layout residency review is still required.')
@allowed(['geography', 'dataZone'])
param processing_location string = 'geography'
@description('Scenario-owned custom analyzer ID.')
param analyzer_id string = 'application-review'
@description('Every field requires explicit human confirmation before publication. Extend this scalar schema under domain review.')
param analyzer_fields {
  *: {
    type: 'string' | 'boolean' | 'number' | 'integer' | 'date'
    method: 'extract'
    @minLength(1)
    description: string
  }
} = {
  ApplicantName: { type: 'string', method: 'extract', description: 'Applicant or organization name exactly as written.' }
  ReferenceNumber: { type: 'string', method: 'extract', description: 'Application reference number, if present.' }
  RequestedCategory: { type: 'string', method: 'extract', description: 'Requested application category exactly as written.' }
  Description: { type: 'string', method: 'extract', description: 'Applicant description or purpose; do not infer eligibility.' }
  SupportingDocuments: { type: 'string', method: 'extract', description: 'Supporting documents explicitly identified in this package.' }
  SignaturePresent: { type: 'boolean', method: 'extract', description: 'Whether a signature is visibly present, not validity or authority.' }
}
@description('Verified approved Blob/processing/billing links, supported CU defaults and separate native-skill processing boundaries. Not indexer readiness.')
param private_dependencies approval
var index_name = '${project_name}-evidence'
var source_name = '${project_name}-review-source'
var base_name = '${project_name}-review'
var metadata_fields = ['case_id', 'owner_id', 'source_kind']
var source_fields = ['id', 'case_id', 'owner_id', 'content', 'title', 'page_from', 'page_to', 'source_kind']
var index = {
  name: index_name
  fields: concat([
    { name: 'id', type: 'Edm.String', key: true, searchable: true, analyzer: 'keyword' }
    { name: 'parent_id', type: 'Edm.String', filterable: true }
    { name: 'content', type: 'Edm.String', searchable: true }
    { name: 'title', type: 'Edm.String', searchable: true }
    { name: 'page_from', type: 'Edm.Int32', filterable: true }
    { name: 'page_to', type: 'Edm.Int32', filterable: true }
  ], map(metadata_fields, name => { name: name, type: 'Edm.String', filterable: true }))
  semantic: { defaultConfiguration: 'evidence', configurations: [{ name: 'evidence', prioritizedFields: { titleField: { fieldName: 'title' }, prioritizedContentFields: [{ fieldName: 'content' }], prioritizedKeywordsFields: [] } }] }
}
var data_sources = map(['pdf', 'fields'], kind => {
  name: '${index_name}-${kind}'
  type: 'azureblob'
  credentials: { connectionString: 'ResourceId=${resourceId(storage.resource_group_name, 'Microsoft.Storage/storageAccounts', storage.name)};' }
  container: { name: kind == 'pdf' ? '${project_name}-approved' : '${project_name}-reviewed-evidence' }
})
var skillset = {
  name: '${index_name}-cu'
  cognitiveServices: { '@odata.type': '#Microsoft.Azure.Search.AIServicesByIdentity', subdomainUrl: content_endpoint, identity: null }
  skills: [{
    '@odata.type': '#Microsoft.Skills.Util.ContentUnderstandingSkill'
    name: 'document-layout'
    context: '/document'
    extractionOptions: ['locationMetadata']
    chunkingProperties: { unit: 'characters', maximumLength: 2000, overlapLength: 200 }
    inputs: [{ name: 'file_data', source: '/document/file_data' }]
    outputs: [{ name: 'text_sections', targetName: 'sections' }]
  }]
  indexProjections: {
    selectors: [{
      targetIndexName: index_name
      parentKeyFieldName: 'parent_id'
      sourceContext: '/document/sections/*'
      mappings: [
        { name: 'content', source: '/document/sections/*/content' }
        { name: 'page_from', source: '/document/sections/*/locationMetadata/pageNumberFrom' }
        { name: 'page_to', source: '/document/sections/*/locationMetadata/pageNumberTo' }
        { name: 'case_id', source: '/document/case_id' }
        { name: 'owner_id', source: '/document/owner_id' }
        { name: 'source_kind', source: '/document/source_kind' }
        { name: 'title', source: '/document/metadata_storage_name' }
      ]
    }]
    parameters: { projectionMode: 'skipIndexingParentDocuments' }
  }
}
var pdf_indexer = {
  name: '${index_name}-pdf'
  dataSourceName: '${index_name}-pdf'
  targetIndexName: index_name
  skillsetName: '${index_name}-cu'
  schedule: { interval: 'PT5M' }
  parameters: { maxFailedItems: 0, maxFailedItemsPerBatch: 0, configuration: { executionEnvironment: 'private', allowSkillsetToReadFileData: true, dataToExtract: 'allMetadata', indexedFileNameExtensions: '.pdf' } }
  fieldMappings: []
  outputFieldMappings: []
}
var fields_indexer = {
  name: '${index_name}-fields'
  dataSourceName: '${index_name}-fields'
  targetIndexName: index_name
  schedule: { interval: 'PT5M' }
  parameters: { maxFailedItems: 0, maxFailedItemsPerBatch: 0, configuration: { executionEnvironment: 'private', parsingMode: 'json', indexedFileNameExtensions: '.json' } }
  fieldMappings: map(source_fields, name => { sourceFieldName: name, targetFieldName: name })
}
var source = {
  name: source_name
  kind: 'searchIndex'
  description: 'Private human-reviewed evidence; callers enforce case and owner filters.'
  searchIndexParameters: { searchIndexName: index_name, semanticConfigurationName: 'evidence', searchFields: [{ name: 'content' }], sourceDataFields: map(source_fields, name => { name: name }) }
}
var base = {
  name: base_name
  description: 'Case-scoped evidence; application enforces caller authorization.'
  knowledgeSources: [{ name: source_name }]
  outputMode: 'extractiveData'
  retrievalReasoningEffort: { kind: 'minimal' }
}
output analyzer_request object = {
  method: 'PUT'
  path: '/contentunderstanding/analyzers/${analyzer_id}?api-version=2025-11-01'
  body: {
    description: 'Structured evidence for human review, not an eligibility decision.'
    baseAnalyzerId: 'prebuilt-document'
    models: analyzer_models
    processingLocation: processing_location
    config: { returnDetails: true, estimateFieldSourceAndConfidence: true, enableSegment: false }
    fieldSchema: { fields: analyzer_fields }
  }
}
output search_requests array = [
  { method: 'PUT', path: '/indexes/${index_name}', body: index }
  { method: 'PUT', path: '/datasources/${index_name}-pdf', body: data_sources[0] }
  { method: 'PUT', path: '/datasources/${index_name}-fields', body: data_sources[1] }
  { method: 'PUT', path: '/skillsets/${index_name}-cu', body: skillset }
  { method: 'PUT', path: '/indexers/${index_name}-pdf', body: pdf_indexer }
  { method: 'PUT', path: '/indexers/${index_name}-fields', body: fields_indexer }
  { method: 'PUT', path: '/knowledgesources/${source_name}', body: source }
  { method: 'PUT', path: '/knowledgebases/${base_name}', body: base }
]
output search_api_version string = '2026-08-01-preview'
output dependency_verification string = private_dependencies.evidence_reference
