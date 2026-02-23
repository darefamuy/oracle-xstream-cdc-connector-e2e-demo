-- =============================================================================
-- 03_create_xstream_outbound.sql
-- Run as: c##ggadmin in CDB (XE)
--
-- Creates the Oracle XStream Capture process, Queue, and Outbound Server.
-- The Confluent XStream CDC Source Connector will attach to the outbound
-- server named XOUT and receive LCRs (Logical Change Records) in real time.
-- =============================================================================

-- Connect as XStream admin in the CDB
CONNECT c##ggadmin/"Confluent12!"@XE

DECLARE
  v_tables  DBMS_UTILITY.UNCL_ARRAY;
  v_schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
  -- Tables to capture CDC events for
  v_tables(1) := 'BANKDB.CUSTOMERS';
  v_tables(2) := 'BANKDB.ACCOUNTS';
  v_tables(3) := 'BANKDB.TRANSACTIONS';
  v_tables(4) := 'BANKDB.TRANSACTION_AUDIT';
  v_tables(5) := NULL;             -- sentinel

  v_schemas(1) := 'BANKDB';

  -- Create Outbound Server, Capture Process and Queue in one call
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    capture_name          => 'confluent_xout1',
    server_name           => 'XOUT',
    source_container_name => 'XEPDB1',
    table_names           => v_tables,
    schema_names          => v_schemas,
    comment               => 'AB Bank – Confluent XStream CDC Source Connector'
  );

  -- Checkpoint retention: 1 day (sufficient for a demo; increase in production)
  DBMS_CAPTURE_ADM.ALTER_CAPTURE(
    capture_name              => 'confluent_xout1',
    checkpoint_retention_time => 1
  );

  -- Limit Streams pool SGA usage per process (XE is capped at 2 GB total SGA)
  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'capture',
    streams_name => 'confluent_xout1',
    parameter    => 'max_sga_size',
    value        => '128'          -- MB
  );

  DBMS_XSTREAM_ADM.SET_PARAMETER(
    streams_type => 'apply',
    streams_name => 'XOUT',
    parameter    => 'max_sga_size',
    value        => '128'          -- MB
  );

  DBMS_OUTPUT.PUT_LINE('XStream Outbound Server XOUT created successfully.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/

-- Verify
SELECT SERVER_NAME, STATUS, CAPTURE_NAME
FROM   ALL_XSTREAM_OUTBOUND
WHERE  SERVER_NAME = 'XOUT';

PROMPT ==========================================
PROMPT Step 3 complete: XStream Outbound Server XOUT ready
PROMPT ==========================================
