DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    available_copies INTEGER NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id SERIAL PRIMARY KEY,
    student_number VARCHAR(30) NOT NULL,
    book_id INTEGER NOT NULL REFERENCES books(book_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    loan_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (loan_status IN ('ACTIVE', 'RETURNED'))
);

INSERT INTO books (title, available_copies) VALUES
('Database Systems', 5),
('Computer Networks', 2),
('Operating Systems', 1);

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF r.available_copies = 0 THEN
            RAISE NOTICE '%: UNAVAILABLE', r.title;
        ELSIF r.available_copies <= 2 THEN
            RAISE NOTICE '%: LOW ON COPIES (% remaining)', r.title, r.available_copies;
        ELSE
            RAISE NOTICE '%: SUFFICIENTLY STOCKED (% remaining)', r.title, r.available_copies;
        END IF;
    END LOOP;
END $$;


DO $$
DECLARE
    reminder_no INTEGER := 1;
BEGIN
    WHILE reminder_no <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', reminder_no;
        reminder_no := reminder_no + 1;
    END LOOP;
END $$;


DO $$
BEGIN
    FOR shelf_no IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf_no;
    END LOOP;
END $$

CREATE OR REPLACE PROCEDURE borrow_book(
    p_student_number VARCHAR,
    p_book_id INTEGER,
    p_quantity INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: must borrow at least one copy.';
    END IF;

    SELECT available_copies
    INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Book ID % does not exist.', p_book_id;
        RETURN;
    END IF;

    IF v_available >= p_quantity THEN
        UPDATE books
        SET available_copies = available_copies - p_quantity
        WHERE book_id = p_book_id;

        INSERT INTO book_loans (student_number, book_id, quantity, loan_status)
        VALUES (p_student_number, p_book_id, p_quantity, 'ACTIVE');

        RAISE NOTICE 'Loan recorded for student %.', p_student_number;
    ELSE
        RAISE NOTICE 'Insufficient stock: only % available.', v_available;
    END IF;
END;
$$;

CALL borrow_book('STU001', 1, 2);
CALL borrow_book('STU002', 2, 1);
CALL borrow_book('STU003', 3, 2);

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;


CREATE OR REPLACE PROCEDURE return_book(p_loan_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INTEGER;
    v_quantity INTEGER;
BEGIN
    SELECT book_id, quantity
    INTO v_book_id, v_quantity
    FROM book_loans
    WHERE loan_id = p_loan_id
      AND loan_status = 'ACTIVE'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % is already returned or does not exist.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans
    SET loan_status = 'RETURNED'
    WHERE loan_id = p_loan_id;

    UPDATE books
    SET available_copies = available_copies + v_quantity
    WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned; % copies restored.', p_loan_id, v_quantity;
END;
$$;

CALL return_book(1);
CALL return_book(1);

DO $$
DECLARE
    book_cursor CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 2
        ORDER BY book_id;
    v_book_id INTEGER;
    v_title VARCHAR(150);
    v_copies INTEGER;
BEGIN
    OPEN book_cursor;

    LOOP
        FETCH book_cursor INTO v_book_id, v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low-copy book: ID %, %, % copies remaining',
            v_book_id, v_title, v_copies;
    END LOOP;

    CLOSE book_cursor;
END $$;


DO $$
BEGIN
    CALL borrow_book('STU004', 1, 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Exception handled: %', SQLERRM;
END $$;


SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
