# Debagr Improvement Task Queue

## Iteration Log

| # | Date | Purpose | Commit SHA | Status | Evidence |
|---|------|---------|------------|--------|----------|
| 1 | 2026-11-14 | Baseline capture: build, tests, checks recorded | (pre-change) | Baseline | See below |
| 2 | 2026-11-14 | CLI: add `--json` support to `--version` and `--help` | `1f46cdd` | Verified | 154 tests pass, CLI output verified |

## Active Tasks

| # | Area | Description | Priority | Blocked? |
|---|------|-------------|----------|----------|
| 3 | Deployment | Improve error messaging when device is locked during install | High | No |
| 4 | Documentation | Align README version badge with actual VERSION file | Low | No |
| 5 | CLI | Add `--diagnose` recovery guidance for common failure modes | Medium | No |

## Completed Tasks

| # | Date | Purpose | Commit SHA | Result |
|---|------|---------|------------|--------|
| 1 | 2026-11-14 | Baseline: build, tests (152 pass), release/doc checks verified | — | All green |
| 2 | 2026-11-14 | CLI: `--version --json` and `--help --json` produce structured output; `--version` includes schemaVersion, version string, bundleShortVersion, buildNumber | `1f46cdd` | 154 tests pass (2 new), CLI verified |
