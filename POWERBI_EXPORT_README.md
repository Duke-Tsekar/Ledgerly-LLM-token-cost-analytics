# Ledgerly Power BI export — first step

This script creates compact CSV tables from the existing DuckDB analysis so Power BI does not need to import the 5-million-row request log.

## Where to put the files

Copy `prepare_powerbi.py` into the Ledgerly project root — the same folder that contains `ledgerly.duckdb`, `data/`, and `sql/`.

## Run in VS Code (Windows PowerShell)

From the project root, run:

```powershell
.\.venv\Scripts\python.exe .\prepare_powerbi.py
```

If your virtual environment is in a different location, use that Python executable. The script requires DuckDB and pandas, which are listed in the project's requirements.

## Files created in `powerbi/`

- `monthly_spend.csv` — monthly total, successful and unsuccessful spend, volume, tokens, and cost per attempt.
- `monthly_model_spend.csv` — monthly spend and model share.
- `monthly_audience_spend.csv` — customer-facing, internal, and unattributed spend.
- `tenant_month_margin.csv` — tenant-month add-on MRR, customer-facing cost, AI margin, and a consecutive-underwater flag that excludes the first observed month.
- `cap_rollout_cohorts.csv` — cap rollout wave and start-date lookup.

## Important interpretation notes

- These are Power BI import tables, not a replacement for the raw data or SQL analysis.
- Unattributed requests remain a separate audience category; they are not silently treated as internal.
- The underwater flag is based on observed consecutive calendar months and excludes a tenant's first observed month.
- The cap cohort table is descriptive. The earlier pre-trend checks found the rollout cohorts differed, so do not present the cap rollout as proven causal impact.
- Keep the model-routing evaluation marked inconclusive because `eval_sample` does not match the served model labels.
