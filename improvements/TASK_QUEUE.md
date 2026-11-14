# Debagr Improvement Task Queue

## Iteration Log

| # | Date | Purpose | Commit SHA | Status | Evidence |
|---|------|---------|------------|--------|----------|
| 1 | 2026-11-14 | Baseline capture: build, tests, checks recorded | (pre-change) | Baseline | All green |
| 2 | 2026-11-14 | CLI: add `--json` support to `--version` and `--help` | `1f46cdd` | Verified | 154 tests pass |
| 3 | 2026-11-14 | CLI: improve --device missing error with actionable recovery | `bcbd788` | Verified | 154 tests pass |
| 4 | 2026-11-14 | CLI: add structured recovery steps to --diagnose output | `e41fb8a` | Verified | 155 tests pass |
| 5 | 2026-11-14 | Deploy: include app path in invalid app error messages | `ce0239f` | Verified | 155 tests pass |
| 6 | 2026-11-14 | Docs: align README version badge with actual VERSION file | `78e7714` | Verified | Doc checks pass |
| 7 | 2026-11-14 | CLI: improve --launch-app error message with example bundle ID | `7dc9be0` | Verified | 155 tests pass |
| 8 | 2026-11-14 | CLI: add deploymentMode to --status and --diagnose output | `bb6a433` | Verified | 155 tests pass |
| 9 | 2026-11-14 | CLI: include receipt path in --deploy-app JSON output | `2beb70a` | Verified | 155 tests pass |
| 10 | 2026-11-14 | CLI: improve --diagnose recovery guidance for common failure modes | `00ed022` | Verified | 155 tests pass |
| 11 | 2026-11-14 | Tests: add regression tests for --help --json and deploymentMode JSON fields | `d614246` | Verified | 157 tests pass |
| 12 | 2026-11-14 | CLI: include developerToolsAvailable in --devices JSON output | `f3ceb4d` | Verified | 157 tests pass |

## Active Tasks

| # | Area | Description | Priority | Blocked? |
|---|------|-------------|----------|----------|
| 13 | CLI | Add `--installed-apps` confirmation during `--deploy-app --launch` to verify bundle ID matches | Medium | No |
| 14 | Tests | Add integration tests for new CLI JSON fields (deploymentMode, recoverySteps, receiptPath) | Low | No |

## Completed Tasks

| # | Date | Purpose | Commit SHA | Result |
|---|------|---------|------------|--------|
| 1 | 2026-11-14 | Baseline: build, tests (152 pass), release/doc checks verified | — | All green |
| 2 | 2026-11-14 | CLI: `--version --json` and `--help --json` produce structured output; `--version` includes schemaVersion, version string, bundleShortVersion, buildNumber | `1f46cdd` | 154 tests pass (2 new), CLI verified |
| 3 | 2026-11-14 | CLI: `CLIError.missingDevice` → dedicated error code `missing_device` with recovery 'Provide --device <UDID>. List available devices with --devices --json.' Generic message for all commands. | `bcbd788` | 154 tests pass (1 updated), CLI verified |
| 4 | 2026-11-14 | CLI: `--diagnose` JSON output includes `recoverySteps` array with actionable steps per failed check; falls back to underlying error recovery when no checks failed. | `e41fb8a` | 155 tests pass (3 new/updated), JSON verified |
| 5 | 2026-11-14 | Deploy: include app path in invalid app error messages for better debugging | `ce0239f` | 155 tests pass, CLI verified |
| 6 | 2026-11-14 | Docs: align README version badge from '0.3.0_preview' to '0.3.0' matching VERSION file | `78e7714` | Doc checks pass |
| 7 | 2026-11-14 | CLI: improve --launch-app error message with example bundle ID format | `7dc9be0` | 155 tests pass, CLI verified |
| 8 | 2026-11-14 | CLI: add deploymentMode ('local'/'remote') to --status and --diagnose JSON output | `bb6a433` | 155 tests pass, CLI verified |
| 9 | 2026-11-14 | CLI: include receipt path in --deploy-app JSON output for agents to reference deployment history | `2beb70a` | 155 tests pass, CLI verified |
| 10 | 2026-11-14 | CLI: improve --diagnose recovery guidance for deviceLocked and timedOut failures | `00ed022` | 155 tests pass, CLI verified |
| 11 | 2026-11-14 | Tests: add regression tests for --help --json and deploymentMode JSON fields | `d614246` | 157 tests pass (2 new), CLI verified |
| 12 | 2026-11-14 | CLI: include developerToolsAvailable in --devices JSON output for pre-flight checks without separate --diagnose call | `f3ceb4d` | 157 tests pass, CLI verified |
