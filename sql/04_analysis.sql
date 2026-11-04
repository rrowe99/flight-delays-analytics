-- ============================================================
-- 04_analysis.sql
-- Business questions about 2015 US flight delays, focused on
-- Boston Logan (BOS).
--
-- Definitions used throughout:
--   On-time      = departed less than 15 minutes late (DOT standard)
--   Operated     = not cancelled
--   Large airport = 50,000+ scheduled departures (Jan to Sep, Nov to Dec)
--   October is excluded from airport-level questions
--   (see 03_data_quality_checks.sql, checks 3 and 4).
-- ============================================================


-- ------------------------------------------------------------
-- Q1: How does BOS compare to other large airports?
-- ------------------------------------------------------------
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
    d.origin_airport,
    a.city,
    d.scheduled_flights,
    ROUND(100.0 * d.on_time_departures / d.operated_flights, 1) AS on_time_pct,
    ROUND(100.0 * d.cancelled_flights / d.scheduled_flights, 2) AS cancellation_pct,
    ROUND(d.avg_delay_when_late, 1) AS avg_minutes_late_when_late,
    RANK() OVER (ORDER BY 1.0 * d.on_time_departures / d.operated_flights DESC) AS on_time_rank
FROM airport_departures d
JOIN airports a ON a.iata_code = d.origin_airport
WHERE d.scheduled_flights >= 50000
ORDER BY on_time_rank;

-- RESULT: 29 large airports. BOS ranks 9th of 29 for on-time departures (81.6%)
-- but has the 6th-highest cancellation rate (2.46%).
-- Best: SLC (87.3%). Worst: MDW (75.1%).



-- ------------------------------------------------------------
-- Q2a: What causes delays on flights leaving BOS?
-- Uses only flights that arrived 15+ min late (the only ones
-- with causes recorded; see check 7).
-- ------------------------------------------------------------
SELECT
    COUNT(*)           AS late_flights,
    SUM(arrival_delay) AS total_late_minutes,
    ROUND(100.0 * SUM(airline_delay)       / SUM(arrival_delay), 1) AS airline_pct,
    ROUND(100.0 * SUM(late_aircraft_delay) / SUM(arrival_delay), 1) AS late_aircraft_pct,
    ROUND(100.0 * SUM(air_system_delay)    / SUM(arrival_delay), 1) AS air_system_pct,
    ROUND(100.0 * SUM(weather_delay)       / SUM(arrival_delay), 1) AS weather_pct,
    ROUND(100.0 * SUM(security_delay)      / SUM(arrival_delay), 1) AS security_pct
FROM flights
WHERE origin_airport = 'BOS'
  AND month <> 10
  AND arrival_delay >= 15;


-- RESULT: 21,363 late flights, 1,260,682 late minutes.
-- Late aircraft 33.2%, Air system 33.2%, Airline 27.7%, Weather 5.7%, Security 0.2%.
-- NOTE: DOT counts only extreme weather as "weather." Non-extreme weather
-- that slows air traffic is counted under "air system," so weather's
-- true impact is larger than 5.7%.


-- ------------------------------------------------------------
-- Q2b: Airline performance on flights leaving BOS
-- Note: US Airways covers Jan to Jun only (see check 9).
-- ------------------------------------------------------------
SELECT
    al.airline,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_pct,
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
HAVING COUNT(*) >= 1000
ORDER BY total_late_minutes DESC;

-- RESULT: JetBlue runs ~35% of BOS flights and causes 36.7% of BOS late
-- minutes. Its late-arrival rate (22.2%) is slightly above BOS overall (~20%)
-- and it has the highest self-caused share (32.9%).
-- Spirit has the worst late rate (29.5%) but only 3.2% of late minutes.
-- US Airways cancellation rate (6.32%) is misleading: Jan to Jun only (see Q2c).


-- ------------------------------------------------------------
-- Q2c: Fair comparison of BOS cancellations, Jan to Jun only
-- (the months US Airways has data for)
-- ------------------------------------------------------------
SELECT
    al.airline,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_pct
FROM flights f
JOIN airlines al ON al.iata_code = f.airline
WHERE f.origin_airport = 'BOS'
  AND f.month BETWEEN 1 AND 6
GROUP BY al.airline
HAVING COUNT(*) >= 500
ORDER BY cancellation_pct DESC;


-- RESULT: In Jan to Jun, all airlines' BOS cancellation rates rise to ~3-4%,
-- so the season explains much of US Airways' 6.32%. But US Airways is still
-- highest (vs 3.3-4.0% for major carriers). JetBlue lowest among majors (3.27%).



-- ------------------------------------------------------------
-- Q3a: BOS on-time and cancellations by month, vs national
-- October excluded (see checks 3 and 4).
-- ------------------------------------------------------------
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
    b.scheduled_flights,
    b.bos_cancellation_pct,
    n.national_cancellation_pct,
    b.bos_on_time_pct,
    n.national_on_time_pct,
    b.bos_weather_cancellations
FROM bos b
JOIN national n ON n.month = b.month
ORDER BY b.month;


-- RESULT: Jan and Feb caused ~2/3 of BOS cancellations and ~85% of weather
-- cancellations. Feb: 13.66% BOS vs 4.78% national (~3x).
-- From April onward, BOS cancellation rate was at or below national every month.
-- CONCLUSION: BOS's high yearly cancellation rate (Q1) is driven by the
-- record 2015 winter, not a year-round problem. One year only; can't
-- generalize to every winter.


-- ------------------------------------------------------------
-- Q3b: BOS on-time performance by scheduled departure hour
-- Uses scheduled_departure, not actual time (see check 10).
-- ------------------------------------------------------------
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
HAVING COUNT(*) >= 100
ORDER BY departure_hour;


-- RESULT: On-time falls from 94.3% (5 AM) to ~68% (5 PM onward).
-- Average delay when late rises from ~24 to ~48 minutes.
-- Delays build through the day. Practical takeaway: morning
-- departures from BOS are far more reliable.



-- ------------------------------------------------------------
-- Q4: Least reliable routes from BOS
-- Routes with at least 500 scheduled flights.
-- ------------------------------------------------------------
SELECT
    f.destination_airport,
    a.city,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_pct,
    ROUND(100.0 * SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted AND f.arrival_delay >= 15 THEN 1 ELSE 0 END)
                / SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted THEN 1 ELSE 0 END), 1) AS late_arrival_pct,
    ROUND(AVG(CASE WHEN f.arrival_delay >= 15 THEN f.arrival_delay END), 1) AS avg_minutes_late_when_late
FROM flights f
JOIN airports a ON a.iata_code = f.destination_airport
WHERE f.origin_airport = 'BOS'
  AND f.month <> 10
GROUP BY f.destination_airport, a.city
HAVING COUNT(*) >= 500
ORDER BY late_arrival_pct DESC;


-- RESULT: Least reliable BOS routes are leisure routes: FLL (30.6% late),
-- LAS (30.5%), SJU (30.0%), PBI (29.3%), plus other Florida airports.
-- Most reliable: short Midwest routes (CLE 12.0%, BUF 14.0%).
-- LGA has by far the highest cancellation rate (6.24%).
-- JFK has the longest delays when late (73.7 min).
-- My guess was wrong: routes to the worst Q1 airports (ORD, EWR, MDW)
-- are mid-pack, not the worst.



-- ------------------------------------------------------------
-- Q4b: Who flies the 5 least reliable BOS routes, and how do
-- airlines compare on the SAME route?
-- ------------------------------------------------------------
SELECT
    f.destination_airport,
    al.airline,
    COUNT(*) AS scheduled_flights,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY f.destination_airport), 1) AS share_of_route_pct,
    ROUND(100.0 * SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted AND f.arrival_delay >= 15 THEN 1 ELSE 0 END)
                / SUM(CASE WHEN NOT f.cancelled AND NOT f.diverted THEN 1 ELSE 0 END), 1) AS late_arrival_pct
FROM flights f
JOIN airlines al ON al.iata_code = f.airline
WHERE f.origin_airport = 'BOS'
  AND f.month <> 10
  AND f.destination_airport IN ('FLL', 'LAS', 'SJU', 'PBI', 'RSW')
GROUP BY f.destination_airport, al.airline
ORDER BY f.destination_airport, scheduled_flights DESC;


-- RESULT: JetBlue flies 71-100% of the 5 least reliable BOS routes.
-- JetBlue's late rate on these routes (23.7-30.0%) is above its BOS
-- average (22.2%), so the routes themselves are harder.
-- Spirit is far worse than JetBlue on FLL (53.7% vs 26.5%) and
-- LAS (47.1% vs 26.4%), pulling those routes to the top.
-- SJU is 100% JetBlue, so no airline comparison is possible.



-- ------------------------------------------------------------
-- Q5: What causes delays at each hour of the day? (national)
-- Late flights only (15+ min). October included: this question
-- doesn't use airport names, so the airport-code problem doesn't apply.
-- ------------------------------------------------------------
SELECT
    scheduled_departure / 100 AS departure_hour,
    COUNT(*) AS late_flights,
    ROUND(100.0 * SUM(late_aircraft_delay) / SUM(arrival_delay), 1) AS late_aircraft_pct,
    ROUND(100.0 * SUM(airline_delay)       / SUM(arrival_delay), 1) AS airline_pct,
    ROUND(100.0 * SUM(air_system_delay)    / SUM(arrival_delay), 1) AS air_system_pct,
    ROUND(100.0 * SUM(weather_delay)       / SUM(arrival_delay), 1) AS weather_pct
FROM flights
WHERE arrival_delay >= 15
GROUP BY departure_hour
HAVING COUNT(*) >= 1000
ORDER BY departure_hour;


-- RESULT: Late-aircraft share of delay rises from 3.7% (5 AM) to ~50%
-- (8 PM). Airline-caused share falls from 63.7% to ~25%.
-- CONCLUSION: Delays snowball through the day. Early-morning delays are
-- mostly within the airline's control, and fixing them prevents
-- delays that spread to later flights.