# enviable-infra

Terraform-managed AWS infrastructure (region **eu-north-1**) for the **enviable-system**
NestJS backend, plus its CI/CD. The **enviable-web** Next.js frontend is hosted on Vercel
and is out of scope here (it only needs one env var — see step 7).

```
Browser → portal.enviabletricycle.com (Vercel, Next.js)
            → /api/* proxied server-side →
          api.enviabletricycle.com (AWS EC2: Caddy TLS → NestJS → Redis)
                                      ├─ RDS PostgreSQL 16 (private)
                                      └─ S3 bucket (PDFs/uploads)
```

What Terraform provisions: a small VPC (1 public subnet for EC2, 2 private for RDS, **no NAT**),
a t3.micro EC2 instance (Docker Compose: Caddy + backend + Redis, 2 GB swap), RDS db.t3.micro
(single-AZ, encrypted, private), an S3 bucket, an ECR repo, SSM Parameter Store secrets/config,
the EC2 instance role, and the GitHub **OIDC** provider + deploy roles. TLS is **Caddy on the box**
(Let's Encrypt) — no ALB, no Route 53 zone.

Design + plan: `docs/superpowers/specs/2026-06-18-enviable-infra-aws-design.md`,
`docs/superpowers/plans/2026-06-18-enviable-infra-aws.md`.

## Prerequisites

- **Terraform >= 1.6.0** (the root pins this; module dirs validate on older versions but the root
  apply requires 1.6+).
- AWS credentials for **eu-north-1** with permissions to create the resources above.
- The `enviable-system` and `enviable-web` repos on GitHub.

## Provisioning order (one-time)

Remote state lives in S3 with a DynamoDB lock, but the state bucket itself must exist first —
hence the two-step bootstrap.

1. **Bootstrap the state backend** (separate root, local state):
   ```bash
   cd bootstrap
   terraform init
   terraform apply        # creates enviable-tfstate-<account_id> + enviable-tf-lock
   ```
   Note the `state_bucket` output and your 12-digit AWS account id.

2. **Point the main stack's backend at that bucket.** Edit `backend.tf`, replacing
   `enviable-tfstate-REPLACE_WITH_ACCOUNT_ID` with the real bucket name — or pass it at init:
   ```bash
   terraform init -backend-config="bucket=enviable-tfstate-<account_id>"
   ```

3. **Create `terraform.tfvars`** from the example and fill the required values
   (`terraform.tfvars` is gitignored — it holds `default_initial_password`):
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # set: caddy_email, github_org, default_initial_password
   ```

4. **Apply the main stack:**
   ```bash
   terraform init        # if not already done in step 2
   terraform apply -var-file=terraform.tfvars
   ```
   RDS takes several minutes. Record the outputs (`terraform output`).

## Wire CI/CD (GitHub Actions variables)

CI uses GitHub **OIDC** — no static AWS keys. Set these **repo variables** (Settings → Secrets and
variables → Actions → **Variables**) from the Terraform outputs:

**enviable-system** repo:

| Variable | Value (from `terraform output`) |
|---|---|
| `AWS_REGION` | `eu-north-1` |
| `AWS_DEPLOY_ROLE_ARN` | `backend_deploy_role_arn` |
| `ECR_REPOSITORY_URL` | `ecr_repository_url` |
| `S3_BUCKET` | `s3_bucket` |
| `SSM_PREFIX` | `ssm_prefix` (`/enviable/prod`) |
| `INSTANCE_ID` | `instance_id` |

**enviable-infra** repo:

| Variable | Value |
|---|---|
| `AWS_INFRA_ROLE_ARN` | `infra_role_arn` |

- Create a GitHub **`production` environment** (with required reviewers) so the infra
  `terraform apply` step is gated.
- **CI tfvars/secret strategy (open decision):** `terraform.yml` runs `-var-file=terraform.tfvars`,
  but that file is gitignored. Before relying on the infra apply-on-merge workflow, either
  (a) commit a **non-secret** `terraform.tfvars` and supply the password via a
  `TF_VAR_default_initial_password` GitHub **secret** (drop `-var-file` if all vars come from
  `TF_VAR_*`), or (b) keep `terraform apply` local and use the workflow for `plan` only.

## DNS records to add (at your current DNS provider)

The zone is **not** migrated to Route 53 — add only these two subdomain records. They do not
affect your apex website, `MX`, or DKIM records.

| Name | Type | Value |
|---|---|---|
| `api` | A | `elastic_ip` (Terraform output) |
| `portal` | CNAME | the target Vercel shows in the project's Domains settings |

Caddy obtains the Let's Encrypt cert automatically once `api.enviabletricycle.com` resolves to the
Elastic IP and ports 80/443 are reachable.

## First deploy (cutover)

1. After `terraform apply` and setting the GitHub variables, trigger the **enviable-system**
   `deploy-backend` workflow (push to `main` or run it via `workflow_dispatch`). This pushes the
   first image to ECR, records the tag in SSM, uploads `deploy/` to S3, and runs the on-box
   `docker compose up`. Confirm the workflow's final step reports `Status: Success`.
2. Add the `api` A record (step above) and wait for it to resolve
   (`dig +short api.enviabletricycle.com`). Caddy then issues the TLS cert.
3. Verify: `curl -I https://api.enviabletricycle.com/api/<a known route>` — expect HTTPS with a
   valid cert and a backend response (not a Caddy 502).
4. In **Vercel**: set `BACKEND_API_URL=https://api.enviabletricycle.com`, point the `portal`
   CNAME at Vercel, redeploy the frontend, and confirm login works end-to-end (this exercises the
   session cookie through the proxy — see the trust-proxy note below).

## Operations

- **Shell into the box (no SSH):**
  ```bash
  aws ssm start-session --target <instance_id> --region eu-north-1
  ```
- **Deploy flow:** push to `enviable-system` `main` → GitHub Actions builds the image → ECR →
  `aws ssm send-command` → the instance pulls and restarts via Docker Compose.
  `prisma migrate deploy` runs on container start.
- **Secrets/config** live in SSM Parameter Store under `/enviable/prod/*` (SecureString for
  secrets). The on-box deploy regenerates `/opt/enviable/.env` from these on every deploy.
- **Session cookies behind Caddy:** the backend sets `proxy: true` on express-session
  (enviable-system) so secure cookies work behind the TLS-terminating proxy. CORS is not needed
  because the frontend proxies `/api/*` server-side, keeping cookies same-origin to `portal`.

## Repo layout

```
bootstrap/            one-time remote-state bucket + DynamoDB lock (local state)
backend.tf            S3 remote state config
versions.tf providers.tf variables.tf main.tf outputs.tf
modules/              network, storage, ecr, ssm, database, iam, compute, cicd
.github/workflows/    terraform.yml (plan on PR, apply on main)
docs/superpowers/     design spec + implementation plan
```

Companion deploy files live in the **enviable-system** repo (`Dockerfile`, `docker-entrypoint.sh`,
`deploy/docker-compose.yml`, `deploy/Caddyfile`, `.github/workflows/deploy.yml`).
