#!/usr/bin/env bash
# =============================================================================
# xstream_monitor.sh
# Prints a live summary of XStream Capture + Outbound Server stats.
# Run while transactions are flowing to see real-time CDC metrics.
# =============================================================================
set -euo pipefail

XSTREAM_ADMIN="${XSTREAM_ADMIN_USER:-c##ggadmin}"
XSTREAM_PASS="${XSTREAM_ADMIN_PASSWORD:-Confluent12!}"

SQL=$(cat <<'ENDSQL'
SET LINES 200 PAGES 50
SET FEEDBACK OFF

PROMPT ============================================================
PROMPT  XStream Outbound Server Status
PROMPT ============================================================
SELECT SERVER_NAME, STATE
FROM   V$XSTREAM_OUTBOUND_SERVER;

PROMPT
PROMPT ============================================================
PROMPT  Capture Latency (seconds behind source)
PROMPT ============================================================
SELECT CAPTURE_NAME,
       ROUND((SYSDATE - CAPTURE_MESSAGE_CREATE_TIME)*86400, 2) AS LATENCY_SEC
FROM   V$XSTREAM_CAPTURE;

PROMPT
PROMPT ============================================================
PROMPT  Outbound Server Throughput
PROMPT ============================================================
SELECT SERVER_NAME,
       TOTAL_TRANSACTIONS_SENT  AS TXN_SENT,
       TOTAL_MESSAGES_SENT      AS LCRS_SENT,
       ROUND(BYTES_SENT/1024/1024, 2) AS MB_SENT,
       ROUND(ELAPSED_SEND_TIME/100, 1) AS SEND_TIME_SEC
FROM   V$XSTREAM_OUTBOUND_SERVER;

PROMPT
PROMPT ============================================================
PROMPT  Active XStream Sessions
PROMPT ============================================================
COLUMN ACTION FORMAT A30
COLUMN PROCESS FORMAT A10
SELECT ACTION, SID, SERIAL#, PROCESS
FROM   V$SESSION
WHERE  MODULE = 'XStream';

PROMPT
PROMPT ============================================================
PROMPT  SGA Usage
PROMPT ============================================================
SELECT CAPTURE_NAME,
       ROUND(SGA_USED/1024/1024, 2)      AS SGA_USED_MB,
       ROUND(SGA_ALLOCATED/1024/1024, 2) AS SGA_ALLOC_MB,
       TOTAL_MESSAGES_CAPTURED,
       TOTAL_MESSAGES_ENQUEUED
FROM   V$XSTREAM_CAPTURE;

EXIT;
ENDSQL
)

echo ""
echo "─────────────────────────────────────────────────────"
echo "  AB Bank XStream CDC Monitor  ($(date '+%Y-%m-%d %H:%M:%S'))"
echo "─────────────────────────────────────────────────────"

docker exec -i oracle bash -c \
  "echo \"${SQL}\" | sqlplus -s ${XSTREAM_ADMIN}/\"${XSTREAM_PASS}\"@XE"
