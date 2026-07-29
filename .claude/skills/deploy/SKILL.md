---
name: deploy
description: Build the React app and publish it to S3 + CloudFront. Use when asked to deploy, ship, publish, or push the site live.
---

CI does this automatically on merge to `main` (`.github/workflows/deploy.yml`) — install, test, build, sync, invalidate, nothing more. Use this skill only for a manual/local deploy.

```sh
npm ci
CI=true npm test
GENERATE_SOURCEMAP=false npm run build   # -> build/  (no .map on a public CDN)

cd terraform
BUCKET=$(terraform output -raw bucket_name)
DIST=$(terraform output -raw distribution_id)

# Only build/static/ is content-hashed, so only it may be immutable. Everything
# else keeps a fixed filename and must stay revalidated.
aws s3 sync ../build/static "s3://$BUCKET/static" --delete \
  --cache-control "public,max-age=31536000,immutable"
aws s3 sync ../build "s3://$BUCKET" --delete \
  --exclude "static/*" --cache-control "no-cache"

aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*"
```

- Tests failing = stop. Do not deploy around a red test.
- Never mark a non-hashed filename `immutable`. An invalidation clears the CloudFront edge, not a browser cache — a wrong `immutable` sticks for a year.
- `--delete` only ever touches the site bucket. Never run it against the state bucket.
- Infra changes are not part of this skill — that's `tf-plan` / `tf-apply`.
- Report the URL from `terraform output -raw site_url` when done.
