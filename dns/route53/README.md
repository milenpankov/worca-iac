# Route 53 zone for a delegated subdomain

One hosted zone, `<zone_name>.<domain>`, for a domain whose DNS is hosted elsewhere (DigitalOcean,
the registrar, ...). The deployments put their records in it: the ACM validation records and the
aliases to their load balancer ([aws-eks/platform](../../aws-eks/platform) and [aws-ecs](../../aws-ecs): `route53_zone`).

It is separate from the deployments on purpose. Every new hosted zone gets new name servers, so a
zone created and destroyed with the deployment would need the delegation changed each time. Kept,
it costs $0.50 a month; the deployments come and go and their records with them.

## Set up once

```bash
cp terraform.tfvars.example terraform.tfvars   # domain, zone_name
terraform init
terraform apply
terraform output -raw delegation
```

At the parent domain's DNS provider, add the four NS records `delegation` prints (name
`zone_name`, e.g. `aws`). Check:

```bash
dig +short NS aws.example.com            # the four awsdns name servers
```

## Remove

Destroy the deployments that use it first, then `terraform destroy` here (`force_destroy`
removes leftover records), and delete the NS records at the parent's DNS provider. The zone is
tagged `Project = <name>` (default `worca-poc`).
