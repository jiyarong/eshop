# Source Mapping From `.claude`

This skill is copied from the repository's `.claude` production helpers:

- `.claude/commands/prod.md`
- `.claude/commands/deploy.md`
- `.claude/settings.local.json`

Relevant inherited conventions:

- Production access goes through `bin/kamal app exec --reuse`
- Deployment goes through `bin/kamal deploy`
- Production writes require explicit confirmation first
- Prefer Kamal-mediated access over manual SSH
