import { runtime_approval } from '../types.bicep'
@export()
@sealed()
type application_config = {
  @minLength(1)
  blob_endpoint: string
  @minLength(1)
  content_endpoint: string
  @minLength(1)
  search_endpoint: string
  @minLength(1)
  openai_endpoint: string
  @minLength(1)
  chat_deployment: string
  @minLength(1)
  analyzer_id: string
  @minLength(1)
  field_names: string[]
  processing_location: 'geography' | 'dataZone'
  confidence_threshold: string
}

@export()
func portal_environment(project_name string, runtime runtime_approval, application application_config, identity_client_id string) object[] => concat([
  { name: 'Portal__TenantId', value: runtime.identity.tenant_id }
  { name: 'Portal__ClientId', value: runtime.identity.spa_client_id }
  { name: 'Portal__ApiAudience', value: runtime.identity.api_client_id }
  { name: 'Portal__ApiScope', value: 'api://${runtime.identity.api_client_id}/access_as_user' }
  { name: 'Portal__BlobEndpoint', value: application.blob_endpoint }
  { name: 'Portal__ContentEndpoint', value: application.content_endpoint }
  { name: 'Portal__SearchEndpoint', value: application.search_endpoint }
  { name: 'Portal__OpenAIEndpoint', value: application.openai_endpoint }
  { name: 'Portal__ChatDeployment', value: application.chat_deployment }
  { name: 'Portal__AnalyzerId', value: application.analyzer_id }
  { name: 'Portal__KnowledgeBase', value: '${project_name}-review' }
  { name: 'Portal__KnowledgeSource', value: '${project_name}-review-source' }
  { name: 'Portal__OriginalContainer', value: '${project_name}-originals' }
  { name: 'Portal__StateContainer', value: '${project_name}-review-state' }
  { name: 'Portal__ApprovedContainer', value: '${project_name}-approved' }
  { name: 'Portal__EvidenceContainer', value: '${project_name}-reviewed-evidence' }
  { name: 'Portal__ProcessingLocation', value: application.processing_location }
  { name: 'Portal__ConfidenceThreshold', value: application.confidence_threshold }
  { name: 'Portal__ManagedIdentityClientId', value: identity_client_id }
], map(application.field_names, (field, i) => { name: 'Portal__FieldNames__${i}', value: field }))
