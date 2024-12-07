terraform {
  required_version = ">= 1.7.0"

  required_providers {
    flux = {
      source  = "fluxcd/flux"
      version = "= 1.3.0"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.1"
    }
  }
}

# ==========================================
# Initialise a Github project
# ==========================================

resource "github_repository" "this" {
  name        = var.github_repository
  description = var.github_repository
  visibility  = "private"
  auto_init   = true # This is extremely important as flux_bootstrap_git will not work without a repository that has been initialised
}

# ==========================================
# Bootstrap KinD cluster
# ==========================================

resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository.this]

  components_extra = [
    "image-reflector-controller",
    "image-automation-controller"
  ]
  embedded_manifests     = true
  kustomization_override = file("${path.root}/resources/flux-kustomization-patch.yaml")
  path               = "clusters/herbgoto"
}