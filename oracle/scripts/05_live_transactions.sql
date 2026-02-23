-- =============================================================================
-- 05_live_transactions.sql
-- Run as: sysdba (Oracle Docker init hook always connects as sysdba in CDB)
--
-- Switches to XEPDB1 and uses fully-qualified bankdb.<table> names.
--
-- Fix: rand_channel() is a locally-declared function and cannot be called
-- directly inside a SQL statement (PLS-00231). It is now called in a PL/SQL
-- assignment first and stored in v_channel, which is then used in INSERT.
-- =============================================================================

ALTER SESSION SET CONTAINER = XEPDB1;

DECLARE
  -- ── config ────────────────────────────────────────────────────────────────
  c_iterations CONSTANT PLS_INTEGER := 10000;
  c_sleep_sec  CONSTANT NUMBER      := 0.5;

  -- ── working vars ──────────────────────────────────────────────────────────
  v_account_id  NUMBER;
  v_account2_id NUMBER;
  v_txn_id      NUMBER;
  v_amount      NUMBER;
  v_bal_before  NUMBER;
  v_bal_after   NUMBER;
  v_type        VARCHAR2(20);
  v_ref         VARCHAR2(30);
  v_channel     VARCHAR2(10);   -- ← holds rand_channel() result before INSERT
  v_roll        NUMBER;

  -- ── helper: random channel ────────────────────────────────────────────────
  -- NOTE: Called only from PL/SQL assignments (v_channel := rand_channel()),
  --       never directly inside a SQL statement, to avoid PLS-00231.
  FUNCTION rand_channel RETURN VARCHAR2 IS
    v_ch SYS.ODCIVARCHAR2LIST :=
      SYS.ODCIVARCHAR2LIST('MOBILE','INTERNET','ATM','POS','BRANCH','USSD','API');
  BEGIN
    RETURN v_ch(TRUNC(DBMS_RANDOM.VALUE(1, v_ch.COUNT + 1)));
  END rand_channel;

BEGIN
  FOR i IN 1 .. c_iterations LOOP

    v_roll := DBMS_RANDOM.VALUE(0, 100);

    -- ── Pick a random active account ─────────────────────────────────────────
    SELECT account_id, balance
    INTO   v_account_id, v_bal_before
    FROM   (
      SELECT account_id, balance
      FROM   bankdb.accounts
      WHERE  account_status = 'ACTIVE'
      ORDER BY DBMS_RANDOM.VALUE
    )
    WHERE ROWNUM = 1;

    v_ref     := 'ABB' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3');
    v_channel := rand_channel();   -- ← assign in PL/SQL, use variable in SQL

    -- ── 70% : Simple CREDIT or DEBIT ─────────────────────────────────────────
    IF v_roll < 70 THEN

      v_amount := ROUND(DBMS_RANDOM.VALUE(100, 500000), 4);
      v_type   := CASE WHEN MOD(i, 3) = 0 THEN 'CREDIT' ELSE 'DEBIT' END;

      IF v_type = 'CREDIT' THEN
        v_bal_after := v_bal_before + v_amount;
      ELSE
        v_amount    := LEAST(v_amount, GREATEST(v_bal_before, 0));
        v_bal_after := v_bal_before - v_amount;
      END IF;

      INSERT INTO bankdb.transactions (
        account_id, transaction_ref, transaction_type,
        amount, currency, balance_before, balance_after,
        description, channel, transaction_status, completed_at)
      VALUES (
        v_account_id, v_ref, v_type,
        v_amount, 'NGN', v_bal_before, v_bal_after,
        v_type || ' transaction #' || i,
        v_channel, 'COMPLETED', SYSTIMESTAMP)   -- ← variable, not function call
      RETURNING transaction_id INTO v_txn_id;

      UPDATE bankdb.accounts
      SET    balance = v_bal_after, available_balance = v_bal_after
      WHERE  account_id = v_account_id;

    -- ── 15% : TRANSFER ────────────────────────────────────────────────────────
    ELSIF v_roll < 85 THEN

      SELECT account_id
      INTO   v_account2_id
      FROM   (
        SELECT account_id
        FROM   bankdb.accounts
        WHERE  account_status = 'ACTIVE'
        AND    account_id <> v_account_id
        ORDER BY DBMS_RANDOM.VALUE
      )
      WHERE ROWNUM = 1;

      v_amount    := ROUND(DBMS_RANDOM.VALUE(500, 200000), 4);
      v_bal_after := v_bal_before - v_amount;

      -- Outgoing leg
      INSERT INTO bankdb.transactions (
        account_id, transaction_ref, transaction_type,
        amount, currency, balance_before, balance_after,
        description, channel, transaction_status, completed_at)
      VALUES (
        v_account_id, v_ref, 'TRANSFER_OUT',
        v_amount, 'NGN', v_bal_before, v_bal_after,
        'Transfer out to account ' || v_account2_id,
        v_channel, 'COMPLETED', SYSTIMESTAMP)   -- ← variable
      RETURNING transaction_id INTO v_txn_id;

      UPDATE bankdb.accounts
      SET    balance = v_bal_after
      WHERE  account_id = v_account_id;

      -- Incoming leg
      INSERT INTO bankdb.transactions (
        account_id, transaction_ref, transaction_type,
        amount, currency, balance_before, balance_after,
        description, channel, transaction_status, completed_at)
      VALUES (
        v_account2_id, v_ref || 'IN', 'TRANSFER_IN',
        v_amount, 'NGN', NULL, NULL,
        'Transfer in from account ' || v_account_id,
        'API', 'COMPLETED', SYSTIMESTAMP);

    -- ── 10% : Fee or Interest ─────────────────────────────────────────────────
    ELSIF v_roll < 95 THEN

      v_amount    := ROUND(DBMS_RANDOM.VALUE(50, 5000), 4);
      v_type      := CASE WHEN MOD(i, 2) = 0 THEN 'FEE' ELSE 'INTEREST' END;
      v_bal_after := CASE v_type
                       WHEN 'FEE' THEN v_bal_before - v_amount
                       ELSE            v_bal_before + v_amount
                     END;

      INSERT INTO bankdb.transactions (
        account_id, transaction_ref, transaction_type,
        amount, currency, balance_before, balance_after,
        description, channel, transaction_status, completed_at)
      VALUES (
        v_account_id, v_ref, v_type,
        v_amount, 'NGN', v_bal_before, v_bal_after,
        INITCAP(v_type) || ' applied – period ' || i,
        'API', 'COMPLETED', SYSTIMESTAMP)
      RETURNING transaction_id INTO v_txn_id;

      UPDATE bankdb.accounts
      SET    balance = v_bal_after
      WHERE  account_id = v_account_id;

    -- ── 5% : High-value credit → audit flag ──────────────────────────────────
    ELSE

      v_amount    := ROUND(DBMS_RANDOM.VALUE(500000, 5000000), 4);
      v_bal_after := v_bal_before + v_amount;

      INSERT INTO bankdb.transactions (
        account_id, transaction_ref, transaction_type,
        amount, currency, balance_before, balance_after,
        description, channel, transaction_status, completed_at)
      VALUES (
        v_account_id, v_ref, 'CREDIT',
        v_amount, 'NGN', v_bal_before, v_bal_after,
        'High-value credit – compliance review required',
        'BRANCH', 'COMPLETED', SYSTIMESTAMP)
      RETURNING transaction_id INTO v_txn_id;

      UPDATE bankdb.accounts
      SET    balance = v_bal_after
      WHERE  account_id = v_account_id;

      INSERT INTO bankdb.transaction_audit (
        transaction_id, audit_action, flagged_reason, notes)
      VALUES (
        v_txn_id, 'FLAGGED',
        'Amount exceeds NGN 500,000 threshold',
        'Auto-flagged by rule engine at iteration ' || i);

    END IF;

    COMMIT;

    -- Occasionally update a customer phone (generates UPDATE CDC events)
    IF MOD(i, 50) = 0 THEN
      UPDATE bankdb.customers
      SET    phone = '+2348099' || LPAD(TRUNC(DBMS_RANDOM.VALUE(100000, 999999)), 6, '0')
      WHERE  customer_id = (
        SELECT customer_id FROM bankdb.customers
        ORDER BY DBMS_RANDOM.VALUE FETCH FIRST 1 ROWS ONLY);
      COMMIT;
    END IF;

    -- Occasionally toggle an account status (generates UPDATE CDC events)
    IF MOD(i, 200) = 0 THEN
      UPDATE bankdb.accounts
      SET    account_status = CASE account_status
                                WHEN 'ACTIVE' THEN 'DORMANT'
                                ELSE 'ACTIVE'
                              END
      WHERE  account_id = (
        SELECT account_id FROM bankdb.accounts
        ORDER BY DBMS_RANDOM.VALUE FETCH FIRST 1 ROWS ONLY);
      COMMIT;
    END IF;

    DBMS_SESSION.SLEEP(c_sleep_sec);

  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Generated ' || c_iterations || ' transactions.');
END;
/