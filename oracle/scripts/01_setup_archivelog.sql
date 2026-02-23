-- =============================================================================
-- 01_setup_archivelog.sql
-- Run as: sysdba in CDB (XE)
--
-- IMPORTANT: Archivelog mode is enabled BEFORE this script runs by the shell
-- script 00_enable_archivelog.sh, which performs the required shutdown/mount/
-- archivelog/open cycle. This script only runs post-open DDL.
-- =============================================================================

-- 1. Enable Supplemental Logging (requires archivelog mode to already be on)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- 2. Enable GoldenGate/XStream replication parameter
ALTER SYSTEM SET enable_goldengate_replication = TRUE SCOPE=BOTH;

-- 3. Streams pool (XE SGA cap is 2 GB — keep it modest)
ALTER SYSTEM SET streams_pool_size   = 256M SCOPE=SPFILE;
ALTER SYSTEM SET pga_aggregate_limit = 2048M SCOPE=BOTH;

-- 4. Create XStream admin user in CDB (c## = CDB-wide common user, required in 21c)
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = 'C##GGADMIN';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE
      'CREATE USER c##ggadmin IDENTIFIED BY "Confluent12!" ' ||
      'DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP';
  END IF;
END;
/

-- 5. Grant XStream capture privilege via the supplied package
BEGIN
  DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
    grantee                 => 'c##ggadmin',
    privilege_type          => 'CAPTURE',
    grant_select_privileges => TRUE
  );
END;
/

GRANT CREATE SESSION, SET CONTAINER  TO c##ggadmin CONTAINER=ALL;
GRANT SELECT ANY DICTIONARY          TO c##ggadmin CONTAINER=ALL;
GRANT SELECT ANY TABLE               TO c##ggadmin CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE            TO c##ggadmin CONTAINER=ALL;
GRANT UNLIMITED TABLESPACE           TO c##ggadmin;

-- Roles required by the Confluent XStream CDC connector pre-flight checks
GRANT SELECT_CATALOG_ROLE            TO c##ggadmin CONTAINER=ALL;
GRANT EXECUTE_CATALOG_ROLE           TO c##ggadmin CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION         TO c##ggadmin CONTAINER=ALL;

-- 6. Resize redo logs: default XE groups are 200 MB, grow them to 512 MB.
--    Switch away from CURRENT group before attempting drops.
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
  EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
  EXECUTE IMMEDIATE 'ALTER SYSTEM CHECKPOINT';
END;
/

ALTER DATABASE ADD LOGFILE GROUP 4 ('/opt/oracle/oradata/XE/redo04.log') SIZE 512M;
ALTER DATABASE ADD LOGFILE GROUP 5 ('/opt/oracle/oradata/XE/redo05.log') SIZE 512M;
ALTER DATABASE ADD LOGFILE GROUP 6 ('/opt/oracle/oradata/XE/redo06.log') SIZE 512M;

BEGIN
  FOR r IN (SELECT group# FROM v$log WHERE bytes < 400*1024*1024 AND status != 'CURRENT') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER DATABASE DROP LOGFILE GROUP ' || r.group#;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Skipping group ' || r.group# || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;

PROMPT ==========================================
PROMPT Step 1 complete: supplemental logging + XStream admin + redo logs
PROMPT ==========================================