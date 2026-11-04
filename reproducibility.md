# Reproducing the Ledgerly Analysis

This repository contains the SQL analysis, synthetic data generator, Power BI dashboard, and supporting files. Large generated data files and the local DuckDB database are excluded from GitHub.

## Requirements

- Python 3.10+
- DuckDB
- pandas
- pyarrow
- numpy
- Power BI Desktop (to open the dashboard)

Install dependencies from the project root:

```powershell
python -m pip install -r requirements.txt
```

## 1. Generate the source data

From the project root, run:

```powershell
python generator/generate.py --seed 42 --key-dir ..\ledgerly-answer-key
```

This generates the request-level fact table and supporting dimension files in `data/`.

The generator also creates a sealed answer key. The command above places it outside the project directory. Do not publish or commit that answer key.

**Important:** The original dataset's random seed was not retained with the published project. Regenerated data will have the same structure and generation logic, but may not reproduce the exact figures reported in the README.

The full dataset contains approximately five million request attempts and may take time and disk space to generate.

## 2. Calculate request-level costs

After data generation, open DuckDB and create or connect to a database named `ledgerly.duckdb` in the project root.

Run the SQL scripts from the project root so their relative file paths resolve correctly.

1. Run `sql/00_foundation/05_calculate_request_cost.sql`. This calculates request-level API costs and writes `data/fact_cost.parquet`.
2. Run `sql/00_foundation/10_create_fact_cost_view.sql` in the same DuckDB database to create the reusable `fact_cost` view.
3. Run the validation scripts in `sql/00_foundation/`.
4. Run `sql/00_foundation/09_reconcile_monthly_cost.sql` to compare calculated costs with the synthetic vendor invoice.

## 3. Run the analysis

Execute the SQL scripts from the project root using DuckDB.

The analysis is organized into:

- `sql/01_spend_baseline/` — monthly spend, model mix, request volume, and usage patterns.
- `sql/02_customer_economics/` — tenant margins, caching opportunities, and savings scenarios.
- `sql/03_decision_analysis/` — vendor commitment scenarios, usage-cap analysis, and forecasting.

Some scripts depend on the `fact_cost` view. Complete the cost calculation and view-creation steps first.

## 4. Refresh Power BI exports

From the project root, run:

```powershell
python prepare_powerbi.py
```

The script expects the local DuckDB database and the required generated data and analysis objects to be available.

Open `powerbi/dashboard.pbix` in Power BI Desktop and refresh the imported CSV data if needed.

## Interpretation notes

- All data is synthetic and intended for portfolio demonstration.
- Forecast outputs are deterministic scenarios, not probability-weighted predictions.
- Caching estimates represent opportunities and scenarios, not realized savings.
- The cap rollout analysis is observational; pre-rollout differences limit causal interpretation.
- The model evaluation sample does not support a valid like-for-like quality comparison across served models.
- Do not commit or publish any `answer_key` files.