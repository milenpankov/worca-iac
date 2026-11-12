# Cluster add-ons, installed by Terraform so they exist before Argo CD deploys Worca. None of them
# tolerates the worker taint, so all run on the system node.

# Ingress: Traefik behind one Network Load Balancer (EKS's built-in service controller makes it).
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.chart_versions.traefik

  values = [yamlencode({
    ingressClass = { enabled = true, isDefaultClass = true }
    providers = {
      kubernetesIngress = { publishedService = { enabled = true } }
    }
    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      }
    }
  })]
}

# TLS certificates from Let's Encrypt (ClusterIssuer in the bootstrap chart).
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_versions.cert_manager

  values = [yamlencode({
    crds = { enabled = true }
  })]
}

# SSM Parameter Store -> Kubernetes Secrets. Its service account has the Pod Identity role the infra
# root made (read /worca/<env>/* only).
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_versions.external_secrets

  values = [yamlencode({
    installCRDs    = true
    serviceAccount = { create = true, name = "external-secrets" }
  })]
}

# Worker nodes from zero: a worker pod that cannot be scheduled starts a spot node; an idle worker
# node goes after 5 minutes.
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.chart_versions.cluster_autoscaler

  values = [yamlencode({
    awsRegion     = local.infra.region
    autoDiscovery = { clusterName = local.infra.cluster_name }
    image         = { tag = var.cluster_autoscaler_image_tag }
    rbac = {
      serviceAccount = { create = true, name = "cluster-autoscaler" }
    }
    extraArgs = {
      "scale-down-unneeded-time"      = "5m"
      "scale-down-delay-after-add"    = "5m"
      "skip-nodes-with-local-storage" = false # worker pods use emptyDir for /tmp
      "expander"                      = "least-waste"
      "balance-similar-node-groups"   = true
    }
  })]
}

# Argo CD: deploys Worca from git (the Application is in the bootstrap chart). No Ingress: reach
# the UI with `kubectl -n argocd port-forward svc/argocd-server 8080:443` (README).
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd

  values = [yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
  })]
}
