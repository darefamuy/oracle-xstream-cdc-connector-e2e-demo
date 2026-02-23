#!/bin/bash
# =============================================================================
# 00_enable_archivelog.sh
#
# Enables Oracle ARCHIVELOG mode before the SQL init scripts run.
#
# WHY A SHELL SCRIPT AND NOT SQL:
#   Enabling archivelog requires: SHUTDOWN → STARTUP MOUNT → ALTER DATABASE
#   ARCHIVELOG → OPEN. Each phase terminates the current connection, so it
#   cannot be done inside a single SQL*Plus session.
#
# WHY LOCAL (OS) AUTH AFTER SHUTDOWN:
#   After SHUTDOWN the listener is also stopped, so TNS connect strings like
#   sys/pass@XE will fail with ORA-12514. We use "/ as sysdba" (local bequeath
#   connection via ORACLE_SID) for every phase — this bypasses the listener
#   completely and works even when Oracle is in MOUNT state.
#
# IDEMPOTENT:
#   Checks if archivelog is already on and exits early if so.
# =============================================================================

set -euo pipefail

export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=/opt/oracle/product/21c/dbhomeXE
export ORACLE_SID="${ORACLE_SID:-XE}"
export PATH=$ORACLE_HOME/bin:$PATH

# Local OS-auth connection — works without listener, even in MOUNT state
LOCAL_CONN="/ as sysdba"

echo "==> [00_enable_archivelog] Checking ARCHIVELOG mode ..."

# ── Check current log mode ────────────────────────────────────────────────────
LOG_MODE=$(sqlplus -s /nolog <<EOF
CONNECT ${LOCAL_CONN}
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 TRIMOUT ON
SELECT LOG_MODE FROM V\$DATABASE;
EXIT;
EOF
)
LOG_MODE=$(echo "$LOG_MODE" | tr -d '[:space:]')

if [[ "$LOG_MODE" == "ARCHIVELOG" ]]; then
  echo "==> [00_enable_archivelog] Already in ARCHIVELOG mode — skipping."
  exit 0
fi

echo "==> [00_enable_archivelog] Currently in ${LOG_MODE} mode."
echo "==> [00_enable_archivelog] Starting SHUTDOWN → MOUNT → ARCHIVELOG → OPEN cycle ..."

# ── Phase 1: Shutdown ─────────────────────────────────────────────────────────
echo "==> [00_enable_archivelog] Phase 1: SHUTDOWN IMMEDIATE ..."
sqlplus -s /nolog <<EOF
CONNECT ${LOCAL_CONN}
SHUTDOWN IMMEDIATE;
EXIT;
EOF

# Wait for the instance to fully stop before attempting STARTUP MOUNT.
# On ARM64 Rosetta emulation this can take longer than on native hardware.
echo "==> [00_enable_archivelog] Waiting for instance to stop ..."
for i in $(seq 1 30); do
  # pmon is the last background process to die; once it's gone, Oracle is down
  if ! pgrep -x "ora_pmon_${ORACLE_SID}" > /dev/null 2>&1; then
    echo "==> [00_enable_archivelog] Instance stopped after ${i}s."
    break
  fi
  sleep 1
done
# Extra buffer — filesystem sync
sleep 3

# ── Phase 2: Startup MOUNT ───────────────────────────────────────────────────
echo "==> [00_enable_archivelog] Phase 2: STARTUP MOUNT ..."
sqlplus -s /nolog <<EOF
CONNECT ${LOCAL_CONN}
STARTUP MOUNT;
EXIT;
EOF

sleep 2

# ── Phase 3: Enable archivelog + open ────────────────────────────────────────
echo "==> [00_enable_archivelog] Phase 3: ALTER DATABASE ARCHIVELOG + OPEN ..."
sqlplus -s /nolog <<EOF
CONNECT ${LOCAL_CONN}
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
EXIT;
EOF

echo "==> [00_enable_archivelog] Database opened."
sleep 2

# ── Verify ────────────────────────────────────────────────────────────────────
# Use local auth again — listener may still be registering after OPEN
LOG_MODE_AFTER=$(sqlplus -s /nolog <<EOF
CONNECT ${LOCAL_CONN}
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 TRIMOUT ON
SELECT LOG_MODE FROM V\$DATABASE;
EXIT;
EOF
)
LOG_MODE_AFTER=$(echo "$LOG_MODE_AFTER" | tr -d '[:space:]')

if [[ "$LOG_MODE_AFTER" != "ARCHIVELOG" ]]; then
  echo "ERROR: [00_enable_archivelog] Failed to enable ARCHIVELOG mode! Got: ${LOG_MODE_AFTER}"
  exit 1
fi

echo "==> [00_enable_archivelog] Verified: LOG_MODE = ARCHIVELOG"
echo "==> [00_enable_archivelog] Done."
