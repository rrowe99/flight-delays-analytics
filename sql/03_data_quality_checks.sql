-- ============================================================
-- 03_data_quality_checks.sql
-- Checks the data for problems before analysis.
-- Each check is followed by what it found and what I decided.
-- ============================================================


-- 1. Did all the data load?
SELECT 'airlines' AS table_name, COUNT(*) AS row_count FROM airlines
UNION ALL SELECT 'airports', COUNT(*) FROM airports
UNION ALL SELECT 'flights', COUNT(*) FROM flights;
-- RESULT: 14 airlines, 322 airports, 5,819,079 flights.


-- 2. Is any month missing?
SELECT month, COUNT(*) AS flights
FROM flights
GROUP BY month
ORDER BY month;
-- RESULT: All 12 months present.


-- 3. Which flights have origin codes that don't match airports.csv?
SELECT f.month, COUNT(*) AS unmatched_origin
FROM flights f
LEFT JOIN airports a ON a.iata_code = f.origin_airport
WHERE a.iata_code IS NULL
GROUP BY f.month
ORDER BY f.month;
-- RESULT: Only October, and all 486,165 October flights are unmatched.


-- 4. What do the unmatched codes look like?
SELECT origin_airport, COUNT(*) AS flights
FROM flights
WHERE origin_airport ~ '^[0-9]+$'   -- only digits
GROUP BY origin_airport
ORDER BY flights DESC
LIMIT 10;
-- RESULT: October uses 5-digit numeric airport IDs (e.g. 10397, 13930)
-- instead of 3-letter codes.
-- DECISION: Exclude October from airport-level analysis.
-- Keep October for airline-level analysis (airline codes are fine).


-- 5. Do cancelled and diverted flights have missing delays?
SELECT
    cancelled,
    diverted,
    COUNT(*) AS flights,
    SUM(CASE WHEN arrival_delay IS NULL THEN 1 ELSE 0 END) AS missing_arrival_delay
FROM flights
GROUP BY 1, 2
ORDER BY 1, 2;
-- RESULT: All 89,884 cancelled and 15,187 diverted flights have no
-- arrival delay. All 5,714,008 normal flights have one.
-- DECISION: Exclude cancelled and diverted flights when averaging delays.


-- 6. Why were flights cancelled?
-- A = airline, B = weather, C = air traffic system, D = security
SELECT cancellation_reason, COUNT(*) AS flights
FROM flights
WHERE cancelled
GROUP BY cancellation_reason
ORDER BY flights DESC;
-- RESULT: Weather 48,851 (~54%), Airline 25,262 (~28%),
-- Air system 15,749 (~18%), Security 22.


-- 7. Are delay causes only recorded for flights 15+ minutes late?
SELECT
    (arrival_delay >= 15)       AS delayed_15_plus,
    (airline_delay IS NOT NULL) AS has_cause_breakdown,
    COUNT(*)                    AS flights
FROM flights
WHERE NOT cancelled AND NOT diverted
GROUP BY 1, 2
ORDER BY 1, 2;
-- RESULT: Causes are filled in for exactly the 1,063,439 flights that
-- arrived 15+ minutes late, and for no others.
-- DECISION: Use only 15+ minute late flights for delay-cause analysis.


-- 8. Do the 5 cause columns add up to the total arrival delay?
SELECT COUNT(*) AS cause_mismatches
FROM flights
WHERE airline_delay IS NOT NULL
  AND arrival_delay <> air_system_delay + security_delay + airline_delay
                     + late_aircraft_delay + weather_delay;
-- RESULT: 0 mismatches. The causes can be trusted.


-- 9. When does each airline's data start and stop?
SELECT
    a.airline,
    MIN(f.flight_date) AS first_flight,
    MAX(f.flight_date) AS last_flight,
    COUNT(*)           AS flights
FROM flights f
JOIN airlines a ON a.iata_code = f.airline
GROUP BY a.airline
ORDER BY flights DESC;
-- RESULT: All airlines cover the full year except US Airways,
-- which ends 2015-06-30 (merged into American Airlines).
-- DECISION: Compare airlines with percentages, not totals.
-- Label US Airways as Jan to Jun only.


-- 10. Is midnight stored as 2400?
SELECT COUNT(*) AS times_2400
FROM flights
WHERE departure_time = 2400 OR arrival_time = 2400;
-- RESULT: 2,969 flights have an actual time of 2400.
-- DECISION: Use scheduled_departure (not actual times) to group by hour.


-- 11. Which airports are missing map coordinates?
SELECT iata_code, airport
FROM airports
WHERE latitude IS NULL OR longitude IS NULL;
-- RESULT: ECP, PBG, UST. Small airports; won't appear on the map.
-- ALSO FOUND: Airport names had garbled characters (e.g. "Â") because
-- the file was read with the wrong encoding.
-- FIX: Reloaded airports with ENCODING 'UTF8'.


-- 12. Are any flights listed twice?
SELECT airline, flight_number, flight_date, origin_airport, scheduled_departure, COUNT(*)
FROM flights
GROUP BY 1, 2, 3, 4, 5
HAVING COUNT(*) > 1
LIMIT 10;
-- RESULT: 1 case: AA 803 from STT on 2015-08-29 appears twice.

-- 12b. Look at both rows
SELECT *
FROM flights
WHERE airline = 'AA'
  AND flight_number = 803
  AND flight_date = '2015-08-29'
  AND origin_airport = 'STT';
-- RESULT: Not a true duplicate. The two rows have different destinations
-- (CLT and SJU). Both were cancelled (reason A). Likely one flight number
-- used for two legs.
-- DECISION: Keep both rows.