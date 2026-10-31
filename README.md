# pilot-infra

Deploy `pilot-test-pg` (RDS PostgreSQL 17.5, db.t4g.micro, 20 GiB gp2, encrypted, Database Insights Standard) whenever you want, and delete it whenever you want.

It uses the account's **default VPC** and the default `aws/rds` KMS key, so there is no NAT gateway, no VPC endpoints, and no customer KMS key. The only hourly charges are the database and its public IPv4 address.

## One-time setup

1. Create a GitHub repo (for example `rravala/pilot-infra`) and push this folder to it.
2. In AWS CloudShell (or any shell with admin credentials for your account):
   ```
   bash bootstrap/bootstrap.sh RRavala/pilot-infra RRavala/flyway-postgres-demo
   ```
   List every repo that should be able to use the role (the second one deploys database changes with Flyway). Use the exact capitalization GitHub shows. This creates the state bucket, the GitHub OIDC provider, and a deploy role. It is safe to re-run.
3. Add the repo variables the script prints (`AWS_ROLE_ARN`, `TF_STATE_BUCKET`, optionally `ALLOWED_CIDR` and `NIGHTLY_DESTROY`).
4. Create two environments in GitHub (Settings > Environments): `deploy` and `destroy`. Required reviewers on `destroy` are optional. Note that on private repos, environment protection rules need a paid GitHub plan. The `confirm` input on destroy works either way.

## Use it

GitHub > Actions > **infra** > Run workflow:

| action | what it does |
|---|---|
| `plan` | shows what would change, changes nothing |
| `apply` | creates or updates everything (about 5 to 10 minutes) |
| `destroy` | deletes everything; set `confirm` to `pilot-test-pg` |

Put your public IP in `allowed_cidr` (for example `203.0.113.7/32`). Only that address can reach port 5432. If your IP changes, run `apply` again.

When `apply` finishes, the run summary shows the endpoint and the Secrets Manager secret that holds the master password.

### Or from your laptop

```
cd terraform
terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="key=pilot-test-pg/terraform.tfstate" \
  -backend-config="region=us-east-1"
terraform apply  -var="allowed_cidr=203.0.113.7/32"
terraform destroy -var="allowed_cidr=203.0.113.7/32"
```

## Data between deploys

- **Default: nothing is kept.** Destroy skips the final snapshot. Recreate the schema with Flyway and reload data with DMS or SCT.
- **Keep the data:** run destroy with `-var="keep_data_on_destroy=true"`. This leaves a snapshot named `pilot-test-pg-final`. Delete the old snapshot before the next keep-data destroy, because the name is fixed.
- **Restore on deploy:** `-var="snapshot_identifier=pilot-test-pg-final"`. Credentials come from the snapshot, so no new secret is created.

## Cost guardrail

Set the repo variable `NIGHTLY_DESTROY=true` and the workflow destroys everything at 1am US Eastern every night. Remove the variable to turn it off. Scheduled destroys skip the confirm step on purpose.

## Replacing the instance you have now

The current `pilot-test-pg` was created by hand, so Terraform doesn't know about it, and an `apply` would fail on the duplicate identifier. Either:

1. Delete it in the console (take a final snapshot if you want the data), then run `apply`; or
2. Import it: `terraform import aws_db_instance.pilot pilot-test-pg`, then run `plan` and review the diff.

## Not managed here

The DMS replication instance, SCT configuration, and your local SQL Server are separate. DMS can be added as a second Terraform file later.
