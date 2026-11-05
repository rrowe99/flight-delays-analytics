-- ============================================================
-- 05_views_for_powerbi.sql
-- Saves the analysis queries as views so Power BI can load
-- small summary tables instead of 5.8 million raw rows.
-- Run the whole file in the Query Tool.
-- Safe to re-run: it drops the views first.
-- ============================================================

DROP VIEW IF EXISTS v_airport_on_time, v_bos_delay_causes, v_bos_airlines,
                    v_bos_monthly, v_bos_hourly, v_bos_routes, v_national_hourly_causes;


-- ------------------------------------------------------------
-- Q1: Large airports (50,000+ flights), on-time and cancellations
-- ------------------------------------------------------------
CREATE VIEW v_airport_on_time AS
WITH airport_departures AS (
    SELECT
        origin_airport,
        COUNT(*) AS scheduled_flights,
        SUM(CASE WHEN cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        SUM(CASE WHEN NOT cancelled THEN 1 ELSE 0 END) AS operated_flights,
        SUM(CASE WHEN NOT cancelled AND departure_delay < 15 THEN 1 ELSE 0 END) AS on_time_departures,
        AVG(CASE WHEN departure_delay > 0 THEN departure_delay END) AS avg_delay_when_late
    FROM flights
    WHERE month <> 10
    GROUP BY origin_airport
)
SELECT
    d.origin_airport AS airport_code,
    a.airport        AS airport_name,
    a.city,
    a.state,
    a.latitude,
    a.longitude,
    d.scheduled_flights,
    ROUND(100.0 * d.on_time_departures / d.operated_flights, 1) AS on_time_pct,
    ROUND(100.0 * d.cancelled_flights / d.scheduled_flights, 2) AS cancellation_pct,
    ROUND(d.avg_delay_when_late, 1) AS avg_minutes_late_when_late,
    RANK() OVER (ORDER BY 1.0 * d.on_time_departures / d.operated_flights DESC) AS on_time_rank,
    (d.origin_airport = 'BOS') AS is_bos
FROM airport_departures d
JOIN airports a ON a.iata_code = d.origin_airport
WHERE d.scheduled_flights >= 50000;


-- ------------------------------------------------------------
-- Q2a: What causes delays on flights leaving BOS
-- One row per cause
-- ------------------------------------------------------------
CREATE VIEW v_bos_delay_causes AS
WITH bos_late AS (
    SELECT *
    FROM flights
    WHERE origin_airport = 'BOS'
      AND month <> 10
      AND arrival_delay >= 15
),
causes AS (
    SELECT 'Late aircraft' AS cause, SUM(late_aircraft_delay) AS delay_minutes FROM bos_late
    UNION ALL SELECT 'Air system', SUM(air_system_delay) FROM bos_late
    UNION ALL SELECT 'Airline',    SUM(airline_delay)    FROM bos_late
    UNION ALL SELECT 'Weather',    SUM(weather_delay)    FROM bos_late
    UNION ALL SELECT 'Security',   SUM(security_delay)   FROM bos_late
)
SELECT
    cause,
    delay_minutes,
    ROUND(100.0 * delay_minutes / SUM(delay_minutes) OVER (), 1) AS pct_of_delay_minutes
FROM causes;


-- ------------------------------------------------------------
-- Q2b + Q2c: Airline performance at BOS
-- Includes Jan-Jun cancellation rate for a fair US Airways comparison
-- ------------------------------------------------------------
CREATE VIEW v_bos_airlines AS
SELECT
    al.airline,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_pct,
    ROUND(100.0 * SUM(CASE WHEN f.month BETWEEN 1 AND 6 AND f.cancelled THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN f.month BETWEEN 1 AND 6 THEN 1 ELSE 0 END), 0), 2) AS jan_jun_cancellation_pct,
    ROUND(100.0 * SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted AND f.arrival_delay >= 15 THEN 1 ELSE 0 END)
                / SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted THEN 1 ELSE 0 END), 1) AS late_arrival_pct,
    SUM(CASE WHEN f.arrival_delay >= 15 THEN f.arrival_delay ELSE 0 END) AS total_late_minutes,
    ROUND(100.0 * SUM(CASE WHEN f.arrival_delay >= 15 THEN f.arrival_delay ELSE 0 END)
                / SUM(SUM(CASE WHEN f.arrival_delay >= 15 THEN f.arrival_delay ELSE 0 END)) OVER (), 1) AS share_of_bos_late_minutes,
    ROUND(100.0 * SUM(f.airline_delay)
                / SUM(CASE WHEN f.arrival_delay >= 15 THEN f.arrival_delay END), 1) AS self_caused_pct
FROM flights f
JOIN airlines al ON al.iata_code = f.airline
WHERE f.origin_airport = 'BOS'
  AND f.month <> 10
GROUP BY al.airline
HAVING COUNT(*) >= 1000;


-- ------------------------------------------------------------
-- Q3a: BOS vs national, by month
-- ------------------------------------------------------------
CREATE VIEW v_bos_monthly AS
WITH bos AS (
    SELECT
        month,
        COUNT(*) AS scheduled_flights,
        ROUND(100.0 * SUM(CASE WHEN cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS bos_cancellation_pct,
        ROUND(100.0 * SUM(CASE WHEN NOT cancelled AND departure_delay < 15 THEN 1 ELSE 0 END)
                    / SUM(CASE WHEN NOT cancelled THEN 1 ELSE 0 END), 1) AS bos_on_time_pct,
        SUM(CASE WHEN cancellation_reason = 'B' THEN 1 ELSE 0 END) AS bos_weather_cancellations
    FROM flights
    WHERE origin_airport = 'BOS'
      AND month <> 10
    GROUP BY month
),
national AS (
    SELECT
        month,
        ROUND(100.0 * SUM(CASE WHEN cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS national_cancellation_pct,
        ROUND(100.0 * SUM(CASE WHEN NOT cancelled AND departure_delay < 15 THEN 1 ELSE 0 END)
                    / SUM(CASE WHEN NOT cancelled THEN 1 ELSE 0 END), 1) AS national_on_time_pct
    FROM flights
    WHERE month <> 10
    GROUP BY month
)
SELECT
    b.month,
    TO_CHAR(make_date(2015, b.month, 1), 'Mon') AS month_name,
    b.scheduled_flights,
    b.bos_cancellation_pct,
    n.national_cancellation_pct,
    b.bos_on_time_pct,
    n.national_on_time_pct,
    b.bos_weather_cancellations
FROM bos b
JOIN national n ON n.month = b.month;


-- ------------------------------------------------------------
-- Q3b: BOS on-time by departure hour
-- ------------------------------------------------------------
CREATE VIEW v_bos_hourly AS
SELECT
    scheduled_departure / 100 AS departure_hour,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * SUM(CASE WHEN NOT cancelled AND departure_delay < 15 THEN 1 ELSE 0 END)
                / SUM(CASE WHEN NOT cancelled THEN 1 ELSE 0 END), 1) AS on_time_pct,
    ROUND(AVG(CASE WHEN departure_delay > 0 THEN departure_delay END), 1) AS avg_minutes_late_when_late
FROM flights
WHERE origin_airport = 'BOS'
  AND month <> 10
GROUP BY departure_hour
HAVING COUNT(*) >= 100;


-- ------------------------------------------------------------
-- Q4: BOS routes (with destination coordinates for a map)
-- ------------------------------------------------------------
CREATE VIEW v_bos_routes AS
SELECT
    f.destination_airport,
    a.city AS destination_city,
    a.latitude,
    a.longitude,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_pct,
    ROUND(100.0 * SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted AND f.arrival_delay >= 15 THEN 1 ELSE 0 END)
                / SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted THEN 1 ELSE 0 END), 1) AS late_arrival_pct,
    ROUND(AVG(CASE WHEN f.arrival_delay >= 15 THEN f.arrival_delay END), 1) AS avg_minutes_late_when_late
FROM flights f
JOIN airports a ON a.iata_code = f.destination_airport
WHERE f.origin_airport = 'BOS'
  AND f.month <> 10
GROUP BY f.destination_airport, a.city, a.latitude, a.longitude
HAVING COUNT(*) >= 500;


-- ------------------------------------------------------------
-- Q5: National delay causes by departure hour
-- One row per hour per cause
-- ------------------------------------------------------------
CREATE VIEW v_national_hourly_causes AS
WITH hourly AS (
    SELECT
        scheduled_departure / 100 AS departure_hour,
        SUM(arrival_delay)       AS total_minutes,
        SUM(late_aircraft_delay) AS late_aircraft,
        SUM(airline_delay)       AS airline,
        SUM(air_system_delay)    AS air_system,
        SUM(weather_delay)       AS weather,
        SUM(security_delay)      AS security
    FROM flights
    WHERE arrival_delay >= 15
    GROUP BY departure_hour
    HAVING COUNT(*) >= 1000
)
SELECT departure_hour, 'Late aircraft' AS cause, ROUND(100.0 * late_aircraft / total_minutes, 1) AS pct_of_delay_minutes FROM hourly
UNION ALL SELECT departure_hour, 'Airline',    ROUND(100.0 * airline    / total_minutes, 1) FROM hourly
UNION ALL SELECT departure_hour, 'Air system', ROUND(100.0 * air_system / total_minutes, 1) FROM hourly
UNION ALL SELECT departure_hour, 'Weather',    ROUND(100.0 * weather    / total_minutes, 1) FROM hourly
UNION ALL SELECT departure_hour, 'Security',   ROUND(100.0 * security   / total_minutes, 1) FROM hourly;