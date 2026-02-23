#!/usr/bin/env bash
# =============================================================================
# deploy_connectors.sh
# Deploy, check, pause, resume, or delete connectors via REST API.
#
# Usage:
#   ./scripts/deploy_connectors.sh deploy   # deploy the CDC connector
#   ./scripts/deploy_connectors.sh status   # show status of the connector
#   ./scripts/deploy_connectors.sh pause    # pause CDC connector
#   ./scripts/deploy_connectors.sh resume   # resume CDC connector
#   ./scripts/deploy_connectors.sh delete   # delete the connector
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CDC_NAME="ABBANK-XSTREAM-CDC"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }

case "${1:-status}" in

  deploy)
    log "Deploying Oracle XStream CDC Source Connector …"
    curl -s -X POST -H 'Content-Type: application/json' \
      --data "@$PROJECT_DIR/connect/connectors/oracle-xstream-cdc.json" \
      "$CONNECT_URL/connectors" | jq .
    ;;

  status)
    log "=== CDC Source Connector status ==="
    curl -s "$CONNECT_URL/connectors/$CDC_NAME/status" | jq .
    echo ""
    log "=== All connectors ==="
    curl -s "$CONNECT_URL/connectors?expand=status" | jq '.[].status.connector'
    ;;

  pause)
    log "Pausing CDC connector …"
    curl -s -X PUT "$CONNECT_URL/connectors/$CDC_NAME/pause" | jq .
    ;;

  resume)
    log "Resuming CDC connector …"
    curl -s -X PUT "$CONNECT_URL/connectors/$CDC_NAME/resume" | jq .
    ;;

  stop)
    log "Stopping CDC connector (KIP-875) …"
    curl -s -X PUT "$CONNECT_URL/connectors/$CDC_NAME/stop" | jq .
    ;;

  restart)
    log "Restarting CDC connector …"
    curl -s -X POST "$CONNECT_URL/connectors/$CDC_NAME/restart" | jq .
    ;;

  delete)
    warn "Deleting CDC connector …"
    curl -s -X DELETE "$CONNECT_URL/connectors/$CDC_NAME" | jq .
    ;;

  logs)
    docker compose logs -f connect
    ;;

  debug)
    log "Setting CDC connector log level to DEBUG …"
    curl -s -X PUT -H 'Content-Type: application/json' \
      -d '{"level":"DEBUG"}' \
      "$CONNECT_URL/admin/loggers/io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector" | jq .
    ;;

  *)
    echo "Usage: $0 {deploy|status|pause|resume|stop|restart|delete|logs|debug}"
    exit 1
    ;;
esac
