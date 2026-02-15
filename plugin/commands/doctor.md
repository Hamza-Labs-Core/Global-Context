---
name: doctor
description: Run health checks on the GlobalContext system
---

# GlobalContext: Doctor

Run comprehensive health checks on the GlobalContext system to verify everything
is functioning correctly.

## Execution

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gc-query" doctor
```

## Output

Present the health check results to the user. Flag any failures or warnings.
If issues are found, suggest remediation steps:
- Missing directories: suggest re-initializing with `gc-init`
- Missing scripts: suggest reinstalling the plugin
- Stale projections: suggest running gc-query to rebuild
- Disk space warnings: report usage and suggest reviewing old sessions
