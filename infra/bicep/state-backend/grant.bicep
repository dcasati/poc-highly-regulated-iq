import { approval } from '../types.bicep'
@description('Previously created PoC private/keyless state account in this resource group.')
param storage_account_name string
@description('Previously created state container; never application/native agent containers.')
param container_name string = 'tfstate'
@description('Verified deployment principal GUID.')
param deployment_principal_id string
@description('Verified deployment principal type.')
@allowed(['User', 'ServicePrincipal'])
param deployment_principal_type string
@description('Separately approved container-scoped state access, not state migration permission.')
param state_access approval
module grant '../modules/storage-bindings.bicep' = {
  name: 'state-container-grant'
  params: {
    account_name: storage_account_name
    create_containers: false
    bindings: [{ container_name: container_name, principal_id: deployment_principal_id, principal_type: deployment_principal_type, role_id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }]
  }
}
output access_verification_reference string = state_access.evidence_reference
