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
type egress_rule = {
  @description('Reviewed IPv4 CIDR. Build rules may instead use a reviewed Azure service tag (region-scoped AzureKeyVault.<Region>, Storage.<Region>, EventHub.<Region>, MicrosoftContainerRegistry.<Region>; global AzureActiveDirectory, AzureMonitor, AzureFrontDoor.FirstParty); never Internet or AzureCloud.')
  @minLength(1)
  destination_cidr: string
  @minValue(1)
  @maxValue(65535)
  port: int
}

@export()
@sealed()
type platform_egress = {
  @minLength(1)
  nat_gateway_id: string
  runtime: egress_rule[]
  build: egress_rule[]
  verification: approval
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
@discriminator('attestation_mode')
type runtime_approval = {
  attestation_mode: 'evidence_gated'
  encryption_standard: 'FIPS140-3'
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
} | {
  attestation_mode: 'synthetic_poc_attestation_deferred'
  encryption_standard: 'FIPS140-3'
  approved: false
  platform_evidence: ''
  image_evidence: ''
  transport_evidence: ''
  knowledge: approval
  identity: browser_identity
  image_algorithm: 'sha256'
  @minLength(64)
  @maxLength(64)
  image_hash: string
}
