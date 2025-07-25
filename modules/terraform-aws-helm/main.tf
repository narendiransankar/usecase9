terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9"
    }
  }
}



# Install AWS Load Balancer Controller using HELM

# Resource: Helm Release 
resource "helm_release" "loadbalancer_controller" {
  #depends_on = [var.lbc_iam_depends_on]
  name       = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  namespace = "kube-system"

  # Value changes based on your Region (Below is for ap-south-1)
  set {
    name  = "image.repository"
    value = "public.ecr.aws/eks/aws-load-balancer-controller"
    #value = "495599733393.dkr.ecr.ap-south-1.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.lbc_iam_role_arn
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "clusterName"
    value = var.cluster_id
  }

}


# Create Namespace for grafana and prometheus
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# Helm to install and setup prometheus and grafana 
resource "helm_release" "prometheus_grafana_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.0.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  timeout    = 600

  # Retry mechanism
  max_history     = 5
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true

  values = [
    <<-EOT
    prometheus:
      enabled: true
      prometheusSpec:
        scrapeInterval: 30s
        evaluationInterval: 30s
        resources:
          requests:
            memory: 1Gi
            cpu: 500m
      additionalPodMonitors:
        - name: aws-lb-controller-monitor
          namespaceSelector:
            matchNames: ["kube-system"]
          podMetricsEndpoints:
            - port: http
              path: /metrics
          selector:
            matchLabels:
              app.kubernetes.io/name: aws-load-balancer-controller
    
    grafana:
      enabled: true
      adminPassword: "admin"
      service:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-type: "external"
          service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
          service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
        port: 80
        targetPort: 3000
      resources:
        requests:
          memory: 512Mi
          cpu: 300m
    EOT
  ]

  depends_on = [
    helm_release.loadbalancer_controller,
    kubernetes_namespace.monitoring
  ]
}
