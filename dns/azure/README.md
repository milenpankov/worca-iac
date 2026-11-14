# Azure DNS zone for a delegated subdomain

One zone, `<zone_name>.<domain>`, for a domain whose DNS is hosted elsewhere (DigitalOcean, the
registrar, ...). [azure-aks/platform](../../azure-aks/platform) puts the hosts' records in it, and
cert-manager its Let's Encrypt DNS-01 challenges. The Azure counterpart of [dns/route53](../route53).

Kept apart from the deployment on purpose: a new zone gets new name servers, so a zone created and
destroyed with the deployment would need the delegation changed each time. ~$0.50 a month.

## Set up once

```bash
az login
cp terraform.tfvars.example terraform.tfvars   # subscription_id, domain, zone_name
terraform init
terraform apply
terraform output -raw delegation
```

At the parent domain's DNS provider, add the four NS records `delegation` prints (name
`zone_name`, e.g. `azure`). Check: `dig +short NS azure.example.com`.

## Remove

Destroy the deployment first, then `terraform destroy` here, and delete the NS records at the
parent's DNS provider.
