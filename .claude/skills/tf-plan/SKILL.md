---
name: tf-plan
description: Run a read-only Terraform plan for terraform/ and summarize the diff. Use before any infra change and whenever asked "what would this change".
---

```sh
cd terraform
terraform init -input=false
terraform validate
terraform plan -input=false -out=tf.plan
```

Report, in this order:

1. **Destroys and replaces first** — every `-` and `-/+` line, named explicitly. This is what the human is reading for.
2. Creates and in-place updates, one line each.
3. The `Plan: X to add, Y to change, Z to destroy` tally.

If Z > 0: stop. Say plainly what would be deleted and why the plan thinks so. Do not continue to `tf-apply`, do not offer to "apply just the safe parts", do not add `-target` to dodge it.

If the plan errors on an unknown or invalid argument, don't guess the fix — go back through `tf-write` and check the schema with `mcp__terraform__get_provider_details`.

`tf.plan` is gitignored. Leave it on disk; `tf-apply` consumes exactly that file.
