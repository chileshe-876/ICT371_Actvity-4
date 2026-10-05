DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INTEGER NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    dispensing_id SERIAL PRIMARY KEY,
    student_number VARCHAR(30) NOT NULL,
    medicine_id INTEGER NOT NULL REFERENCES medicines(medicine_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    dispensing_status VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
        CHECK (dispensing_status IN ('DISPENSED', 'REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
('Paracetamol', 50),
('Amoxicillin', 10),
('Ibuprofen', 5);

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT medicine_name, stock_quantity
             FROM medicines ORDER BY medicine_id LOOP
        IF r.stock_quantity = 0 THEN
            RAISE NOTICE '%: OUT OF STOCK', r.medicine_name;
        ELSIF r.stock_quantity <= 10 THEN
            RAISE NOTICE '%: LOW ON STOCK (% remaining)',
                r.medicine_name, r.stock_quantity;
        ELSE
            RAISE NOTICE '%: SUFFICIENTLY STOCKED (% remaining)',
                r.medicine_name, r.stock_quantity;
        END IF;
    END LOOP;
END $$;


DO $$
DECLARE
    review_day INTEGER := 1;
BEGIN
    WHILE review_day <= 3 LOOP
        RAISE NOTICE 'Stock review day %', review_day;
        review_day := review_day + 1;
    END LOOP;
END $$;


DO $$
BEGIN
    FOR inspection_no IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', inspection_no;
    END LOOP;
END $$;


CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_student_number VARCHAR,
    p_medicine_id INTEGER,
    p_quantity INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: must be greater than zero.';
    END IF;

    SELECT stock_quantity
    INTO v_stock
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Medicine ID % does not exist.', p_medicine_id;
        RETURN;
    END IF;

    IF v_stock >= p_quantity THEN
        UPDATE medicines
        SET stock_quantity = stock_quantity - p_quantity
        WHERE medicine_id = p_medicine_id;

        INSERT INTO dispensing_records
            (student_number, medicine_id, quantity, dispensing_status)
        VALUES
            (p_student_number, p_medicine_id, p_quantity, 'DISPENSED');

        RAISE NOTICE 'Medicine dispensed to student %.', p_student_number;
    ELSE
        RAISE NOTICE 'Insufficient stock: only % available.', v_stock;
    END IF;
END;
$$;


CALL dispense_medicine('STU001', 1, 10);
CALL dispense_medicine('STU002', 2, 3);
CALL dispense_medicine('STU003', 3, 10);

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY dispensing_id;


CREATE OR REPLACE PROCEDURE reverse_dispensing(p_dispensing_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INTEGER;
    v_quantity INTEGER;
BEGIN
    SELECT medicine_id, quantity
    INTO v_medicine_id, v_quantity
    FROM dispensing_records
    WHERE dispensing_id = p_dispensing_id
      AND dispensing_status = 'DISPENSED'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % is already reversed or does not exist.',
            p_dispensing_id;
        RETURN;
    END IF;

    UPDATE dispensing_records
    SET dispensing_status = 'REVERSED'
    WHERE dispensing_id = p_dispensing_id;

    UPDATE medicines
    SET stock_quantity = stock_quantity + v_quantity
    WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Dispensing record % reversed; % units restored.',
        p_dispensing_id, v_quantity;
END;
$$;

CALL reverse_dispensing(1);
CALL reverse_dispensing(1);


DO $$
DECLARE
    medicine_cursor CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity < 10
        ORDER BY medicine_id;
    v_medicine_id INTEGER;
    v_name VARCHAR(100);
    v_stock INTEGER;
BEGIN
    OPEN medicine_cursor;

    LOOP
        FETCH medicine_cursor INTO v_medicine_id, v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low-stock medicine: ID %, %, % units remaining',
            v_medicine_id, v_name, v_stock;
    END LOOP;

    CLOSE medicine_cursor;
END $$;


DO $$
BEGIN
    CALL dispense_medicine('STU004', 1, -2);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Exception handled: %', SQLERRM;
END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY dispensing_id;
