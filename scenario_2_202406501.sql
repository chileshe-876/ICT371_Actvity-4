DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,
    session_name VARCHAR(100) NOT NULL,
    available_workstations INTEGER NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    lecturer VARCHAR(100) NOT NULL,
    session_id INTEGER NOT NULL REFERENCES lab_sessions(session_id),
    workstations INTEGER NOT NULL CHECK (workstations > 0),
    reservation_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (reservation_status IN ('ACTIVE', 'CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
('Database Practical', 20),
('Programming Practical', 10),
('Networking Practical', 5);

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT session_name, available_workstations
             FROM lab_sessions ORDER BY session_id LOOP
        IF r.available_workstations = 0 THEN
            RAISE NOTICE '%: FULL', r.session_name;
        ELSIF r.available_workstations <= 3 THEN
            RAISE NOTICE '%: NEARLY FULL (% workstations left)',
                r.session_name, r.available_workstations;
        ELSE
            RAISE NOTICE '%: ENOUGH WORKSTATIONS (% available)',
                r.session_name, r.available_workstations;
        END IF;
    END LOOP;
END $$;

DO $$
DECLARE
    reminder_no INTEGER := 1;
BEGIN
    WHILE reminder_no <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', reminder_no;
        reminder_no := reminder_no + 1;
    END LOOP;
END $$;

DO $$
BEGIN
    FOR check_no IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', check_no;
    END LOOP;
END $$;


CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_lecturer VARCHAR,
    p_session_id INTEGER,
    p_workstations INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid workstation quantity: must be greater than zero.';
    END IF;

    SELECT available_workstations
    INTO v_available
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Session ID % does not exist.', p_session_id;
        RETURN;
    END IF;

    IF v_available >= p_workstations THEN
        UPDATE lab_sessions
        SET available_workstations = available_workstations - p_workstations
        WHERE session_id = p_session_id;

        INSERT INTO reservations
            (lecturer, session_id, workstations, reservation_status)
        VALUES
            (p_lecturer, p_session_id, p_workstations, 'ACTIVE');

        RAISE NOTICE 'Reservation recorded for %.', p_lecturer;
    ELSE
        RAISE NOTICE 'Insufficient capacity: only % workstations available.',
            v_available;
    END IF;
END;
$$;

CALL reserve_workstations('Dr. Banda', 1, 5);
CALL reserve_workstations('Dr. Phiri', 2, 4);
CALL reserve_workstations('Dr. Zulu', 3, 6);

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INTEGER;
    v_workstations INTEGER;
BEGIN
    SELECT session_id, workstations
    INTO v_session_id, v_workstations
    FROM reservations
    WHERE reservation_id = p_reservation_id
      AND reservation_status = 'ACTIVE'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % is already cancelled or does not exist.',
            p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations
    SET reservation_status = 'CANCELLED'
    WHERE reservation_id = p_reservation_id;

    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_workstations
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled; % workstations released.',
        p_reservation_id, v_workstations;
END;
$$;

CALL cancel_reservation(1);
CALL cancel_reservation(1);

DO $$
DECLARE
    session_cursor CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 3
        ORDER BY session_id;
    v_session_id INTEGER;
    v_name VARCHAR(100);
    v_available INTEGER;
BEGIN
    OPEN session_cursor;

    LOOP
        FETCH session_cursor INTO v_session_id, v_name, v_available;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low-capacity session: ID %, %, % workstations remaining',
            v_session_id, v_name, v_available;
    END LOOP;

    CLOSE session_cursor;
END $$;

DO $$
BEGIN
    CALL reserve_workstations('Dr. Zero', 1, 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Exception handled: %', SQLERRM;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
