#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---check}"

if [[ "$MODE" == "--fix" ]]; then
  echo "Formatting Swift sources with swift format..."
  swift format format --configuration .swift-format --in-place --recursive Sources Tests Package.swift
elif [[ "$MODE" == "--check" ]]; then
  echo "Checking Swift formatting with swift format lint..."
  swift format lint --configuration .swift-format --strict --recursive Sources Tests Package.swift
else
  echo "Usage: $0 [--check|--fix]" >&2
  exit 2
fi
