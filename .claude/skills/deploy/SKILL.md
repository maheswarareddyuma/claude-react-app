---
name: deploy
description: Build the React app and publish it to S3 + CloudFront. Use when asked to deploy, ship, publish, or push the site live.
---

CI does this automatically on merge to `main` (`.github/workflows/deploy.yml`) — install, test, build, sync, invalidate, nothing more. Use this skill only for a manual/local deploy.

```sh
npm ci
CI=true npm test
npm run build            # -> build/

cd terraform
BUCKET=$(terraform output -raw bucket_name)
DIST=$(terraform output -raw distribution_id)

aws s3 sync ../build "s3://$BUCKET" --delete \
  --cache-control "public,max-age=31536000,immutable" --exclude "index.html"
aws s3 cp ../build/index.html "s3://$BUCKET/index.html" --cache-control "no-cache"

aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*"
```

- Tests failing = stop. Do not deploy around a red test.
- `--delete` only ever touches the site bucket. Never run it against the state bucket.
- Infra changes are not part of this skill — that's `tf-plan` / `tf-apply`.
- Report the URL from `terraform output -raw site_url` when done.
