import { runtime_approval } from '../types.bicep'
import { application_config, portal_environment } from './application.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Mandatory accepted FIPS140-3 encryption evidence, real browser identity and verified private knowledge. Not whole-app/hash/JWT certification. This emits manifests, not Kubernetes resources.')
param runtime runtime_approval
@description('Verified private endpoints, analyzer schema and existing tools-disabled agent.')
param application application_config
@description('Actual registry login server and workload identity client ID from the platform. No credentials.')
param platform { registry_login_server: string, identity_client_id: string }
@description('Approved actual AKS ingress/mesh settings. TLS secret is installed separately by an administrator, never supplied here.')
param ingress { hostname: string, private_ip: string, mesh_revision: string, namespace: string, tls_secret_name: string }
@description('Exact private endpoint CIDRs and separately approved Entra/firewall proxy /32s used by the workload. Never 0.0.0.0/0; NSG/UDR controls remain authoritative.')
param approved_https_cidrs string[]
var namespace = {
  apiVersion: 'v1'
  kind: 'Namespace'
  metadata: { name: 'review', labels: { 'istio.io/rev': ingress.mesh_revision } }
}
var service_account = {
  apiVersion: 'v1'
  kind: 'ServiceAccount'
  metadata: { name: 'review', namespace: 'review', annotations: { 'azure.workload.identity/client-id': platform.identity_client_id } }
}
var deployment = {
  apiVersion: 'apps/v1'
  kind: 'Deployment'
  metadata: { name: 'review', namespace: 'review' }
  spec: {
    replicas: 2
    selector: { matchLabels: { app: 'review' } }
    template: {
      metadata: { labels: { app: 'review', 'azure.workload.identity/use': 'true' } }
      spec: {
        serviceAccountName: 'review'
        nodeSelector: { workload: 'review', compliance: 'fips' }
        tolerations: [{ key: 'workload', operator: 'Equal', value: 'review', effect: 'NoSchedule' }]
        securityContext: { runAsNonRoot: true, runAsUser: 1654, fsGroup: 1654, seccompProfile: { type: 'RuntimeDefault' } }
        containers: [{
          name: 'review'
          image: '${platform.registry_login_server}/review-portal@${runtime.image_algorithm}:${runtime.image_hash}'
          ports: [{ containerPort: 8080 }]
          env: portal_environment(project_name, runtime, application, platform.identity_client_id)
          securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ['ALL'] } }
          resources: { requests: { cpu: '250m', memory: '512Mi' }, limits: { cpu: '1', memory: '2Gi' } }
          livenessProbe: { httpGet: { path: '/health/live', port: 8080 }, initialDelaySeconds: 10 }
          readinessProbe: { httpGet: { path: '/health/ready', port: 8080 }, initialDelaySeconds: 10 }
          volumeMounts: [{ name: 'tmp', mountPath: '/tmp' }]
        }]
        volumes: [{ name: 'tmp', emptyDir: {} }]
      }
    }
  }
}
var service = {
  apiVersion: 'v1'
  kind: 'Service'
  metadata: { name: 'review', namespace: 'review' }
  spec: { selector: { app: 'review' }, type: 'ClusterIP', ports: [{ port: 80, targetPort: 8080 }] }
}
var peer = {
  apiVersion: 'security.istio.io/v1'
  kind: 'PeerAuthentication'
  metadata: { name: 'strict', namespace: 'review' }
  spec: { mtls: { mode: 'STRICT' } }
}
var gateway = {
  apiVersion: 'networking.istio.io/v1'
  kind: 'Gateway'
  metadata: { name: 'review', namespace: 'review' }
  spec: {
    selector: { istio: 'aks-istio-ingressgateway-internal' }
    servers: [{
      port: { number: 443, name: 'https', protocol: 'HTTPS' }
      hosts: [ingress.hostname]
      tls: { mode: 'SIMPLE', credentialName: ingress.tls_secret_name, minProtocolVersion: 'TLSV1_2' }
    }]
  }
}
var route = {
  apiVersion: 'networking.istio.io/v1'
  kind: 'VirtualService'
  metadata: { name: 'review', namespace: 'review' }
  spec: { hosts: [ingress.hostname], gateways: ['review'], http: [{ route: [{ destination: { host: 'review.review.svc.cluster.local', port: { number: 80 } } }], timeout: '120s' }] }
}
var policy = {
  apiVersion: 'networking.k8s.io/v1'
  kind: 'NetworkPolicy'
  metadata: { name: 'review', namespace: 'review' }
  spec: {
    podSelector: { matchLabels: { app: 'review' } }
    policyTypes: ['Ingress', 'Egress']
    ingress: [{ from: [{ namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': ingress.namespace } } }], ports: [{ port: 8080, protocol: 'TCP' }] }]
    egress: [
      { to: [{ namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'kube-system' } } }], ports: [{ port: 53, protocol: 'UDP' }, { port: 53, protocol: 'TCP' }] }
      { to: map(approved_https_cidrs, cidr => { ipBlock: { cidr: cidr } }), ports: [{ port: 443, protocol: 'TCP' }] }
      { to: [{ namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'aks-istio-system' } } }], ports: [{ port: 15012, protocol: 'TCP' }] }
    ]
  }
}
output manifests array = [namespace, service_account, deployment, service, peer, gateway, route, policy]
output ingress_service_annotation object = { 'service.beta.kubernetes.io/azure-load-balancer-ipv4': ingress.private_ip }
