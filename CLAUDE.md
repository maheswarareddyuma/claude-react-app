# CLAUDE.md

React SPA built with Create React App, deployed as static files to **S3 + CloudFront**, infra managed by **Terraform**, shipped by **GitHub Actions using AWS OIDC** (no long-lived keys).

## Stack

- React 19 + `react-scripts` 5.0.1 (CRA — not Vite, not Next)
- Tests: React Testing Library + Jest, specs live in `src/tests/`
- `Dockerfile` and `.github/workflows/ci-cd.yml` are the old VM/nginx + Docker Hub deploy. **Not part of this pipeline — leave them alone.** The live path is `.github/workflows/deploy.yml`.

## Commands

```sh
npm install          # deps
npm start            # dev server, localhost:3000
npm test             # CI=true npm test  -> non-watch
npm run build        # -> build/  (this is the artifact that goes to S3)
```

`npm run build` output is `build/` — plain static files. Anything that deploys this app uploads `build/` to the S3 bucket and invalidates the CloudFront distribution. Never `npm run eject`.

## Infrastructure

Terraform lives in `terraform/` — `versions.tf`, `variables.tf`, `main.tf` (bucket + CDN), `oidc.tf` (CI identity), `outputs.tf`.

- S3 bucket, private, no public access — CloudFront origin only, encrypted, versioned
- CloudFront + Origin Access Control (OAC), not legacy OAI; bucket policy scoped by `AWS:SourceArn`
- SPA routing: 403/404 → `/index.html` with 200
- Managed cache policy `CachingOptimized` + response headers policy `SecurityHeadersPolicy`
- Default `*.cloudfront.net` cert. A custom domain needs `aliases` + an ACM cert in `us-east-1` via a provider alias — not wired up yet.
- GitHub OIDC provider + one CI role, trust scoped to `repo:<owner>/<repo>:*`

Remote state in S3 with **native lockfile locking** (`use_lockfile`, TF ≥ 1.10) — no DynamoDB table. Backend is partial config; CI supplies `bucket` and `region` via `-backend-config`. State is never committed.

**Terraform never runs in CI.** All infra changes are applied locally by a human via `tf-plan` → `tf-apply`. CI has no state access and no IAM permissions — it can upload objects to the site bucket and create an invalidation, nothing else. If a change needs new infra, apply it before merging the code that depends on it.

**`github_repo_ids` is the only value Terraform asks for** — `owner@owner_id/repo@repo_id`, validated. It's a security boundary: it decides which repository may assume the deploy role, so it is never defaulted or guessed. GitHub embeds immutable numeric ids in the OIDC subject claim, and the trust policy matches only that form — the plain `owner/repo` name is deliberately not accepted, because a freed name can be re-registered by someone else while ids are never reissued. Get it with `gh api repos/<owner>/<repo> --jq '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'`. Everything else is derived: the AWS account id comes from your credentials, and the bucket name is `${project}-site-${account_id}`, which is globally unique for free. Real values go in `terraform/terraform.tfvars` (gitignored); `terraform.tfvars.example` is the template.

Create the state bucket by hand, then `terraform init -backend-config="bucket=..." -backend-config="region=..."` and apply. If the account already has the GitHub OIDC provider, `terraform import` it rather than creating a duplicate.

Then wire the outputs into GitHub — variables: `AWS_REGION`, `SITE_BUCKET` (= `bucket_name`), `CLOUDFRONT_DISTRIBUTION_ID` (= `distribution_id`); secret: `AWS_DEPLOY_ROLE_ARN` (= `ci_role_arn`).

### MCP servers

Declared in `.mcp.json` (project scope — approve them on first launch). Requires Docker running and `uvx` on PATH.

| Server | Runs as | Tools |
|---|---|---|
| `terraform` | `docker run -i --rm hashicorp/terraform-mcp-server` | `search_providers`, `get_provider_details`, `get_latest_provider_version`, `get_provider_capabilities`, `search_modules`, `get_module_details`, `get_latest_module_version`, `search_policies`, `get_policy_details` |
| `aws` | `uvx --from awslabs.aws-api-mcp-server@latest awslabs.aws-api-mcp-server` | `call_aws`, `suggest_aws_commands` |

**Never write a Terraform resource block from memory.** Look up the schema first:
`get_latest_provider_version` → `search_providers` (gives a `providerDocID`) → `get_provider_details` (full argument reference). `service_slug` is the resource name minus `aws_`, e.g. `cloudfront_distribution`.

The aws server runs with `READ_OPERATIONS_ONLY=true` and `REQUIRE_MUTATION_CONSENT=true` — it refuses mutating CLI calls outright. That's the second layer under the Bash hook, and it's why the audit agents can't damage anything even if they try. Deploys go through the CI role and the `deploy` skill, not through this server.

The registry has already caught two things hand-written config got wrong: the AWS provider is at **6.57.0** (not 5.x), and `thumbprint_list` on the GitHub OIDC provider is ignored by AWS — see the comment in `oidc.tf`.

## Hard rules — destructive Terraform is blocked

**Never run, suggest running, or write a script/workflow step containing:**

- `terraform destroy` (or `-destroy`, `terraform apply -destroy`, `terraform plan -destroy`)
- `terraform state rm` / `terraform state mv` / `terraform taint`
- `terraform force-unlock`
- `terraform apply -auto-approve` outside CI
- `aws s3 rb`, `aws s3 rm --recursive`, `aws cloudfront delete-distribution`
- `terraform workspace delete`

This is enforced by a `PreToolUse` hook (`.claude/settings.json`) that **denies** the Bash call, not just warns. If the hook fires, do not look for a workaround, do not rewrite the command to evade the pattern, do not use a different tool to do the same thing. Report the block and stop.

If a resource genuinely must be removed, the human does it manually outside Claude Code. Say that; don't do it.

`terraform plan` is always safe and always runs first. `terraform apply` is allowed only after a plan has been shown and the human has approved that specific plan in the conversation.

### Hook layout (`.claude/settings.json`)

| Hook | Job |
|---|---|
| `UserPromptSubmit` | Injects the destructive-command rule into context on every turn, so it survives long sessions. |
| `PreToolUse` (Bash) | Pattern-matches the command against the deny list above → `permissionDecision: "deny"`. The actual guardrail. |
| `PostToolUse` (Edit/Write on `*.tf`) | Runs `terraform fmt` + `terraform validate` on the changed file. |

## Skills / agents

Skills (`.claude/skills/`) — do work:

| Name | Does |
|---|---|
| `tf-write` | Authors/edits `.tf` files. Pulls every schema from terraform MCP first; never invents arguments. |
| `tf-plan` | `init` → `validate` → `plan -out=tf.plan`, summarizes the diff, destroys listed first. Read-only. |
| `tf-apply` | Applies **a saved plan file only**, after the human approves that plan in-conversation. Refuses `-auto-approve`, `-target`, and any destroy. |
| `deploy` | `npm ci` → `npm test` → `npm run build` → `s3 sync` → CloudFront invalidation. Manual/local only; CI does this on merge. |

Agents (`.claude/agents/`) — read-only, report and stop:

| Name | Does |
|---|---|
| `infra-check` | Live AWS vs. code — bucket policy, OAC, SPA error responses, cache headers, a real `curl` of the site. |
| `drift-detector` | `plan -refresh-only -detailed-exitcode`; classifies each drift as adopt / revert / ignore. |
| `security-auditor` | Public ACLs, unscoped bucket policy, legacy OAI, TLS < 1.2, wildcard IAM, unscoped OIDC `sub`, committed secrets. |
| `cost-optimizer` | Cache hit ratio, price class, invalidation volume, noncurrent-version lifecycle. Says "nothing to do" when true. |

Agents have no Edit/Write tools by design, and their aws MCP access is read-only. They report; the human decides.

No `scaffold-terraform` — the baseline exists. Use `tf-write` to change it.

## CI/CD

GitHub Actions, OIDC only — **no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets anywhere**. If you see them in a workflow, that's a bug to flag.

```yaml
permissions:
  id-token: write     # required for OIDC
  contents: read

- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION }}
```

`.github/workflows/deploy.yml`, one job, deliberately small:

```
npm ci  →  CI=true npm test  →  npm run build  →  aws s3 sync build/  →  invalidate
```

PRs stop after the build — they never assume the AWS role (the OIDC trust policy only accepts `ref:refs/heads/main`, so a fork PR cannot reach the bucket even if a step were added). Only pushes to `main` deploy.

Upload splits caching: hashed assets get `max-age=31536000,immutable`, `index.html` gets `no-cache`. Getting this backwards is the classic "my deploy didn't show up". The invalidation is belt-and-braces — `no-cache` on `index.html` already makes CloudFront revalidate, and every other file is content-hashed.

No workflow may contain a destroy step or a `terraform apply`. There is no "teardown" job.

## Conventions

- Provider versions are pinned in `versions.tf`. Keep them pinned.
- Never commit: `.terraform/`, `*.tfstate*`, `*.tfplan`, `tf.plan`, `terraform.tfvars`, `.env`, AWS creds. All gitignored — keep it that way. `.terraform.lock.hcl` *is* committed: it pins provider hashes across machines.
- Only `build/static/` is content-hashed. Anything else keeps a fixed filename, so it must never be sent with `immutable` — an invalidation clears the CDN edge, not a browser cache.
- CRA inlines every `REACT_APP_*` env var into the public bundle. Nothing secret goes there.
- Bucket names and account IDs come from variables, never hardcoded in resource blocks.
