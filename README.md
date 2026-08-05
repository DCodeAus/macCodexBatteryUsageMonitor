# Codex Battery Monitor for macOS

A lightweight, privacy-conscious shell monitor for diagnosing elevated battery use associated with the ChatGPT desktop app, Codex, Computer Use, macOS screen capture, and WindowServer.

This is an independent community diagnostic tool. It is not an official OpenAI product and does not modify Codex, ChatGPT, macOS power settings, or running processes.

## Why this exists

Graphical agent workflows can legitimately use macOS Screen Recording while Computer Use is actively viewing or controlling another application. That can temporarily raise CPU use in processes such as:

- `replayd`, a macOS screen-capture service
- WindowServer, the macOS display compositor
- ChatGPT
- `SkyComputerUseService`
- Codex renderer and service helpers

Brief activity during an active task can be normal. Sustained activity after the task finishes may indicate a capture session, overlay, animation, or retry loop that did not tear down correctly.

This script correlates those process measurements with battery state, charger recognition, and a narrowly counted Codex Pet/PiP recovery message. It helps collect repeatable evidence without continuously running heavyweight tools such as `top` or Activity Monitor.

## Features

- Samples aggregate CPU use for relevant processes using the built-in `ps` command.
- Records battery percentage and charging/discharging state using `pmset`.
- Separately checks whether the battery hardware recognizes external power using `ioreg`.
- Optionally counts a specific Pet/PiP recovery event in local Codex desktop logs.
- Writes simple CSV suitable for charts, issue reports, or before/after comparisons.
- Supports one-shot snapshots, finite sample counts, or continuous monitoring.
- Offers a wall-clock-free mode for less identifying output.
- Reads process executable names with `comm=`, not full command arguments.
- Does not require root access, package installation, or network access.
- Does not kill processes or change system configuration.

## Supported platform

- macOS
- Bash 3.2 or newer; the Bash version included with macOS is sufficient
- ChatGPT desktop app or the earlier standalone Codex app

The monitor uses only standard macOS commands:

```text
pmset ioreg ps awk sed date find
```

No Homebrew packages are required.

## Quick start

Clone or download this repository, then open Terminal in the project folder:

```bash
chmod +x codex-battery-monitor.sh
./codex-battery-monitor.sh
```

The default behaviour is:

- one sample every 30 seconds
- continue until `Ctrl+C`
- alert when `replayd` reaches 30% CPU
- write `codex-battery-monitor.csv` in the current directory
- count the narrowly defined Pet/PiP recovery message in today's Codex logs

Stop monitoring with `Ctrl+C`. The CSV is flushed after every sample, so data already written is retained.

## Recommended diagnostic runs

### One snapshot

```bash
./codex-battery-monitor.sh --once --output snapshot.csv
```

### Two-minute baseline at 10-second intervals

```bash
./codex-battery-monitor.sh --interval 10 --samples 12 --output baseline.csv
```

### Privacy-minimized run

This omits wall-clock timestamps and does not inspect Codex logs:

```bash
./codex-battery-monitor.sh \
  --no-wall-clock \
  --no-log-scan \
  --output private-monitor.csv
```

### Quiet collection

```bash
./codex-battery-monitor.sh --quiet --samples 120 --output long-run.csv
```

### Custom alert threshold

```bash
./codex-battery-monitor.sh --threshold 20
```

## Command reference

| Option | Meaning |
| --- | --- |
| `-i, --interval SECONDS` | Sampling interval. Minimum 5 seconds; default 30. |
| `-o, --output FILE` | CSV output path. Parent directory must already exist. |
| `-n, --samples COUNT` | Stop after this many samples. Without it, monitoring continues until interrupted. |
| `--once` | Alias for `--samples 1`. |
| `-t, --threshold PERCENT` | CPU percentage at which `replayd` is marked high. Default 30. |
| `--no-log-scan` | Do not inspect Codex desktop logs or count Pet/PiP recovery messages. |
| `--no-wall-clock` | Leave the timestamp column empty and use only elapsed seconds. |
| `-q, --quiet` | Suppress terminal status lines while continuing to write CSV. |
| `-h, --help` | Display built-in help. |
| `-v, --version` | Display the monitor version. |

The interval is deliberately limited to five seconds or more. Very frequent process sampling can distort the system being observed.

## CSV schema

| Column | Description |
| --- | --- |
| `timestamp` | Local ISO-like timestamp with numeric timezone, unless `--no-wall-clock` is used. |
| `elapsed_seconds` | Seconds since the monitor started. |
| `battery_percent` | macOS-reported battery percentage. |
| `battery_state` | Usually `charging`, `discharging`, or `charged`. |
| `external_power` | Hardware-level `Yes`, `No`, or `Unknown` from the battery registry. |
| `replayd_cpu` | Aggregate CPU percentage for `replayd`. |
| `windowserver_cpu` | Aggregate CPU percentage for WindowServer. |
| `chatgpt_cpu` | Aggregate CPU percentage for the ChatGPT desktop process. |
| `sky_computer_use_cpu` | Aggregate CPU percentage for `SkyComputerUseService`. |
| `codex_cpu` | Combined CPU percentage for Codex Service and Renderer helpers. |
| `pet_retry_count` | Total matching recovery messages in today's Codex log files; `-1` when disabled. |
| `pet_retry_delta` | New recovery messages since the prior sample. |
| `alert` | `none`, `high_replayd`, or `high_replayd_with_pet_retries`. |

On macOS, 100% CPU represents approximately one fully occupied logical CPU core. A multi-process workload can legitimately total more than 100%.

## Interpreting results

The defaults are diagnostic heuristics, not universal performance limits.

### Likely normal

- CPU rises while Computer Use is actively viewing or operating another app.
- `replayd` and WindowServer fall back toward idle shortly after the visual task stops.
- The Pet retry counter does not increase.
- Battery charges when a sufficiently powerful adapter is recognized.

### Worth investigating

- `replayd` remains above 30% for several consecutive samples after Computer Use stops.
- `SkyComputerUseService` and Codex helpers remain active with no visible task running.
- `pet_retry_delta` repeatedly increases.
- The alert repeatedly reads `high_replayd_with_pet_retries`.
- CPU returns to normal only after fully quitting the ChatGPT desktop app.

### Not necessarily a Codex issue

- High WindowServer CPU without elevated ChatGPT, Codex, or Computer Use CPU may come from external displays, high refresh rates, video playback, another screen recorder, screen sharing, animation, or accessibility software.
- `external_power=No` means the battery hardware does not recognize usable external power. Check the charger, cable, dock, and port before attributing discharge entirely to software.
- An audio or video application may prevent idle sleep independently of Codex.
- Battery percentage changes slowly and is not a direct measurement of instantaneous application energy use.

## Controlled reproduction procedure

Use the following procedure to produce evidence suitable for a bug report:

1. Connect a known-good charger directly to the Mac.
2. Fully quit the ChatGPT desktop app.
3. Wait 30 seconds for related helpers to exit.
4. Reopen the app but do not start Computer Use.
5. Collect a two-minute baseline:

   ```bash
   ./codex-battery-monitor.sh --interval 10 --samples 12 --output 01-idle.csv
   ```

6. Start a narrowly scoped Computer Use task.
7. While the task is active, collect another two minutes:

   ```bash
   ./codex-battery-monitor.sh --interval 10 --samples 12 --output 02-active.csv
   ```

8. Finish or cancel the Computer Use task and wait 30 seconds.
9. Collect a post-task run:

   ```bash
   ./codex-battery-monitor.sh --interval 10 --samples 18 --output 03-after.csv
   ```

10. If applicable, tuck away the floating Pet and repeat the post-task run as `04-pet-disabled.csv`.
11. Compare `replayd_cpu`, `sky_computer_use_cpu`, `codex_cpu`, `pet_retry_delta`, and `alert` across the files.

A useful report demonstrates that idle usage is low, active visual usage rises as expected, and post-task usage either recovers or remains elevated.

## Privacy design

The script contains no hardcoded username, home directory, device identifier, application session identifier, or repository path.

It intentionally collects only:

- timestamps or elapsed seconds
- battery state
- external-power recognition
- aggregate CPU totals by executable name
- the count of one exact recovery-message pattern

It does **not** collect:

- prompts or responses
- command arguments
- filenames opened by Codex
- repository contents
- account details
- device or battery serial numbers
- hardware UUIDs
- conversation, thread, or session identifiers
- raw Codex log lines
- network traffic

New CSV files are created with user-only permissions through `umask 077`.

### Remaining privacy considerations

Wall-clock timestamps can reveal when a computer was in use. Use `--no-wall-clock` before collecting data intended for public sharing.

CPU and battery traces can reveal general usage patterns. Review every CSV before uploading it. For the most conservative collection, combine:

```bash
./codex-battery-monitor.sh --no-wall-clock --no-log-scan
```

The default log scan reads local Codex log files only to count lines containing this exact fixed phrase:

```text
Native pet composition recovery scheduled
```

It does not copy or print those lines. Disable all log access with `--no-log-scan`.

## Troubleshooting

### Permission denied

Make the script executable:

```bash
chmod +x codex-battery-monitor.sh
```

Or invoke it explicitly with Bash:

```bash
bash codex-battery-monitor.sh
```

### Output directory does not exist

Create the directory first or select an existing one:

```bash
mkdir -p monitor-results
./codex-battery-monitor.sh --output monitor-results/run.csv
```

### `external_power=No` while a cable is connected

The battery registry does not currently recognize usable charger input. Disconnect and reconnect the cable, connect directly instead of through a dock, try another port, and confirm the adapter and cable support sufficient USB-C Power Delivery.

### Pet retry count is zero

That is normal when the message is absent, logs were rotated, the Pet feature is not active, the app version uses different wording, or the standalone CLI is being used. The other CPU and battery metrics still work.

### Pet retry count resets

The count covers log files in the current local calendar day. It can reset at midnight or when logs rotate. The script prevents a reset from being reported as a negative delta.

### CPU values differ from Activity Monitor

Process CPU changes quickly. This script and Activity Monitor may sample at different moments and use different averaging windows. Compare trends across several samples rather than expecting exact equality.

### The script itself appears in process lists

The script uses short-lived standard commands. It does not match or add to any monitored process category. Longer intervals further reduce sampling overhead.

## Preparing a public issue report

Prefer a finite run with no wall-clock timestamps:

```bash
./codex-battery-monitor.sh \
  --interval 10 \
  --samples 18 \
  --no-wall-clock \
  --output sanitized-reproduction.csv
```

Before uploading:

1. Open the CSV in a text editor.
2. Confirm the timestamp column is empty if timing privacy matters.
3. Confirm it contains only the documented columns.
4. Do not attach raw Codex logs without reviewing and sanitizing them separately.
5. Include app version, macOS version, hardware class, expected behaviour, actual behaviour, and reproduction steps in prose.

## Testing

Run the included smoke tests:

```bash
./tests/smoke-test.sh
```

The test checks shell syntax, help/version output, argument validation, absence of hardcoded macOS user paths, and—when executed on macOS—a single real monitoring sample written to a temporary directory.

## Publish this folder as a GitHub repository

Create an empty repository on GitHub without adding a generated README, license, or `.gitignore`, because this folder already contains them. Then run the following from the parent directory, replacing the example remote URL:

```bash
cd codex-battery-monitor
git init
git add .
git commit -m "Initial public release"
git branch -M main
git remote add origin https://github.com/YOUR-ACCOUNT/codex-battery-monitor.git
git push -u origin main
```

Before pushing, verify exactly what will be public:

```bash
git status --short
git diff --cached
```

Generated CSV monitoring data is ignored by `.gitignore`, except for the deliberately fictional `examples/sample-output.csv`. Do not force-add personal monitoring files or raw Codex logs.

## Project structure

```text
codex-battery-monitor/
├── .github/
│   └── workflows/
│       └── test.yml
├── examples/
│   └── sample-output.csv
├── tests/
│   └── smoke-test.sh
├── .gitignore
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── codex-battery-monitor.sh
```

## Contributing

Contributions are welcome. Keep collection narrow and privacy-conscious. See [CONTRIBUTING.md](CONTRIBUTING.md) before adding a metric or dependency.

## License

MIT. See [LICENSE](LICENSE).
