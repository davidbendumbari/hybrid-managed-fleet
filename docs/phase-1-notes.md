# Phase 1: Cloud site with Terraform

**Region:** eu-north-1 (Stockholm), chosen as the cheapest EU region.
**Result:** 8 resources built and destroyed on demand.
**Time taken:** 7 minutes from empty repo to working SSH login.


## What I built
VPC, subnet, internet gateway, route table, SSH-restricted security group, key pair, one t4g.micro Ubuntu server.

## Decisions
- ARM instance for lower price
- Firewall allows SSH from one IP only
- Destroy after every session to protect a $5 budget

## Problems and fixes
- forgot to terraform destroy for about 30mins. so created automation to terraform destroy at a specific time in the day to always save costs

## Evidence
See the docs/evidence folder.
