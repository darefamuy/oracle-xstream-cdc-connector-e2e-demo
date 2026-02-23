# AB Bank CDC Demo – Troubleshooting Guide

---

## Oracle Won't Start

**Symptom:** `docker compose logs oracle` shows `ORA-04031` or similar memory errors.

**Fix:** Oracle 21c XE requires at least 2 GB RAM for the container.

```bash
# Check how much Docker Desktop has allocated
docker info | grep -i memory

# Increase in Docker Desktop → Settings → Resources → Memory (set to 10 GB+)
```

Also check:
```bash
docker stats oracle --no-stream
```

---

## XStream Connector FAILED – `ORA-01031: insufficient privileges`

The `c##ggadmin` user is missing privileges.

```bash
docker exec -it oracle sqlplus sys/"Oracle21c!"@XE as sysdba <<'EOF'
EXEC DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
  grantee                 => 'c##ggadmin',
  privilege_type          => 'CAPTURE',
  grant_select_privileges => TRUE
);
GRANT CREATE SESSION, SET CONTAINER TO c##ggadmin CONTAINER=ALL;
EOF
```

---

## `libclntsh.so: cannot open shared object file`

The Oracle Instant Client is missing or is the wrong architecture.

1. Verify the directory: `ls -la connect/instantclient/`
2. It must contain `libclntsh.so` (or a symlink to it).
3. Check architecture matches your Docker host:
   - x86-64 Mac / Linux: use `linux.x64` Instant Client
   - Apple Silicon / ARM: use `linux.arm64` Instant Client (via Rosetta)
4. Rebuild the Connect image: `docker compose build connect --no-cache`

---

## Connector Shows `RUNNING` but No Messages in Topics

1. Check XStream Outbound Server is attached:

```bash
docker exec -it oracle sqlplus c##ggadmin/"Confluent12!"@XE
SQL> SELECT SERVER_NAME, STATE FROM V$XSTREAM_OUTBOUND_SERVER;
-- Expected: STATE = "ATTACHED" when connector is running
```

2. If STATE is `WAITING FOR CLIENT`:

```bash
# Restart the CDC connector
curl -s -X POST http://localhost:8083/connectors/ABBANK-XSTREAM-CDC/restart
```

3. Check the Capture process is running:

```bash
SQL> SELECT CAPTURE_NAME, STATE FROM V$XSTREAM_CAPTURE;
-- Expected: STATE = "CAPTURING CHANGES"
```

---

## `xstreams.jar` ClassNotFoundException

The `xstreams.jar` and `ojdbc8.jar` must be in the connector's `lib/` folder.

```
connect/confluent-hub-components/confluentinc-kafka-connect-oracle-xstream-cdc/lib/
├── kafka-connect-oracle-xstream-cdc-X.X.X.jar
├── ojdbc8.jar          ← copy from Instant Client zip
└── xstreams.jar        ← copy from Instant Client zip
```

These JARs are included in the Oracle Instant Client download (`instantclient-jdbc-linux.*.zip`).

Rebuild after adding:

```bash
docker compose build connect --no-cache
docker compose up -d connect
```

---

## Connect Container Won't Start (Memory)

Reduce heap size in `docker-compose.yml`:

```yaml
KAFKA_OPTS: >-
  -Xmx2G -Xms1G
```

---

## Complete Reset

```bash
docker compose down -v              # stop + remove all volumes
docker rmi abbank-connect:latest    # remove built image
docker compose build                # rebuild
docker compose up -d                # start fresh
```
