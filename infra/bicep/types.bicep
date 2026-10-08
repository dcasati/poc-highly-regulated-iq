@export()
type us_region = 'westus' | 'westus2' | 'westus3' | 'westcentralus' | 'centralus' | 'northcentralus' | 'southcentralus' | 'eastus' | 'eastus2'

@export()
@sealed()
type reference = {
  @minLength(1)
  resource_group_name: string
  @minLength(1)
  name: string
}

@export()
@sealed()
type approval = {
  approved: true
  @minLength(1)
  evidence_reference: string
}

@export()
@sealed()
type model = {
  @minLength(1)
  name: string
  @minLength(1)
  version: string
  sku: 'DataZoneStandard' | 'Standard'
  @minValue(1)
  capacity: int
}

@export()
@sealed()
type browser_identity = {
  @minLength(36)
  @maxLength(36)
  tenant_id: string
  @minLength(36)
  @maxLength(36)
  spa_client_id: string
  @minLength(36)
  @maxLength(36)
  api_client_id: string
}

@export()
@sealed()
type runtime_approval = {
  approved: true
  @minLength(1)
  platform_evidence: string
  @minLength(1)
  image_evidence: string
  @minLength(1)
  transport_evidence: string
  knowledge: approval
  identity: browser_identity
  image_algorithm: 'sha256'
  @minLength(64)
  @maxLength(64)
  image_hash: string
}
