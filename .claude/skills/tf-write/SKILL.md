---
name: tf-write
description: Author or edit Terraform in terraform/, using the terraform MCP registry for every resource schema. Use when adding, changing, or removing AWS infrastructure (S3, CloudFront, IAM/OIDC).
---

**Never write a resource block from memory. Look it up first.** Model recall of provider schemas is stale by months; the registry is authoritative.

## Lookup loop (terraform MCP)

```
mcp__terraform__get_latest_provider_version  {namespace:"hashicorp", name:"aws"}
mcp__terraform__search_providers             {provider_namespace:"hashicorp", provider_name:"aws",
                                              provider_version:"latest",
                                              service_slug:"<resource without aws_ prefix>",
                                              provider_document_type:"resources"}
   -> returns providerDocID
mcp__terraform__get_provider_details         {provider_doc_id:"<id>"}
   -> full argument reference + working examples
```

- `service_slug` is the resource name minus `aws_`: `cloudfront_distribution`, `s3_bucket_policy`, `iam_openid_connect_provider`.
- Use `provider_document_type:"data-sources"` for `data` blocks, `"guides"` for major-version upgrade notes.
- Read the **Argument Reference** section, not just the example. Optional-vs-required and deprecation notes live there — that's how you catch things like `thumbprint_list` being ignored for GitHub.
- Before bumping a major provider version, pull the upgrade guide with `provider_document_type:"guides"`.
- `mcp__terraform__search_modules` → `get_module_details` before hand-rolling anything a well-known module already solves. For this stack the resources are few enough that raw resources win — don't add a module for four resources.

## Writing

1. Reuse what's in `terraform/`: existing variables, the `${var.project}-` prefix, existing data sources.
2. New resources go in the file that owns the concern — `main.tf` = site + CDN, `oidc.tf` = CI identity. New file only for a genuinely new concern.
3. No hardcoded bucket names, account IDs, or regions. Those are variables.
4. Drop arguments the docs say are ignored or deprecated. Dead config rots.

## Finish

```sh
cd terraform && terraform fmt -recursive && terraform init -backend=false && terraform validate
```

Both must pass. Then hand off to `tf-plan` — never apply from this skill.

Removing a resource from the code is a destroy in disguise. Say so and stop; the human runs it.
