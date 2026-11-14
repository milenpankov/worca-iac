terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {
    key_vault {
      # A destroyed vault is purged at once, so its name can be used again.
      purge_soft_delete_on_destroy = true
    }
  }
}
