# Cluster add-ons, installed by Terraform so they exist before Argo CD deploys Worca. None of them
# tolerates the worker taint, so all run on the system node.

# One ALB for every Ingress in the `worca` IngressGroup (Worca and Argo CD), TLS with the ACM
# certificate (acm.tf), targets are pods by IP. Group-wide settings must match in every member.
locals {
  alb_annotations = {
    "alb.ingress.kubernetes.io/group.name"      = "worca"
    "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/listen-ports"    = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
    "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.this.arn
    "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    # Worca's WebSockets stay open while a page is: the default 60 s idle timeout would cut them.
    "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=3600"
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions.aws_load_balancer_controller

  values = [yamlencode({
    clusterName  = local.infra.cluster_name
    region       = local.infra.region
    vpcId        = local.infra.vpc_id
    replicaCount = 1
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller" # its Pod Identity association (infra/iam.tf)
    }
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

  # The controller's webhook must answer before other Services are created, and it must still run
  # when Ingresses are deleted on destroy (their finalizer).
  depends_on = [helm_release.aws_load_balancer_controller]
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

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Argo CD: deploys Worca from git (the Application is in the bootstrap chart). Its UI is on the
# same ALB at argocd_host (the Ingress below), with Argo CD's own login: the `admin` user and the
# password it generates at install (output argocd_admin_password_command).
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd

  values = [yamlencode({
    global        = { domain = var.argocd_host }
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      params = { "server.insecure" = true } # TLS ends at the ALB
    }
  })]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Argo CD's Ingress, made here rather than by its chart so Terraform waits for the ALB it brings
# up (the `worca` IngressGroup's) and knows its host name (dns.tf). The certificate must be issued
# first: the controller cannot make the HTTPS listener with a pending one.
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
    annotations = merge(local.alb_annotations, {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
    })
  }

  spec {
    ingress_class_name = "alb"
    rule {
      host = var.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }

  # Without route53_zone the certificate waits for your DNS records (acm_validation_records), and
  # so does this, up to its timeout: add them, then apply again.
  wait_for_load_balancer = true
  timeouts {
    create = "15m"
  }

  depends_on = [aws_acm_certificate_validation.this]
}
