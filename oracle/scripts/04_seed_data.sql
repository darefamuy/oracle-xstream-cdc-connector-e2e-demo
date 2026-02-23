-- =============================================================================
-- 04_seed_data.sql
-- Run as: sysdba (Oracle Docker init hook always connects as sysdba in CDB)
--
-- Switches to XEPDB1 and uses fully-qualified bankdb.<table> names throughout
-- so this works when connected as sysdba rather than as the bankdb user.
-- =============================================================================

ALTER SESSION SET CONTAINER = XEPDB1;

-- ── Customers ──────────────────────────────────────────────────────────────
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Amara',    'Okonkwo',    'amara.okonkwo@abbank.ng',     '+2348012345001', DATE '1985-03-15', 'Lagos',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Chidi',    'Eze',        'chidi.eze@abbank.ng',         '+2348012345002', DATE '1990-07-22', 'Abuja',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Fatima',   'Bello',      'fatima.bello@abbank.ng',      '+2348012345003', DATE '1978-11-08', 'Kano',          'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Emeka',    'Nwosu',      'emeka.nwosu@abbank.ng',       '+2348012345004', DATE '1995-01-30', 'Port Harcourt', 'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Ngozi',    'Adeyemi',    'ngozi.adeyemi@abbank.ng',     '+2348012345005', DATE '1988-06-12', 'Ibadan',        'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Musa',     'Ibrahim',    'musa.ibrahim@abbank.ng',      '+2348012345006', DATE '1972-09-03', 'Kaduna',        'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Aisha',    'Mohammed',   'aisha.mohammed@abbank.ng',    '+2348012345007', DATE '1993-12-19', 'Abuja',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Tunde',    'Olawale',    'tunde.olawale@abbank.ng',     '+2348012345008', DATE '1982-04-25', 'Lagos',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Chioma',   'Uchenna',    'chioma.uchenna@abbank.ng',    '+2348012345009', DATE '1997-08-14', 'Enugu',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Babatunde','Afolabi',    'baba.afolabi@abbank.ng',      '+2348012345010', DATE '1965-02-28', 'Lagos',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Halima',   'Garba',      'halima.garba@abbank.ng',      '+2348012345011', DATE '1991-05-17', 'Sokoto',        'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Obinna',   'Okorie',     'obinna.okorie@abbank.ng',     '+2348012345012', DATE '1987-10-09', 'Owerri',        'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Zainab',   'Usman',      'zainab.usman@abbank.ng',      '+2348012345013', DATE '1994-03-21', 'Maiduguri',     'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Kayode',   'Fashola',    'kayode.fashola@abbank.ng',    '+2348012345014', DATE '1980-07-06', 'Abeokuta',      'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Nkem',     'Okafor',     'nkem.okafor@abbank.ng',       '+2348012345015', DATE '1999-11-25', 'Asaba',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Suleiman', 'Danladi',    'suleiman.danladi@abbank.ng',  '+2348012345016', DATE '1976-01-15', 'Bauchi',        'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Ifeoma',   'Nwachukwu',  'ifeoma.nwachukwu@abbank.ng',  '+2348012345017', DATE '1992-09-30', 'Lagos',         'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Yakubu',   'Musa',       'yakubu.musa@abbank.ng',       '+2348012345018', DATE '1970-12-03', 'Jos',           'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Adaeze',   'Obi',        'adaeze.obi@abbank.ng',        '+2348012345019', DATE '1996-04-08', 'Onitsha',       'Nigeria');
INSERT INTO bankdb.customers (first_name, last_name, email, phone, date_of_birth, city, country)
VALUES ('Rotimi',   'Coker',      'rotimi.coker@abbank.ng',      '+2348012345020', DATE '1983-06-22', 'Lagos',         'Nigeria');

COMMIT;

-- ── Accounts (2 per customer: SAVINGS + CURRENT) ──────────────────────────
DECLARE
  CURSOR c_cust IS
    SELECT customer_id, ROWNUM rn
    FROM   bankdb.customers                           -- schema-qualified
    ORDER BY customer_id;
BEGIN
  FOR r IN c_cust LOOP
    -- Savings account
    INSERT INTO bankdb.accounts (                     -- schema-qualified
      customer_id, account_number, account_type,
      currency, balance, available_balance)
    VALUES (
      r.customer_id,
      'SAVN' || LPAD(r.rn, 8, '0'),
      'SAVINGS', 'NGN',
      ROUND(DBMS_RANDOM.VALUE(10000,  5000000), 4),
      ROUND(DBMS_RANDOM.VALUE( 5000,  2000000), 4));

    -- Current account
    INSERT INTO bankdb.accounts (                     -- schema-qualified
      customer_id, account_number, account_type,
      currency, balance, available_balance, overdraft_limit)
    VALUES (
      r.customer_id,
      'CURR' || LPAD(r.rn, 8, '0'),
      'CURRENT', 'NGN',
      ROUND(DBMS_RANDOM.VALUE(    0, 10000000), 4),
      ROUND(DBMS_RANDOM.VALUE(    0,  8000000), 4),
      500000);
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Accounts seeded.');
END;
/

PROMPT ==========================================
PROMPT Step 4 complete: seed data inserted
PROMPT ==========================================