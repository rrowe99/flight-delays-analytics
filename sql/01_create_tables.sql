-- 01_create_tables.sql
-- Creates the flight delays schema. Drops tables first so it can be re-run.

DROP TABLE IF EXISTS flights, airports, airlines;

CREATE TABLE airlines (
    iata_code CHAR(2) PRIMARY KEY,
    airline   TEXT NOT NULL
);

CREATE TABLE airports (
    iata_code CHAR(3) PRIMARY KEY,
    airport   TEXT NOT NULL,
    city      TEXT,
    state     CHAR(2),
    country   TEXT,
    latitude  NUMERIC(8,5),
    longitude NUMERIC(8,5)
);

-- No foreign keys to airports on purpose: October uses numeric airport IDs
-- instead of 3-letter codes, which would make the load fail.
CREATE TABLE flights (
    year                INT NOT NULL,
    month               INT NOT NULL CHECK (month BETWEEN 1 AND 12),
    day                 INT NOT NULL CHECK (day BETWEEN 1 AND 31),
    day_of_week         INT CHECK (day_of_week BETWEEN 1 AND 7),
    airline             CHAR(2) NOT NULL REFERENCES airlines(iata_code),
    flight_number       INT,
    tail_number         TEXT,
    origin_airport      TEXT NOT NULL,
    destination_airport TEXT NOT NULL,
    scheduled_departure INT,   -- HHMM, e.g. 1430 = 2:30 PM
    departure_time      INT,
    departure_delay     INT,   -- minutes; negative = left early
    taxi_out            INT,
    wheels_off          INT,
    scheduled_time      INT,
    elapsed_time        INT,
    air_time            INT,
    distance            INT,
    wheels_on           INT,
    taxi_in             INT,
    scheduled_arrival   INT,
    arrival_time        INT,
    arrival_delay       INT,
    diverted            BOOLEAN,
    cancelled           BOOLEAN,
    cancellation_reason CHAR(1),
    air_system_delay    INT,
    security_delay      INT,
    airline_delay       INT,
    late_aircraft_delay INT,
    weather_delay       INT,
    -- Built automatically from year/month/day. \copy skips this column.
    flight_date DATE GENERATED ALWAYS AS (make_date(year, month, day)) STORED
);