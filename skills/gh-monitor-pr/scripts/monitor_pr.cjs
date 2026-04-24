const { execSync } = require('child_process');

const prNumber = process.argv[2];
const intervalSeconds = parseInt(process.argv[3] || '30');
const timeoutMinutes = parseInt(process.argv[4] || '30');

if (!prNumber) {
  console.error('Usage: node monitor_pr.cjs <pr-number> [interval-seconds] [timeout-minutes]');
  process.exit(1);
}

const startTime = Date.now();
const timeoutMs = timeoutMinutes * 60 * 1000;

console.log(`Monitoring PR #${prNumber} every ${intervalSeconds}s (Timeout: ${timeoutMinutes}m)...`);

function checkStatus() {
  try {
    const output = execSync(`gh pr view ${prNumber} --json statusCheckRollup`, { encoding: 'utf8' });
    const data = JSON.parse(output);
    const rollup = data.statusCheckRollup || [];

    const total = rollup.length;
    const completed = rollup.filter(c => c.status === 'COMPLETED').length;
    const failed = rollup.filter(c => c.conclusion === 'FAILURE' || c.conclusion === 'CANCELLED' || c.conclusion === 'TIMED_OUT');
    const success = rollup.filter(c => c.conclusion === 'SUCCESS').length;

    if (total === 0) {
      // No checks yet? Or maybe checks haven't started.
      // We'll wait.
      return 'WAITING';
    }

    if (failed.length > 0) {
      console.log('\nFAILURE: Some checks failed:');
      failed.forEach(f => console.log(`- ${f.name} (${f.conclusion}): ${f.detailsUrl}`));
      process.exit(0); // Exit cleanly so agent can read output
    }

    if (success === total) {
      console.log('\nSUCCESS: All checks passed.');
      process.exit(0);
    }

    process.stdout.write(`\rProgress: ${completed}/${total} completed...`);
    return 'IN_PROGRESS';
  } catch (error) {
    console.error(`\nError checking status: ${error.message}`);
    return 'ERROR';
  }
}

const timer = setInterval(() => {
  if (Date.now() - startTime > timeoutMs) {
    console.log('\nTIMEOUT: Monitoring period exceeded.');
    clearInterval(timer);
    process.exit(0);
  }

  const result = checkStatus();
  if (result === 'SUCCESS' || result === 'FAILURE') {
    clearInterval(timer);
  }
}, intervalSeconds * 1000);

// Initial check
checkStatus();
