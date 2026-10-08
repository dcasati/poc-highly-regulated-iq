locals {
  deploy_kubernetes = var.hosting == "aks" && var.provision_hosting && var.deploy_runtime
}
resource "kubernetes_annotations" "ingress" {
  count       = local.deploy_kubernetes ? 1 : 0
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "aks-istio-ingressgateway-internal"
    namespace = var.aks.ingress_namespace
  }
  annotations = {
    "service.beta.kubernetes.io/azure-load-balancer-ipv4" = var.aks.private_ip
  }
  depends_on = [azurerm_role_assignment.cluster_deployer]
}
resource "kubernetes_namespace_v1" "app" {
  count = local.deploy_kubernetes ? 1 : 0
  metadata {
    name = "review"
    labels = {
      "istio.io/rev" = var.aks.mesh_revision
    }
  }
  depends_on = [azurerm_role_assignment.cluster_deployer]
}
resource "kubernetes_service_account_v1" "app" {
  count = local.deploy_kubernetes ? 1 : 0
  metadata {
    name      = "review"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.app.client_id
    }
  }
}
resource "kubernetes_deployment_v1" "app" {
  count = local.deploy_kubernetes ? 1 : 0
  metadata {
    name      = "review"
    namespace = "review"
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "review" } }
    template {
      metadata {
        labels = { app = "review", "azure.workload.identity/use" = "true" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.app[0].metadata[0].name
        node_selector        = { workload = "review", compliance = "fips" }
        toleration {
          key      = "workload"
          operator = "Equal"
          value    = "review"
          effect   = "NoSchedule"
        }
        security_context {
          run_as_non_root = true
          run_as_user     = 1654
          fs_group        = 1654
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name  = "review"
          image = local.image
          port { container_port = 8080 }
          dynamic "env" {
            for_each = local.portal_env
            content {
              name  = env.key
              value = env.value
            }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "2Gi" }
          }
          liveness_probe {
            http_get {
              path = "/health/live"
              port = 8080
            }
            initial_delay_seconds = 10
          }
          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 8080
            }
            initial_delay_seconds = 10
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
  depends_on = [
    terraform_data.gates, azurerm_kubernetes_cluster_node_pool.app, azurerm_role_assignment.cluster_pull,
    azurerm_role_assignment.app_storage, azurerm_role_assignment.app_project,
    azurerm_role_assignment.app_search, azurerm_role_assignment.app_content,
    azurerm_federated_identity_credential.app
  ]
}
resource "kubernetes_service_v1" "app" {
  count = local.deploy_kubernetes ? 1 : 0
  metadata {
    name      = "review"
    namespace = "review"
  }
  spec {
    selector = { app = "review" }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
  depends_on = [kubernetes_namespace_v1.app]
}
resource "kubernetes_manifest" "peer_authentication" {
  count = local.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "security.istio.io/v1"
    kind       = "PeerAuthentication"
    metadata   = { name = "strict", namespace = "review" }
    spec       = { mtls = { mode = "STRICT" } }
  }
  depends_on = [kubernetes_namespace_v1.app]
}
resource "kubernetes_manifest" "gateway" {
  count = local.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.istio.io/v1"
    kind       = "Gateway"
    metadata   = { name = "review", namespace = "review" }
    spec = {
      selector = { istio = "aks-istio-ingressgateway-internal" }
      servers = [{
        port  = { number = 443, name = "https", protocol = "HTTPS" }
        hosts = [var.aks.hostname]
        tls   = { mode = "SIMPLE", credentialName = var.aks.tls_secret_name, minProtocolVersion = "TLSV1_2" }
      }]
    }
  }
  depends_on = [kubernetes_namespace_v1.app]
}
resource "kubernetes_manifest" "virtual_service" {
  count = local.deploy_kubernetes ? 1 : 0
  manifest = {
    apiVersion = "networking.istio.io/v1"
    kind       = "VirtualService"
    metadata   = { name = "review", namespace = "review" }
    spec = {
      hosts    = [var.aks.hostname]
      gateways = ["review"]
      http = [{
        route   = [{ destination = { host = "review.review.svc.cluster.local", port = { number = 80 } } }]
        timeout = "120s"
      }]
    }
  }
  depends_on = [kubernetes_manifest.gateway, kubernetes_service_v1.app]
}
resource "kubernetes_network_policy_v1" "app" {
  count = local.deploy_kubernetes ? 1 : 0
  metadata {
    name      = "review"
    namespace = "review"
  }
  spec {
    pod_selector { match_labels = { app = "review" } }
    policy_types = ["Ingress", "Egress"]
    ingress {
      from {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = var.aks.ingress_namespace } }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "kube-system" } }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "aks-istio-system" } }
      }
      ports {
        port     = "15012"
        protocol = "TCP"
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.app]
}
