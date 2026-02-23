#!/usr/bin/env bash
# =============================================================================
# generate_transactions.sh
# Runs the PL/SQL transaction generator inside the Oracle container.
# Loops so it can be restarted and runs indefinitely.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[[ -f "$PROJECT_DIR/.env" ]] && { set -a; source "$PROJECT_DIR/.env"; set +a; }

echo "[$(date '+%H:%M:%S')] Starting continuous transaction generation …"
echo "  Oracle container: oracle"
echo "  Schema:           bankdb @ XEPDB1"
echo ""
echo "  Ctrl+C to stop"
echo ""

docker exec -i oracle \
  sqlplus bankdb/"${BANK_SCHEMA_PASSWORD:-BankDB2024!}"@XEPDB1 \
  @/opt/oracle/scripts/startup/05_live_transactions.sql
