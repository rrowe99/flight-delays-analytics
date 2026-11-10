# Boston Logan Flight Delay Analysis (2015)

An analysis of 5.8 million US domestic flights from 2015, focused on Boston Logan
International Airport (BOS). Built with **PostgreSQL** for data cleaning and analysis
and **Power BI** for the dashboard.

**The question:** How reliable is Boston Logan, what causes its delays, and when and
where are they worst?

![Boston vs large airports](images/page1_airport_comparison.png)

---

## Key Findings

1. **Boston departs on time better than most large airports, but cancels more.**
   BOS ranked 9th of 29 large airports for on-time departures (81.6%), but its
   cancellation rate (2.46%) was about 1.6x the large-airport average (1.57%).

2. **Boston's cancellation problem was a winter problem.**
   In February 2015, BOS cancelled 13.66% of flights vs 4.78% nationally. January and
   February accounted for about two-thirds of BOS cancellations and 85% of its weather
   cancellations. From April on, BOS cancelled at or below the national rate.
   This lines up with Boston's record-breaking 2015 winter
   ([CBS Boston](https://www.cbsnews.com/boston/news/the-most-extreme-winter-month-ever-observed-in-new-england)).

3. **Two-thirds of Boston's delay comes from late incoming planes and air traffic congestion.**
   Late aircraft (33.2%) and air system delays (33.2%) outweigh airline-caused delays (27.7%).
   Weather appears small (5.7%) only because DOT counts non-extreme weather under "air system."

4. **JetBlue accounts for about a third of Boston's delay.**
   JetBlue runs ~35% of BOS flights and causes 36.7% of BOS late minutes, with the highest
   self-caused delay share of any airline (32.9%).

5. **Delays snowball through the day.**
   At BOS, 94.3% of 5 AM departures leave on time vs 67.9% at 7 PM. Nationally, late
   incoming planes cause 3.7% of delay minutes at 5 AM but 50.7% by 8 PM.

6. **Vacation routes are the least reliable.**
   Fort Lauderdale (30.6% late), Las Vegas (30.5%), San Juan (30.0%), and West Palm Beach
   (29.3%) are Boston's worst routes. On FLL and LAS, Spirit flights were late about twice
   as often as JetBlue flights on the same route.

---

## Dashboard

| Page | Question |
|---|---|
| 1. Boston vs Large Airports | How does BOS compare to other large airports? |
| 2. Delay Causes & Airlines | What causes BOS delays, and which airlines are responsible? |
| 3. Seasonality | When in the year are BOS cancellations worst? |
| 4. Time of Day | When during the day do delays build up, and why? |
| 5. Routes | Which BOS routes are least reliable? |

![Delay causes and airlines](images/page2_delay_causes_airlines.png)
![Seasonality](images/page3_seasonality.png)
![Time of day](images/page4_time_of_day.png)
![Routes](images/page5_routes.png)

---

## Data

- **Source:** [2015 Flight Delays and Cancellations](https://www.kaggle.com/datasets/usdot/flight-delays)
  (US Department of Transportation, via Kaggle)
- **Tables:** `flights` (5,819,079 rows), `airlines` (14), `airports` (322)
- `flights.csv` (~565 MB) is not included in this repo because of GitHub's file size limit.
  Download it from the link above and place it in `data/`.

## Tools

- **PostgreSQL / pgAdmin:** schema design, data loading, data quality checks, analysis
  (CTEs, window functions, conditional aggregation, views)
- **Power BI Desktop:** 5-page dashboard built on PostgreSQL views

---

## Data Quality Issues and Decisions

| Issue | Decision |
|---|---|
| All 486,165 October flights use 5-digit numeric airport IDs instead of 3-letter codes | Excluded October from airport-level analysis; kept it for airline-level and national hourly analysis |
| US Airways data ends June 30, 2015 (merger with American) | Compared airlines by rates, not totals; added a Jan-Jun cancellation comparison for fairness |
| Cancelled (89,884) and diverted (15,187) flights have no arrival delay | Excluded from delay averages; included in cancellation rates |
| Delay causes are only recorded for flights 15+ minutes late | Used only those flights for cause analysis; verified the 5 causes sum exactly to total delay |
| 2,969 actual times recorded as 2400 instead of 0000 | Grouped by scheduled departure hour instead of actual time |
| Airport names had garbled characters | Reloaded with UTF-8 encoding |
| One apparent duplicate flight (AA 803, STT, 2015-08-29) | Investigated: two different destinations, both cancelled. Kept both rows |

## Metric Definitions

- **On-time departure:** left less than 15 minutes after schedule (DOT standard), out of flights that operated
- **Late arrival:** arrived 15+ minutes late, out of flights that weren't cancelled or diverted
- **Cancellation rate:** cancelled flights out of all scheduled flights
- **Large airport:** 50,000+ scheduled departures (excluding October)

## Limitations

- One year of data (2015). The winter finding reflects an unusually severe winter and
  may not apply to every year.
- On-time rates only count flights that operated, so airports that cancel more may look
  more punctual than they are.
- The LaGuardia cancellation rate (6.24%) may reflect airlines cancelling short shuttle
  flights first during congestion, but this analysis doesn't prove that.

---

## Project Structure

```
flight-delays-analytics/
├── data/
│   ├── airlines.csv
│   └── airports.csv          (flights.csv downloaded separately)
├── sql/
│   ├── 01_create_tables.sql
│   ├── 02_load_data.sql
│   ├── 03_data_quality_checks.sql
│   ├── 04_analysis.sql
│   └── 05_views_for_powerbi.sql
├── powerbi/
│   └── flight_delays_dashboard.pbix
├── images/
└── README.md
```

## How to Reproduce

1. Download the dataset from Kaggle and place the CSVs in `data/`.
2. In PostgreSQL, create a database named `flights`.
3. Run the SQL files in order: `01` through `05`. File `02` uses `\copy` and must be run
   in psql or pgAdmin's PSQL Tool; update the file paths to match your computer.
4. Open `powerbi/flight_delays_dashboard.pbix` in Power BI Desktop. If prompted, update
   the PostgreSQL connection to your server and credentials, then click **Refresh**.