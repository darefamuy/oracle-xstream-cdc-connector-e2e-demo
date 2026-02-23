#!/usr/bin/env bash
# =============================================================================
# demo.sh – Full end-to-end AB Bank CDC demo runner
#
# Usage:  ./scripts/demo.sh
#
# What it does:
#   1. Validates prerequisites
#   2. Waits for all Docker services to be healthy
#   3. Verifies the XStream Outbound Server exists in Oracle
#   4. Deploys the Oracle XStream CDC Source Connector
#   5. Starts the transaction generator
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colours
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠  $*${NC}"; }
die()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}"; exit 1; }

# ── Load .env if present ──────────────────────────────────────────────────────
if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

# ── 1. Prerequisite checks ────────────────────────────────────────────────────
log "=== Step 1: Checking prerequisites ==="

for cmd in docker curl jq; do
  command -v "$cmd" &>/dev/null || die "'$cmd' not found. Please install it."
done

CONNECTOR_DIR="$PROJECT_DIR/connect/confluent-hub-components"
if [[ ! -d "$CONNECTOR_DIR" ]] || [[ -z "$(ls -A "$CONNECTOR_DIR" 2>/dev/null)" ]]; then
  die "Connector not found at $CONNECTOR_DIR\n  See README.md §2 for instructions."
fi

IC_DIR="$PROJECT_DIR/connect/instantclient"
if [[ ! -d "$IC_DIR" ]] || [[ -z "$(ls -A "$IC_DIR" 2>/dev/null)" ]]; then
  die "Oracle Instant Client not found at $IC_DIR\n  See README.md §2 for instructions."
fi

log "Prerequisites OK."

# ── 2. Wait for services ──────────────────────────────────────────────────────
log "=== Step 2: Waiting for Docker services to be healthy ==="

wait_for_http() {
  local name="$1" url="$2" retries="${3:-60}" interval="${4:-5}"
  local count=0
  echo -n "  Waiting for $name ($url)"
  while ! curl -sf "$url" &>/dev/null; do
    if (( count >= retries )); then
      echo ""; die "Timed out waiting for $name"
    fi
    echo -n "."; sleep "$interval"; (( count++ ))
  done
  echo " ✓"
}

wait_for_http "Schema Registry" "http://localhost:${SCHEMA_REGISTRY_PORT:-8081}/subjects" 60 5
wait_for_http "Kafka Connect"   "$CONNECT_URL/"                                           60 5

log "All services healthy."

# ── 3. XStream Outbound Server ────────────────────────────────────────────────
log "=== Step 3: Verifying XStream Outbound Server in Oracle ==="

# Query using local OS auth (/ as sysdba) piped via heredoc into docker exec -i.
# This avoids all nested shell quoting issues — the heredoc delivers the SQL
# verbatim with no escaping required, and local auth works without a listener.
OUTBOUND_CHECK=$(docker exec -i oracle sqlplus -s "/ as sysdba" << 'SQLEOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 TRIMOUT ON VERIFY OFF
ALTER SESSION SET CONTAINER = CDB$ROOT;
SELECT COUNT(*) FROM ALL_XSTREAM_OUTBOUND WHERE SERVER_NAME = 'XOUT';
EXIT;
SQLEOF
)

# Strip all whitespace so we get a bare number like "1" or "0"
OUTBOUND_COUNT=$(echo "$OUTBOUND_CHECK" | tr -d '[:space:]')

if [[ -z "$OUTBOUND_COUNT" ]] || [[ "$OUTBOUND_COUNT" == "0" ]]; then
  warn "XStream Outbound Server XOUT not found – running setup script ..."
  docker exec -i oracle sqlplus "/ as sysdba" \
    @/opt/oracle/scripts/startup/03_create_xstream_outbound.sql \
    || warn "XStream setup returned non-zero – check: docker compose logs oracle"
else
  log "XStream Outbound Server XOUT is present."
fi

# ── helper: deploy a connector if it does not already exist ──────────────────
# Uses curl -s (not -sf) so a 404 response body is captured rather than
# treated as a fatal error. set -e would otherwise kill the script the moment
# curl returns non-zero inside a $(...) assignment.
connector_exists() {
  local name="$1"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "$CONNECT_URL/connectors/$name")
  [[ "$http_code" == "200" ]]
}

deploy_connector() {
  local name="$1" config_file="$2"
  if connector_exists "$name"; then
    warn "Connector $name already exists – skipping create."
    return 0
  fi
  local result
  result=$(curl -s -X POST -H 'Content-Type: application/json' \
    --data "@$config_file" "$CONNECT_URL/connectors")
  local deployed_name
  deployed_name=$(echo "$result" | jq -r '.name // empty' 2>/dev/null || true)
  if [[ "$deployed_name" != "$name" ]]; then
    die "Failed to deploy $name. Response: $result"
  fi
  log "Connector deployed: $deployed_name"
}

# ── 4. Deploy Oracle XStream CDC Source Connector ────────────────────────────
log "=== Step 4: Deploying Oracle XStream CDC Source Connector ==="

deploy_connector "ABBANK-XSTREAM-CDC" "$PROJECT_DIR/connect/connectors/oracle-xstream-cdc.json"

echo -n "  Waiting for CDC connector to become RUNNING"
for i in $(seq 1 30); do
  STATE=$(curl -s "$CONNECT_URL/connectors/ABBANK-XSTREAM-CDC/status" \
    | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
  if [[ "$STATE" == "RUNNING" ]]; then echo " ✓"; break; fi
  if [[ "$STATE" == "FAILED"  ]]; then
    echo ""
    curl -s "$CONNECT_URL/connectors/ABBANK-XSTREAM-CDC/status" | jq .
    die "CDC Connector FAILED. Check: docker compose logs connect"
  fi
  echo -n "."; sleep 5
done

# ── 5. Start transaction generator ───────────────────────────────────────────
log "=== Step 5: Starting live transaction generator ==="
log ""
log "  ╔══════════════════════════════════════════════════════╗"
log "  ║  AB Bank CDC Demo is LIVE!                           ║"
log "  ║                                                      ║"
log "  ║  Control Center : http://localhost:9021              ║"
log "  ║  Connect REST   : http://localhost:8083              ║"
log "  ║  Schema Registry: http://localhost:8081              ║"
log "  ║                                                      ║"
log "  ║  Press Ctrl+C to stop transaction generation         ║"
log "  ╚══════════════════════════════════════════════════════╝"
log ""

exec "$SCRIPT_DIR/generate_transactions.sh"
