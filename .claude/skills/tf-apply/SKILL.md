---
name: tf-apply
description: Apply a previously reviewed Terraform plan file. Use only after tf-plan output has been shown and the human has approved it in this conversation.
---

Preconditions, all required:

- `tf-plan` ran **in this conversation** and its output was shown.
- The plan has `0 to destroy`.
- The human explicitly approved *that* plan. Silence is not approval; "go ahead" earlier in the session about something else is not approval.

Then:

```sh
cd terraform && terraform apply -input=false tf.plan
```

Rules:

- Saved plan file only. Never `terraform apply` with no plan file, never `-auto-approve`, never `-destroy`, never `-target`.
- If the plan is stale ("saved plan is stale"), re-run `tf-plan` and get approval again. Do not force it.
- The PreToolUse hook denies the forbidden forms. If it fires, report the block and stop — do not rewrite the command to get past it.

After: print `terraform output` so the human has the URL, bucket, distribution ID, and CI role ARN.
