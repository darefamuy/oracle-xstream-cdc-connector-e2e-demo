-- =============================================================================
-- 02_create_schema.sql
-- Run as: sysdba (script switches to XEPDB1 for the DDL)
--
-- Creates the AB Bank application schema (BANKDB) and all tables that will
-- be captured by the XStream CDC connector.
-- =============================================================================

-- Switch into the pluggable database
ALTER SESSION SET CONTAINER = XEPDB1;

-- Create application user
CREATE USER bankdb IDENTIFIED BY "BankDB2024!"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP;

GRANT CONNECT, RESOURCE, CREATE SESSION TO bankdb;
GRANT CREATE TABLE, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER TO bankdb;
ALTER USER bankdb QUOTA UNLIMITED ON USERS;

-- ============================================================
-- Table 1: CUSTOMERS
-- ============================================================
CREATE TABLE bankdb.customers (
  customer_id      NUMBER(10)     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name       VARCHAR2(100)  NOT NULL,
  last_name        VARCHAR2(100)  NOT NULL,
  email            VARCHAR2(255)  UNIQUE NOT NULL,
  phone            VARCHAR2(20),
  date_of_birth    DATE,
  national_id      VARCHAR2(50),
  address_line1    VARCHAR2(255),
  address_line2    VARCHAR2(255),
  city             VARCHAR2(100),
  country          VARCHAR2(100)  DEFAULT 'Nigeria',
  customer_status  VARCHAR2(20)   DEFAULT 'ACTIVE'
                   CHECK (customer_status IN ('ACTIVE','INACTIVE','SUSPENDED','CLOSED')),
  created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
  updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

COMMENT ON TABLE  bankdb.customers IS 'AB Bank customer master data';
COMMENT ON COLUMN bankdb.customers.customer_status IS 'ACTIVE|INACTIVE|SUSPENDED|CLOSED';

-- Supplemental logging on the table key (good practice per CDC docs)
ALTER TABLE bankdb.customers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ============================================================
-- Table 2: ACCOUNTS
-- ============================================================
CREATE TABLE bankdb.accounts (
  account_id       NUMBER(12)     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id      NUMBER(10)     NOT NULL
                   REFERENCES bankdb.customers(customer_id),
  account_number   VARCHAR2(20)   UNIQUE NOT NULL,
  account_type     VARCHAR2(20)   NOT NULL
                   CHECK (account_type IN ('SAVINGS','CURRENT','FIXED_DEPOSIT','LOAN')),
  currency         VARCHAR2(3)    DEFAULT 'NGN',
  balance          NUMBER(18,4)   DEFAULT 0.0000,
  available_balance NUMBER(18,4)  DEFAULT 0.0000,
  overdraft_limit  NUMBER(18,4)   DEFAULT 0.0000,
  interest_rate    NUMBER(5,4)    DEFAULT 0.0000,
  account_status   VARCHAR2(20)   DEFAULT 'ACTIVE'
                   CHECK (account_status IN ('ACTIVE','DORMANT','CLOSED','FROZEN')),
  opened_date      DATE           DEFAULT SYSDATE,
  closed_date      DATE,
  created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP,
  updated_at       TIMESTAMP      DEFAULT SYSTIMESTAMP
);

ALTER TABLE bankdb.accounts ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ============================================================
-- Table 3: TRANSACTIONS (the main CDC target)
-- ============================================================
CREATE TABLE bankdb.transactions (
  transaction_id    NUMBER(15)     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id        NUMBER(12)     NOT NULL
                    REFERENCES bankdb.accounts(account_id),
  transaction_ref   VARCHAR2(30)   UNIQUE NOT NULL,
  transaction_type  VARCHAR2(20)   NOT NULL
                    CHECK (transaction_type IN
                      ('CREDIT','DEBIT','TRANSFER_IN','TRANSFER_OUT',
                       'INTEREST','FEE','REVERSAL','LOAN_REPAYMENT')),
  amount            NUMBER(18,4)   NOT NULL,
  currency          VARCHAR2(3)    DEFAULT 'NGN',
  balance_before    NUMBER(18,4),
  balance_after     NUMBER(18,4),
  description       VARCHAR2(500),
  counterparty_name VARCHAR2(255),
  counterparty_acct VARCHAR2(30),
  channel           VARCHAR2(30)
                    CHECK (channel IN
                      ('BRANCH','ATM','MOBILE','INTERNET','POS','USSD','API')),
  transaction_status VARCHAR2(20)  DEFAULT 'PENDING'
                    CHECK (transaction_status IN
                      ('PENDING','COMPLETED','FAILED','REVERSED','DISPUTED')),
  initiated_at      TIMESTAMP      DEFAULT SYSTIMESTAMP,
  completed_at      TIMESTAMP,
  created_at        TIMESTAMP      DEFAULT SYSTIMESTAMP,
  updated_at        TIMESTAMP      DEFAULT SYSTIMESTAMP
);

ALTER TABLE bankdb.transactions ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Index for common queries
CREATE INDEX bankdb.idx_txn_account   ON bankdb.transactions(account_id, initiated_at DESC);
CREATE INDEX bankdb.idx_txn_status    ON bankdb.transactions(transaction_status);
-- CREATE INDEX bankdb.idx_txn_ref       ON bankdb.transactions(transaction_ref);

-- ============================================================
-- Table 4: TRANSACTION_AUDIT
-- High-value or suspicious transactions get written here too
-- ============================================================
CREATE TABLE bankdb.transaction_audit (
  audit_id          NUMBER(15)    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transaction_id    NUMBER(15)    NOT NULL
                    REFERENCES bankdb.transactions(transaction_id),
  audit_action      VARCHAR2(20)  NOT NULL
                    CHECK (audit_action IN ('FLAGGED','REVIEWED','CLEARED','ESCALATED')),
  flagged_reason    VARCHAR2(255),
  reviewed_by       VARCHAR2(100),
  reviewed_at       TIMESTAMP,
  notes             VARCHAR2(1000),
  created_at        TIMESTAMP     DEFAULT SYSTIMESTAMP
);

ALTER TABLE bankdb.transaction_audit ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Allow the XStream admin to read any of the banking tables
GRANT SELECT ON bankdb.customers        TO c##ggadmin;
GRANT SELECT ON bankdb.accounts         TO c##ggadmin;
GRANT SELECT ON bankdb.transactions     TO c##ggadmin;
GRANT SELECT ON bankdb.transaction_audit TO c##ggadmin;

-- ============================================================
-- Auto-update updated_at via triggers
-- ============================================================
CREATE OR REPLACE TRIGGER bankdb.trg_customers_upd
  BEFORE UPDATE ON bankdb.customers
  FOR EACH ROW
BEGIN
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER bankdb.trg_accounts_upd
  BEFORE UPDATE ON bankdb.accounts
  FOR EACH ROW
BEGIN
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER bankdb.trg_transactions_upd
  BEFORE UPDATE ON bankdb.transactions
  FOR EACH ROW
BEGIN
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- ============================================================
-- Sequence for transaction reference numbers
-- ============================================================
CREATE SEQUENCE bankdb.txn_ref_seq
  START WITH 100000
  INCREMENT BY 1
  NOCACHE
  NOCYCLE;

PROMPT ==========================================
PROMPT Step 2 complete: BANKDB schema created
PROMPT ==========================================
