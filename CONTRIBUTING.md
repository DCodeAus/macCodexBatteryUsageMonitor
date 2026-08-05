# Contributing

Thank you for helping improve Codex Battery Monitor.

## Principles

Changes should preserve these properties:

1. **Privacy by design.** Collect aggregate diagnostic signals, not prompts, command arguments, filenames, account details, identifiers, or raw logs.
2. **Low overhead.** The monitor must not materially distort the CPU or battery behaviour it observes.
3. **No mutation.** Monitoring must not terminate processes, change permissions, edit Codex configuration, or alter macOS power settings.
4. **No network access.** Collection should remain fully local.
5. **Standard macOS tooling.** Avoid dependencies unless a capability cannot be implemented safely with built-in commands.
6. **Evidence over attribution.** Treat process correlation as diagnostic evidence, not automatic proof of a root cause.

## Development workflow

1. Create a focused branch.
2. Make the smallest change that solves the problem.
3. Update README documentation for every user-visible option or collected field.
4. Add or update smoke-test coverage.
5. Run:

   ```bash
   ./tests/smoke-test.sh
   ```

6. Test a finite real run on macOS:

   ```bash
   ./codex-battery-monitor.sh --interval 5 --samples 2 --no-wall-clock --output test-run.csv
   ```

7. Inspect the generated CSV and confirm no unexpected data is present.

## Adding a metric

Before adding a metric, document:

- what diagnostic question it answers
- why existing fields are insufficient
- which local command or file supplies it
- its collection cost
- its privacy implications
- how users can disable it

Do not add raw command lines, environment variables, open-file lists, network destinations, window titles, prompts, repository paths, or unfiltered log text.

## Pull requests

Keep pull requests narrow. Include:

- a concise problem statement
- before/after behaviour
- test output
- macOS version used for manual testing
- any privacy or performance tradeoff

Do not attach personal monitoring CSVs or raw Codex logs to a public pull request.

