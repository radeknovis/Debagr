# Debagr Improvement Task Queue

## Iteration Log

| # | Date | Purpose | Commit SHA | Status | Evidence |
|---|------|---------|------------|--------|----------|
| 1 | 2026-11-14 | Baseline capture: build, tests, checks recorded | (pre-change) | Baseline | See below |
| 2 | 2026-11-14 | CLI: add `--json` support to `--version` and `--help` | `1f46cdd` | Verified | 154 tests pass, CLI output verified |
| 3 | 2026-11-14 | CLI: improve --device missing error with actionable recovery | `bcbd788` | Verified | 154 tests pass, CLI output verified |
| 4 | 2026-11-14 | CLI: add structured recovery steps to --diagnose output | `e41fb8a` | Verified | 155 tests pass, JSON output verified |

## Active Tasks

| # | Area | Description | Priority | Blocked? |
|---|------|-------------|----------|----------|
| 5 | CLI | Add --diagnose guidance for common deployment failure modes | Medium | No |
| 6 | Deployment | Improve `--deploy-app` error when .app path is invalid | High | No |
| 7 | Documentation | Align README version badge with actual VERSION file | Low | No |

## Completed Tasks

| # | Date | Purpose | Commit SHA | Result |
|---|------|---------|------------|--------|
| 1 | 2026-11-14 | Baseline: build, tests (152 pass), release/doc checks verified | — | All green |
| 2 | 2026-11-14 | CLI: `--version --json` and `--help --json` produce structured output; `--version` includes schemaVersion, version string, bundleShortVersion, buildNumber | `1f46cdd` | 154 tests pass (2 new), CLI verified |
| 3 | 2026-11-14 | CLI: `CLIError.missingDevice` → dedicated error code `missing_device` with recovery 'Provide --device <UDID>. List available devices with --devices --json.' Generic error message for all commands. | `bcbd788` | 154 tests pass (1 updated), CLI verified |
| 4 | 2026-11-14 | CLI: `--diagnose` JSON output includes `recoverySteps` array with actionable steps per failed check; falls back to underlying error recovery when no checks failed. | `e41fb8a` | 155 tests pass (3 new/updated), JSON verified |
