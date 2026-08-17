---
name: production-ops
description: Access and operate the production eshop service through local Kamal commands. Use when the user asks to inspect or run commands against the live Rails app, query production data, execute Rails runner code in production, or deploy the current branch to the production server. Trigger on requests like "线上", "prod", "production", "正式环境", "deploy", or production troubleshooting.
---

# Production Ops

Use the local repository's `bin/kamal` entrypoints to access the production app at `eshop.evexport.cn`.

## Environment

- Host: `eshop.evexport.cn`
- Access path: `bin/kamal app exec`
- Runtime: Kamal-managed app container
- Preferred target: reuse the running web container with `--reuse`

## Production app commands

For production inspection or Rails-side execution, run:

```bash
cd /Users/jiyarong/Developer/5/eshop && bin/kamal app exec --reuse "bin/rails runner '<ruby code>'"
```

For complex multiline Ruby, use this form:

```bash
cd /Users/jiyarong/Developer/5/eshop && bin/kamal app exec --reuse "bin/rails runner \"$(cat <<'RUBY'
<ruby code>
RUBY
)\""
```

## Rules

1. Translate natural-language production inspection requests into explicit Ruby or Rails commands before execution.
2. Default to read-only operations. Prefer `.pluck`, `.count`, `find_by`, `limit`, `puts`, and `pp`.
3. Treat `create!`, `update!`, `save!`, `delete`, `destroy`, migrations, backfills, and report runners with side effects as write operations.
4. Before any write operation, show the exact command or Ruby code and ask for confirmation.
5. Keep outputs concise and structured so the user can read terminal results quickly.
6. Do not fall back to manual SSH unless Kamal access is unavailable and the user explicitly wants SSH-based access.

## Deployment

Deploy the current branch with:

```bash
cd /Users/jiyarong/Developer/5/eshop && bin/kamal deploy
```

Before deployment:

1. Show `git status --short`.
2. Show the latest commit summary.
3. If there are uncommitted changes, warn the user.
4. Ask for confirmation before running the deploy command.

## Examples

- `线上查一下 ec_weekly_rates 有哪些记录`
- `prod 跑一下某段只读 runner`
- `部署到正式环境`

