# Clara performance investigation — September 25, 2026

This report measures version 0.4.3. Version 0.4.4 restores the single dark native backdrop by visual preference and extends it to the navigator and file dock; the measurements below do not establish performance for that later styling change.

## Method

Test machine: Apple M4 MacBook Air, 16 GB RAM, macOS 27, Apple silicon release builds. Synthetic app window: 1380 × 880 points. The user's existing Clara process remained running; it was never terminated. Background system load and macOS timer coalescing introduce variation.

Instruments Time Profiler captured both the existing idle app and an isolated synthetic workload. Comparative measurements below run **without Instruments attached**. The original baseline ran twice, then once more immediately before the final two optimized runs; runs were sequential, without concurrent compilation. All recorded thermal states were nominal. The baseline is commit `4ad118f` plus the same opt-in workload used for the optimized build.

The workload opens three isolated `zsh -f` sessions, cycles full/right/bottom terminal panels, feeds terminal output, inserts text into a 900-line Swift file, appends Markdown chunks to a 100-message conversation, scrolls chat, and idles. Each phase performs 60 steps separated by approximately 100 ms. It does not call an AI service or run user shell startup scripts. Terminal output is injected into the renderer, so this does not benchmark a compiler or SSH connection.

CPU seconds measure process user + system CPU for the same work. Main-loop p95 is a 60 Hz timer's interval, **not rendered FPS, GPU time, or input latency**. The workload exercises native text insertion and programmatic scrolling, not human typing or a trackpad. Idle timer measurements are especially sensitive to App Nap/coalescing.

## Comparative results

CPU values are the mean across three baseline and two optimized runs. p95 columns show the range across runs; averaging percentiles would hide variability. Full synthetic metrics are in [the results folder](performance/2026-09-25).

| Workload | Baseline CPU (s) | Optimized CPU (s) | Baseline p95 (ms) | Optimized p95 (ms) |
|---|---:|---:|---:|---:|
| idle three terminals | 0.241 | 0.052 | 16.7–17.5 | 17.1–17.4 |
| panel cycle | 3.895 | 4.148 | 27.0–65.6 | 32.4–65.3 |
| terminal output | 1.282 | 1.288 | 23.9–26.5 | 26.4–26.9 |
| editor typing | 4.300 | 1.940 | 80.3–83.5 | 38.6–45.4 |
| streamed markdown | 2.711 | 2.802 | 49.5–51.2 | 55.3–55.5 |
| chat scroll | 1.657 | 1.783 | 35.9–40.3 | 39.3–40.0 |
| idle after work | 0.248 | 0.113 | 17.5–108.8 | 16.7–17.5 |

Editor typing is the repeatable gain. Panel timing remains variable, and chat scrolling/streaming have no demonstrated improvement. RSS measurements also varied: no memory-reduction claim is made. Idle CPU fell in the initial three-terminal phase; this is not a battery-life benchmark.

## Findings and retained changes

- The idle trace included terminal activity polling that published unchanged state. Polling now publishes only on a real activity transition.
- The workload trace was dominated by native text layout, with repeated full-file syntax highlighting and regular-expression matching. Regexes are cached; typing recolors affected lines; the editor uses incremental TextKit 1 layout with noncontiguous layout enabled.
- The focus-ring workaround walked the entire native view tree on every window update. It now visits only the focused view's ancestors when focus changes.
- The final patch preserves the existing glass layers, window dragging, and synchronized docking animations.

## Rejected experiments

A compositor-transform docking animation increased panel-cycle CPU and stalls, so it was removed. Shorter spring transitions and an explicit equatable message wrapper did not show a reliable benefit and were also removed. Removing stacked blur layers and changing background window dragging also failed to produce a consistent panel improvement. Those changes were reverted. These experiments are not part of the shipped optimization.

## Limits and remaining work

Rich Markdown streaming and long-chat scrolling still need dedicated work; this patch does not claim to fix them. Panel animation measurements vary and must be assessed separately from editor gains. More useful follow-up targets are incremental Markdown rendering and reducing broad workspace invalidation during streaming.

The Animation Hitches/GPU capture failed and produced an oversized temporary trace. That specific generated trace was deleted to recover disk space. No reliable GPU percentage, energy measurement, or rendered-frame data was obtained. The CPU capture is useful evidence, but cannot quantify the battery cost of Liquid Glass. Raw Instruments traces are kept local rather than published because they contain machine/process metadata.

The Mac had approximately 3 GB of free disk space during the investigation. Low disk space is a separate system constraint worth addressing, but this investigation does not measure its contribution to the perceived slowdown.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
./scripts/profile.sh
```

The script copies the build to a separate bundle identity and creates an isolated workspace beneath `.build/performance/`. It launches the executable directly; using Instruments `--launch` on this machine incorrectly selected the installed app. Attach Time Profiler to the isolated process if a stack capture is needed. Keep profiling disabled for comparative timing runs.

`CLARA_PROFILE_DIRECTORY` opts into the workload. Without this environment variable, normal application startup is unchanged. The report's checked-in JSON contains synthetic phase metrics only, not user conversations or raw system traces.
