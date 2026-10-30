#!/usr/bin/env bash
set -euo pipefail

# mstack Append-Only Audit & Evidence Logger
# Usage: ./mobile-migration-tools/scripts/log-evidence.sh <step> <principles> <decision> <command> <evidence_path> <status>

AUDIT_FILE="${MSTACK_AUDIT_FILE:-.mstack/audit.tsv}"
mkdir -p "$(dirname "$AUDIT_FILE")"

sanitize() {
  local s="${1:-}"
  s="${s//$'\t'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  if [[ "$s" =~ ^[=+\-@] ]]; then
    s="'$s"
  fi
  printf '%s' "$s"
}

if [[ ! -f "$AUDIT_FILE" ]]; then
  printf 'ts_utc\tstep\tprinciples_applied\tdecision_or_action\tcommand_run\tevidence_path\tstatus\n' > "$AUDIT_FILE"
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STEP=$(sanitize "${1:-unknown}")
PRINCIPLES=$(sanitize "${2:-none}")
DECISION=$(sanitize "${3:-}")
CMD_RUN=$(sanitize "${4:-}")
EVIDENCE=$(sanitize "${5:-}")
STATUS=$(sanitize "${6:-OPEN}")

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS" "$STEP" "$PRINCIPLES" "$DECISION" "$CMD_RUN" "$EVIDENCE" "$STATUS" >> "$AUDIT_FILE"
