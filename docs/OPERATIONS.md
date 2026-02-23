# AB Bank CDC Demo – Operations Runbook

This document covers common operational tasks for the demo environment.

---

## Connector Management

### Check all connector statuses

```bash
curl -s 'http://localhost:8083/connectors?expand=status' | \
  jq 'to_entries[] | {name: .key, state: .value.status.connector.state}'
```

### Pause / Resume (buffer in Oracle redo logs)

```bash
# Pause – CDC connector stops consuming but Oracle captures all changes in redo logs
curl -s -X PUT http://localhost:8083/connectors/ABBANK-XSTREAM-CDC/pause

# Resume – connector picks up exactly where it left off (no data loss)
curl -s -X PUT http://localhost:8083/connectors/ABBANK-XSTREAM-CDC/resume
```

### Stop / Restart (KIP-875, CP 7.6+)

```bash
curl -s -X PUT  http://localhost:8083/connectors/ABBANK-XSTREAM-CDC/stop
curl -s -X POST http://localhost:8083/connectors/ABBANK-XSTREAM-CDC/restart
```

### Update connector config

Edit `connect/connectors/oracle-xstream-cdc.json` then:

```bash
curl -s -X PUT -H 'Content-Type: application/json' \
  --data @connect/connectors/oracle-xstream-cdc.json \
  http://localhost:8083/connectors/ABBANK-XSTREAM-CDC/config | jq .
```

---

## Oracle XStream Health

```bash
# Attach a SQL*Plus session as XStream admin
docker exec -it oracle sqlplus c##ggadmin/"Confluent12!"@XE

-- Quick health check
SELECT SERVER_NAME, STATE FROM V$XSTREAM_OUTBOUND_SERVER;
SELECT CAPTURE_NAME, ROUND((SYSDATE-CAPTURE_MESSAGE_CREATE_TIME)*86400,2) LAG_SEC FROM V$XSTREAM_CAPTURE;

-- Is connector attached?
SELECT CAPTURE_NAME, STATUS FROM ALL_XSTREAM_OUTBOUND WHERE SERVER_NAME='XOUT';
```

### Drop and recreate the Outbound Server

If you need a clean restart (e.g. after wiping Oracle volumes):

```bash
docker exec -it oracle sqlplus c##ggadmin/"Confluent12!"@XE

SQL> EXECUTE DBMS_XSTREAM_ADM.DROP_OUTBOUND('XOUT');
-- Then re-run the setup script:
SQL> @/opt/oracle/scripts/startup/03_create_xstream_outbound.sql
```

---

## Kafka Topics

```bash
# List all topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list

# Describe a topic
docker exec broker kafka-topics --bootstrap-server broker:29092 \
  --describe --topic XEPDB1.BANKDB.TRANSACTIONS

# Consume latest messages from the transactions topic
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.BANKDB.TRANSACTIONS \
  --from-beginning --max-messages 5
```

---

## Full Demo Reset

To start the demo from scratch without recreating the Oracle database:

```bash
# 1. Delete connectors
./scripts/deploy_connectors.sh delete

# 2. Delete Kafka topics (offset reset)
for topic in XEPDB1.BANKDB.CUSTOMERS XEPDB1.BANKDB.ACCOUNTS \
             XEPDB1.BANKDB.TRANSACTIONS XEPDB1.BANKDB.TRANSACTION_AUDIT \
             __cflt-oracle-heartbeat.XEPDB1 __orcl-schema-changes.XEPDB1; do
  docker exec broker kafka-topics --bootstrap-server broker:29092 --delete --topic "$topic"
done

# 3. Drop and recreate XStream Outbound Server
docker exec -it oracle sqlplus c##ggadmin/"Confluent12!"@XE <<'EOF'
EXECUTE DBMS_XSTREAM_ADM.DROP_OUTBOUND('XOUT');
@/opt/oracle/scripts/startup/03_create_xstream_outbound.sql
EOF

# 4. Redeploy connectors
./scripts/deploy_connectors.sh deploy
```

---

## Logs

```bash
docker compose logs -f oracle          # Oracle startup + CDC activity
docker compose logs -f connect         # Connector logs
docker compose logs -f broker          # Kafka broker
```
