# Deploy Readiness Audit

Date: 2026-06-22
Environment: production (AWS account 588985586185, region eu-north-1)
Author: infra session
Scope: read-only code/deploy audit plus production data inventory. No destructive
operations were run. No application code was changed.

## Executive summary

The task was framed as (a) clean seed-derived data from a production database that
has accumulated real operational activity since the last deploy, and (b) bring the
infra session current on substantial code changes pending since that deploy. The
evidence contradicts both premises, so this report corrects them before proposing
any action.

Findings in one paragraph: production is roughly four days old (EC2 and RDS both
created 2026-06-18). The backend running in production is commit `d144c32`, which is
the current `main` HEAD of enviable-system, deployed today (2026-06-22 17:16 CEST).
There is no backend code gap between production and main, and no pending Prisma
migrations. The production database holds almost no operational data to preserve:
7 real users, 49 audit-log entries, the RBAC catalog, a small set of seed reference
rows, and three zero-value test transactional records. There are zero customers,
zero sales orders, zero units, zero stock movements, zero payments, zero returns.

The single launch-blocking issue is unrelated to data cleanup: the variant
auto-create feature shipped to production today depends on a sentinel product row
that does not exist in production, so the first supply-side use of it will fail.

## Production environment (verified facts)

- AWS account: 588985586185, region eu-north-1.
- Compute: single EC2 instance `enviable-backend` (i-0b108ecb33bd21b67, t3.micro),
  launched 2026-06-18. Runs docker compose: backend, Caddy (TLS), Redis.
- Database: RDS PostgreSQL `enviable-postgres` (db.t3.micro), created 2026-06-18,
  in a private subnet. Reached only from the EC2 box (same VPC).
- ECR repo: `enviable-backend`. Deploys are image build to ECR plus an SSM
  RunCommand on the box (no ECS).
- Frontend (enviable-web) is a Next.js app and is not deployed on this AWS infra
  (no frontend ECR repo, no frontend service on the box). It deploys on Vercel,
  which is outside the visibility of this AWS-scoped session. Its deploy state must
  be checked in Vercel separately.

## Phase 1: code and deploy audit

### Current production commit and deploy timeline

Running container image tag: `enviable-backend:d144c32c96c0033b7cfff5b3c7eddefe78edb127`.

SSM deploy history (RunCommand comments, all Success):

| When (CEST)        | Commit   | Message |
|--------------------|----------|---------|
| 2026-06-18 21:19   | fe2a4c4  | block PO lines for discontinued variants |
| 2026-06-19 00:37   | c1167ce  | run idempotent seed on deploy |
| 2026-06-19 11:18   | 2058547  | Revert "run idempotent seed on deploy" |
| 2026-06-22 16:12   | b98c470  | align ProductVariant catalog to VSK supplier SKU format |
| 2026-06-22 17:16   | d144c32  | auto-create variants at supply-side entry points (CURRENT) |

`d144c32` is the current `main` HEAD of enviable-system. Production backend equals
main. There is no pending backend code to deploy.

### Migrations

Repo `prisma/migrations` contains exactly five migrations, and all five are applied
in production (table `_prisma_migrations`, all finished 2026-06-18 13:50):

1. 20260522123926_init
2. 20260522123953_invariant_partial_unique_indexes
3. 20260523000000_database_level_immutability
4. 20260525160732_updated_at_for_mirror_spine
5. 20260618000357_user_role_management_fields

No migrations are pending. The Docker entrypoint runs `prisma migrate deploy` on
start, so any future migration applies automatically at deploy time. The entrypoint
does NOT run the seed.

### Permissions

The seed defines 50 permission keys. Production `permissions` holds 50 keys. A
key-by-key diff is empty in both directions: production's permission catalog is
identical to the current code. Despite seed-on-deploy being reverted, the 06-19
seed run already carried the full current permission set.

Not verified: whether every role's permission assignments (`role_permissions`,
249 rows) match the current seed's role-to-permission mapping. The catalog matches,
but specific role grants for newer features may lag. This is low severity because an
admin can grant via the role-management UI, and a missing grant denies rather than
crashes. Recommend a targeted check before launch (see actions).

### Environment variables (SSM Parameter Store, path /enviable/prod)

All required parameters are present:
AWS_REGION, DATABASE_URL (SecureString), DEFAULT_INITIAL_PASSWORD (SecureString),
INVOICE_COMPANY_NAME, INVOICE_DEFAULT_NET_DAYS, INVOICE_SALES_CURRENCY,
PUPPETEER_EXECUTABLE_PATH, REDIS_URL, S3_BUCKET, SESSION_SECRET, SESSION_STORE,
NODE_ENV, PORT, BACKEND_IMAGE.

`DEFAULT_INITIAL_PASSWORD` is set as a SecureString. No SendGrid or email
infrastructure parameters exist (no email decision has landed; not required for the
current code).

### Cookie / reverse-proxy posture

The session trusts the reverse proxy (commit d8c775b) and Caddy terminates TLS in
front of the backend. The running image is built from main, so this fix is in
production. No further production config change is needed for cookies.

## Findings (severity-ranked)

### BLOCKER 1: sentinel product missing in production

The auto-create feature (d144c32, deployed today) attaches every auto-created
variant to a sentinel product `seed-product-pending-classification`. The code
(`src/products/variant-auto-create.ts`, `createAutoVariant`) does a plain
`productVariant.create` with `productId: SENTINEL_PRODUCT_ID`. It does NOT upsert
the sentinel. `ProductVariant.productId` is a non-null foreign key.

Production has only two products: `seed-prod-gsplus` and `seed-prod-zsplus`. The
sentinel row is absent (it was added to the seed in d144c32 today, and seed-on-deploy
was reverted on 06-19, so it was never applied).

Consequence: the first time any operator triggers auto-create (historical-load with
an unknown SKU, or a PO line with an unknown SKU), the insert fails with a foreign
key violation and the entire supply-side transaction rolls back. This is a
launch-blocking defect in a feature already live in production.

Fix (prod-safe). Do NOT run the full seed against production. Established project
knowledge: `prisma/seed.ts` is a dev seed. It matches roles, customer tiers, and
users by mutable `name`/`email` and re-creates test users (a prior prod seed run
created five duplicate test users, hard-deleted 2026-06-19), and it overwrites
operator edits on id-keyed reference rows. Running it would reintroduce that damage.

Correct fix, in order of preference:
- Add an additive Prisma data migration that inserts only the sentinel product
  (`INSERT ... ON CONFLICT (id) DO NOTHING`). It runs via `prisma migrate deploy` at
  the next deploy, is idempotent, and touches nothing else. This belongs in the
  enviable-system repo (build session), not infra. Exact target (verified against
  `prisma/schema.prisma` and `prisma/seed.ts`): table `products`; columns
  `id='seed-product-pending-classification'`, `name='Pending Classification'`,
  `manufacturerId='seed-cp-tvs'` (column is nullable, but the seed sets this and the
  counterparty exists in prod), `category='PASSENGER'` (set explicitly), plus
  `"createdAt"=NOW()` and `"updatedAt"=NOW()`. Note: `updatedAt` is `@updatedAt`
  (client-managed, no DB default), so raw SQL MUST set it or the insert fails NOT NULL.
- If a fix is needed before the next deploy, do a single-row manual INSERT of just
  the sentinel product against production (backup first). Not the seed.

### MEDIUM 2: production variant SKUs are stale relative to the seed

Production has the five expected seed variant ids
(seed-var-gs-ecogreen, seed-var-gs-nepblue, seed-var-gs-winered, seed-var-gs-gyellow,
seed-var-zs-gyellow), but their `supplierSkuCode` values are the pre-realignment
codes (for example `GSP-G-YELLOW`, `GSP-ECO-GREEN`). The current seed (after b98c470)
sets the real VSK SKU format (for example `TVS KING GS+ DP CKD EXP10 G YELLOW`).
Because seed-on-deploy was reverted before b98c470, the new SKUs never reached
production.

This matters for auto-create's similarity detection (edit-distance against existing
ACTIVE variants). Stale codes change which incoming SKUs are flagged as duplicates.
Correct via a targeted additive/idempotent data migration that updates the five
`supplierSkuCode` values by id (build session, enviable-system repo). Do NOT run the
full seed (see Finding 1). Lower urgency than Finding 1: it only affects similarity
flagging, not whether the feature works.

### MEDIUM 3: seed is not applied on deploy

Seed-on-deploy was added (c1167ce) then reverted (2058547). The entrypoint runs only
`prisma migrate deploy`. Consequence: catalog or permission updates that live in the
seed do not reach production through the normal deploy. This is a deliberate choice
(seed should not clobber operational data), but it means seed-delivered changes (the
sentinel product, SKU realignment, future permission additions) need an explicit,
controlled seed run or a targeted migration. Recommend documenting the intended
mechanism for shipping seed-level reference changes to production.

### LOW 4: role-to-permission assignments not verified against the seed

See Permissions above. Catalog matches; per-role grants for newer features are
unverified.

## Phase 2: production data inventory and classification

### Exact row counts (production)

| Table | Rows | Nature |
|-------|------|--------|
| permissions | 50 | RBAC catalog (reference, keep) |
| role_permissions | 249 | RBAC mapping (reference, keep) |
| roles | 14 | RBAC (keep) |
| users | 7 | real team members (keep all) |
| user_roles | 9 | real assignments (keep) |
| audit_log_entries | 49 | audit history (keep all, never delete) |
| feature_toggles | 3 | seed config (keep) |
| customer_tiers | 2 | seed reference: ResellerStandard, ResellerVolume (keep) |
| payment_methods | 2 | seed reference (keep) |
| counterparties | 2 | seed reference: TVS (manufacturer), VSK (supplier) |
| products | 2 | seed: TVS King GS+, TVS King ZS+ |
| product_variants | 5 | seed variants (stale SKUs, see Finding 2) |
| warehouses | 1 | seed: Lagos Main (keep) |
| price_list_entries | 11 | 9 pure seed, 1 superseded seed, 1 operator-created |
| purchase_orders | 1 | test record PO-2026-0001 (zero value, no lines) |
| purchase_order_lines | 0 | none |
| shipments | 1 | test record SH-2026-0001 (isHistoricalImport, no units) |
| proforma_invoices | 1 | test record ORD0000023649 (zero value) |
| proforma_invoice_lines | 0 | none |
| customers | 0 | none |
| sales_orders / sales_order_lines | 0 | none |
| units / stock_movements / payments / returns / invoices | 0 | none |
| (all other tables) | 0 | none |

### What real operator activity exists

- 7 users (Theresa Nwaubani, Daniel Omage, Ikenna Okoye, Kelechi Ekuru, Mr E,
  System Administrator, IT Admin). All real. Several seeded at deploy time but they
  are named team members. Preserve all.
- 49 audit-log entries. Preserve all.
- One operator-created price-list entry: id `cmqkv7o16...`, set by IT Admin on
  2026-06-19, price 2,900,000 for variant seed-var-gs-gyellow (the prior seed entry
  for that variant was superseded with an effectiveTo timestamp). This is real
  pricing activity and should be preserved.
- Three zero-value test transactional records created together on 2026-06-22 13:36:
  PO-2026-0001 (CLOSED, supplier VSK, no lines), SH-2026-0001 (historical import,
  RECEIVED, no units), proforma ORD0000023649 (linked to that PO). These look like a
  smoke test of the historical-load / PO flow, not real business. They produced no
  units, no stock, no downstream chain.

### Classification outcome

The elaborate seed-vs-accumulated classification the original task anticipated does
not apply: the operational tables it worried about (customers, sales orders, units,
stock movements, payments, returns) are empty. There is no tangle of seed-origin
data now referenced by real activity to carefully preserve.

The only genuine cleanup question is small and is a business decision, not a
referential-integrity decision:

1. The 2 products, 5 variants, 2 counterparties, 2 customer tiers, 11 price-list
   entries, 1 warehouse: are these the real reference catalog the team intends to
   launch with, or throwaway placeholders? They model real entities (TVS King
   GS+/ZS+ in real colours, real suppliers, a real Lagos warehouse, real tier
   pricing), so they read as intended launch reference data, not test fixtures. The
   recommendation is to keep them and correct the stale SKUs via a targeted data
   migration (Finding 2), not to delete them and not via the full seed.
2. The 3 zero-value test transactional records (PO, shipment, proforma): these are
   the only plausible deletion candidates. They are operator-created (post-deploy),
   carry audit-log references, and deleting them would remove those audit rows'
   referents. Given audit integrity is paramount and these do no harm, the
   recommendation is to leave them and let real PO/shipment numbering continue from
   PO-2026-0002 onward, OR, if a clean launch ledger is wanted, delete them only
   after an explicit decision and a backup. This is the user's call.

No deletions were performed. Nothing in the database currently requires deletion to
make the system function.

## Recommended actions before launch

Priority order:

1. (BLOCKER) Create the sentinel product in production via an additive data
   migration (`INSERT ... ON CONFLICT DO NOTHING`) in the enviable-system repo, which
   applies on the next deploy. Do NOT run the full seed (it duplicates users and
   clobbers id-keyed reference edits). Take an RDS snapshot before any write.
2. (MEDIUM) Adopt additive data migrations as the standard mechanism for shipping
   reference changes (sentinel, SKU corrections, future permissions) to production
   (Finding 3). The full seed is dev-only and not prod-safe.
3. (LOW) Verify role-to-permission assignments against the current seed mapping for
   the newer features (productvariant.manage, return.manage, unit.adjust, pi.review,
   shipment.receive, etc.). Grant via the role UI where missing.
4. (BUSINESS) Decide whether to remove the three zero-value test transactional
   records. Default recommendation: leave them.
5. (SEPARATE) Confirm the enviable-web (Vercel) deploy is current with web main and
   points at the production backend URL. Out of scope for this AWS session.

## What was not done, and why

- No destructive database operations. The task's destructive Phase 2 was gated on an
  explicit confirmed deletion list, and the evidence shows there is essentially
  nothing that needs deleting. The only deletion candidates are a business decision.
- No database backup was taken yet. A backup belongs immediately before any write
  (the seed run for the sentinel, or any deletion), not before a read-only audit.
  Recommend an RDS snapshot of `enviable-postgres` as the first step of whatever
  write action is approved next.
- No application code changes. This round is read plus reporting only.

## Verification outcome (2026-06-22, post-deploy)

BLOCKER 1 (sentinel) and MEDIUM 2 (stale SKUs): RESOLVED and verified in production.

- Migration `20260622213814_production_sentinel_and_variant_realignment` (commit
  55053a9) auto-deployed via CI and applied to prod at 2026-06-22 21:44:08 UTC. It is
  recorded in `_prisma_migrations` with `finished_at` set and `rolled_back_at` null.
- Running container is now `enviable-backend:55053a9`.
- Sentinel row present in `products`: id `seed-product-pending-classification`, name
  `Pending Classification`, category `PASSENGER`, `manufacturerId` NULL (the build
  session set NULL deliberately, since the migration runs before the seed and an FK to
  the seeded manufacturer would break fresh-env safety; the column is nullable).
  Product count is now 3.
- All 5 variant `supplierSkuCode` values realigned to the VSK format
  (`TVS KING GS+ DP CKD EXP10 ...`, `TVS KING ZS+ DP CKD EXP10 G YELLOW`).
- FK satisfiability probe (BEGIN; INSERT a variant on the sentinel; ROLLBACK):
  insert succeeded, then rolled back, post-rollback row count 0. Auto-create's insert
  is now satisfiable in production with no test data persisted.
- Backout point: RDS snapshot `enviable-pre-sentinel-20260622-2348`. Note it was taken
  a few minutes AFTER the migration applied (CI deployed faster than the snapshot
  started), so it captures the post-migration state, not pre-migration. This is
  immaterial: the change verified correct, the pre-migration state is fully documented
  in this report (5 old SKUs GSP-/ZSP-, sentinel absent), and a revert is a trivial,
  safe reverse (zero auto-created variants point at the sentinel yet, so it can be
  deleted and SKUs reverted with no orphaning).

## Decisions and current status (2026-06-22, post-review)

- BLOCKER 1 (sentinel) and MEDIUM 2 (stale SKUs): resolved via a single idempotent
  data migration authored in the build session (enviable-system), not a manual prod
  INSERT and not the full seed. Rationale: keeps all prod data changes flowing through
  repo migration files so a rebuild-from-migrations path cannot reintroduce the bug,
  and bundles both fixes in one commit. No real-use is racing the fix (zero
  operational users), so waiting for the migration to land is acceptable.
- Deploy mechanics: `enviable-system/.github/workflows/deploy.yml` triggers on push to
  main. When the migration commit lands on main, CI builds the image and SSM-deploys
  it, and the container entrypoint runs `prisma migrate deploy`, applying the migration
  to production automatically. There is no separate infra deploy step. The infra
  session's job is post-deploy verification (sentinel row present, migration recorded
  in `_prisma_migrations`, auto-create succeeds against an unknown SKU). Take an RDS
  snapshot of `enviable-postgres` immediately before that deploy as the backout point.
- Phase 2 test records: the 3 zero-value records (PO-2026-0001, SH-2026-0001, proforma
  ORD0000023649) will be LEFT in place. Deleting them would orphan their audit-log
  references, and clean numbering (starting at 0001) is cosmetic. Real numbering
  continues from PO-2026-0002.
- Frontend (Vercel) currency: OPEN. enviable-web main HEAD is `0536c0c` (clean, pushed
  to origin/main). Vercel production should show this commit. Auto-deploy from web main
  normally keeps it current; verify in the Vercel dashboard (or via the Vercel
  integration) that prod equals `0536c0c`, and trigger a deploy from main if it lags.
  Risk if stale: backend supports auto-create but the frontend would not surface its UI.

## Verification evidence

- Running image: `docker ps` on i-0b108ecb33bd21b67 via SSM RunCommand.
- Deploy timeline: `aws ssm list-commands` and `aws ecr describe-images`.
- Data counts and rows: psql against the production database, reached from the EC2
  box via SSM (RDS is private). Sensitive user columns (passwordHash, initialPassword)
  were redacted in the query.
- Migrations, permissions, env: `_prisma_migrations` and `permissions` queried in
  prod; SSM Parameter Store listed; repo files read directly.

## Operational hardening (2026-06-25)

Follow-up to the CD disk-full incident (see enviable-system#1, merged as `83aa9b3`,
which changed `docker image prune -f` to `-af`). Tracked in enviable-infra#1. The four
items below were addressed as one batch. Terraform changes were applied via the
sanctioned `terraform` workflow_dispatch by the infra session (not a local apply, and
not an auto-apply on push), keeping the "no silent apply" rule intact.

1. Deploy-failure visibility. Three layers now exist:
   - GitHub Actions already exits non-zero on a failed SSM deploy (native failure email
     to the actor/watchers). This was always present; the gap was nobody watching.
   - Real-time: an EventBridge rule (`enviable-ssm-command-failed`) matches any SSM Run
     Command that goes to `Failed`/`TimedOut` and publishes to the `enviable-alerts` SNS
     topic. This catches the exact disk-full failure mode within seconds.
   - Daily: an SSM association (`enviable-image-drift-check`, `rate(1 day)`) runs a
     shell document on the box comparing the running backend container image tag against
     the recorded `/enviable/prod/BACKEND_IMAGE`. On mismatch (the "deployed but not
     really" state) it publishes to SNS via the instance role's scoped `sns:Publish`.

2. EBS sizing. Root gp3 volume grown 20G to 40G via Terraform (`modules/compute`,
   in-place modify, no instance replacement, no downtime). The OS partition and xfs
   filesystem were then grown live with `growpart /dev/nvme0n1 1` and `xfs_growfs /`.

3. `.env`-before-pull ordering. The deploy script wrote `.env` before pulling the image,
   so a failed pull left `.env` pointing at an undeployed image. Reordered to pull first
   and only rewrite `.env` after a successful pull. This lives in the backend repo and is
   proposed as a PR (enviable-system) per the repo guard; the backend session merges.

4. Disk-usage alarm. The CloudWatch agent was installed on the box (live via SSM, not in
   userdata which would force-replace the instance) and configured from an
   `AmazonCloudWatch-enviable-prod` SSM parameter to publish `disk_used_percent`
   aggregated to `InstanceId`. A CloudWatch alarm (`enviable-root-disk-high`) fires to
   SNS at >=80%, giving warning before a deploy can fail with ENOSPC.

Alerts route to the `enviable-alerts` SNS topic, email-subscribed to the infra contact
address (`caddy_email`). The subscription requires a one-time confirmation click.
New Terraform: `modules/monitoring` (SNS, subscription, topic policy, EventBridge rule
and target, CW agent config param, disk alarm, drift document and association);
`modules/iam` gains `CloudWatchAgentServerPolicy` and a scoped `sns:Publish`;
`modules/compute` volume bumped to 40G.

Latent footgun fixed in the same change: the instance AMI comes from the "latest
AL2023" SSM parameter, so the first `terraform plan` after AWS published a newer AL2023
image wanted to replace the production box (`aws_instance` forced replacement on `ami`).
That would have destroyed `/opt/enviable` and the running containers. Added
`lifecycle { ignore_changes = [ami] }` on the instance so AMI drift no longer forces
replacement; image refreshes are now a deliberate taint/replace, not a side effect of an
unrelated apply. Verified the post-fix plan shows the instance updated in-place (volume
only), with zero destroys.
