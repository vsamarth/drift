---
name: gh-monitor-pr
description: Monitor a GitHub Pull Request status and merge automatically on success or report errors on failure. Use when you want to wait for CI to finish and take action.
---

# GH Monitor PR

Monitor the CI status of a GitHub Pull Request and take automatic action upon completion.

## Usage

Use the bundled `monitor_pr.cjs` script to poll the PR status. This script handles the waiting logic and provides a clear summary of success or failure.

### Polling for Status

Execute the script using `node`:

```bash
node scripts/monitor_pr.cjs <pr-number> [interval-seconds] [timeout-minutes]
```

- **pr-number**: (Required) The PR number to monitor.
- **interval-seconds**: (Optional, default: 30) Seconds between checks.
- **timeout-minutes**: (Optional, default: 30) Total time to monitor before giving up.

### Handling Output

The script will exit with a summary message:

- **SUCCESS**: All checks passed. You should proceed to merge the PR.
- **FAILURE**: One or more checks failed. Report the specific failures to the user.
- **TIMEOUT**: Monitoring ended without reaching a final state.

## Automatic Merge & Cleanup

If the script reports **SUCCESS**, use the GitHub CLI to merge the PR and immediately perform a local cleanup:

1. **Merge the PR:**
   ```bash
   gh pr merge <pr-number> --merge --auto
   ```

2. **Switch to main and refresh:**
   ```bash
   git checkout main && git pull
   ```

3. **Delete the local feature branch:**
   ```bash
   git branch -d <branch-name>
   ```

## Error Reporting

If the script reports **FAILURE**, use `gh pr view <pr-number> --json statusCheckRollup` to get detailed logs if the script's output isn't enough, and present the errors to the user.
