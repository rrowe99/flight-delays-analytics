-- ============================================================
-- 02_load_data.sql
-- Loads the 3 CSV files, then adds indexes.
--
-- PART 1 runs in the PSQL Tool (right-click database > PSQL Tool).
-- PART 2 runs in the Query Tool.
-- Load order matters: airlines before flights, because flights
-- references airlines.
-- ============================================================

-- ---------- PART 1: Load data (PSQL Tool) ----------
-- Each \copy command must stay on ONE line.
-- ENCODING 'UTF8' keeps special characters (é, á) from turning into garbage.

\copy airlines FROM 'C:/Users/Richie/OneDrive/Documents/flight-delays-analytics/data/airlines.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy airports FROM 'C:/Users/Richie/OneDrive/Documents/flight-delays-analytics/data/airports.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy flights FROM 'C:/Users/Richie/OneDrive/Documents/flight-delays-analytics/data/flights.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- ---------- PART 2: Indexes (Query Tool) ----------
-- Created AFTER loading so the load runs faster.
-- These speed up queries that filter or group by these columns.

CREATE INDEX idx_flights_origin  ON flights (origin_airport);
CREATE INDEX idx_flights_dest    ON flights (destination_airport);
CREATE INDEX idx_flights_airline ON flights (airline);
CREATE INDEX idx_flights_date    ON flights (flight_date);