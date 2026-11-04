# Ledgerly | LLM Token & Cost Analytics

**Turning LLM usage data into better vendor and product decisions**

## Project Background

Ledgerly is a B2B spend-management SaaS company offering AI features through a per-seat subscription add-on. Between April and September 2026, its LLM API spend increased sharply, putting pressure on margins and raising two questions:

1. **Finance:** Should Ledgerly accept a $360,000 annual vendor commitment in exchange for a 15% discount?
2. **Product:** Should AI usage caps be introduced to protect customer-level margins without discouraging adoption?

### Stakeholders

| Stakeholder | Role | Primary concern |
|---|---|---|
| Adaeze | VP Finance | Vendor commitment, spend exposure and margin |
| Mariam | Director, Product AI | Tenant economics, usage caps and pricing |
| Tunde | Head of Platform Engineering | API efficiency, reliability and operational waste |

As an analyst supporting Finance, Product, and Platform Engineering. The goal was not simply to report token usage, but to turn request-level data into evidence that could guide these decisions.

**Tools:** SQL, DuckDB, Python, Power BI

**Dataset:** 5.07 million synthetic API request attempts across April–September 2026.

## Executive Summary

LLM spend reached **$32,399 in September**, equivalent to an annualized run rate of approximately **$388,789**. The increase was driven largely by higher request volume: monthly attempts grew more than sevenfold between April and September.

The analysis also identified opportunities to improve caching and highlighted customers whose AI add-on revenue did not cover their customer-facing AI costs. However, the evidence does not support treating the full estimated savings opportunity as guaranteed.

**The central takeaway:** Ledgerly should avoid making a long-term vendor commitment based on September spend alone, and should test targeted usage controls before introducing broad customer-facing caps.

## Key Findings

### 1. Spend and usage growth

- Total calculated API cost was **$118,900.57** across the six-month period.
- Monthly request attempts increased from **205,482 in April to 1.53 million in September**.
- Average tokens per request increased by approximately **4.5%**, meaning higher volume was the larger contributor to overall growth.
- The largest model, `lg-1`, accounted for approximately **77% of total spend**.

### 2. Customer-level AI economics

- The analysis identified **9 tenants** with AI add-on margins below zero for at least two consecutive observed months after their first observed month: 8 Starter and 1 Growth.
- September customer-facing attempts per seat were highest for Starter tenants: **67**, compared with 58 for Growth and 45 for Scale.
- This points to a potential mismatch between usage and monetization, particularly among some Starter customers.

### 3. Caching and cost efficiency

- The model-level analysis estimated up to **$93,882.78** in additional six-month caching savings under an optimistic upper-bound assumption.
- A separate feature-level analysis identified approximately **$38,990** in potential caching opportunity.
- Applying 10%, 25%, and 40% capture assumptions to that opportunity produced estimated six-month savings of approximately **$3,899, $9,748, and $15,596**, respectively.

These are scenarios, not realized savings. Actual results depend on whether repeated prompts can be cached without affecting product behavior.

### 4. Vendor commitment and usage caps

- Under the flat-usage, no-optimization scenario, the 12-month forecast estimated **$388,789** in list-price spend. The proposed commitment would cost $360,000, a potential saving of approximately **$28,789**.
- Under a flat scenario with 30% usage reduction, the commitment would cost approximately **$87,847 more** than pay-as-you-go.
- The cap rollout analysis showed declines in usage metrics across rollout waves, but pre-existing differences between groups prevent a confident causal conclusion.

## Recommendations

| Priority | Action | Owner | Expected impact |
|---|---|---|---|
| **1 – High** | Renegotiate the $360,000 commitment. Seek a lower minimum, a usage-based discount, or a flexibility clause before signing. | VP Finance | Reduces the risk of paying for unused committed capacity if optimization lowers demand. |
| **2 – High** | Run a controlled caching improvement pilot, starting with high-volume models and features identified in the opportunity analysis. | Head of Platform Engineering | Tests whether a portion of the estimated $3,899–$15,596 six-month savings scenario can be captured. |
| **3 – High** | Review the 9 persistently underwater tenants and investigate usage patterns, plan fit, and add-on pricing before applying caps. | Director of Product (AI) | Targets poor-margin usage while reducing the risk of harming adoption across all customers. |
| **4 – Medium** | Run a randomized or better-matched Q1 usage-cap pilot, with adoption and reliability guardrails. | Product + Platform Engineering | Establishes stronger evidence on whether caps reduce cost without damaging engagement. |
| **5 – Medium** | Monitor model-level spend and evaluate routing opportunities using a properly matched quality dataset. | Head of Platform Engineering | Identifies potential model-cost savings without assuming cheaper models deliver equivalent results. |

## Data and Method

The dataset contains **5,067,031 request attempts** across six months, alongside tenant, feature, model-pricing, cap-rollout, and vendor-invoice data.

The analysis used an effective-dated pricing join to calculate request costs, accounting for cached input tokens, output tokens, billed failures, and excluded rate-limited requests. Calculated costs reconciled to the synthetic vendor invoice with a **$0 variance** for the period.

The SQL work is organized around the business questions:

- `sql/00_foundation/` — cost calculation, validation, invoice reconciliation, and reusable views.
- `sql/01_spend_baseline/` — monthly spend, model mix, request volume, and customer-facing versus internal usage.
- `sql/02_customer_economics/` — tenant margins, caching opportunities, savings scenarios, and underwater-tenant validation.
- `sql/03_decision_analysis/` — vendor commitment scenarios, break-even analysis, cap impact, and the 12-month forecast.

Supporting Python scripts prepare the Power BI exports and run SQL queries. The dashboard presents the Finance vendor decision and Product usage-and-margin analysis.

## Assumptions and Caveats

- **Synthetic data:** The dataset is generated for portfolio analysis. Findings demonstrate analytical methods; they are not claims about a real company's performance.
- **Vendor forecast:** The 12-month outputs are deterministic scenarios, not probability-weighted forecasts. They do not establish the probability or expected cost of a commitment shortfall.
- **Caching:** The $93,882.78 estimate is an optimistic upper bound. The feature-level opportunity and capture scenarios are more conservative planning inputs, but still require validation through implementation.
- **Usage caps:** Rollout waves were not randomized and had different pre-rollout patterns. The estimated effects are descriptive, not definitive causal evidence.
- **Model quality:** The evaluation sample did not provide a valid like-for-like comparison across the served models, so it was not used to claim that model routing would preserve quality.
- **Margin definition:** Tenant AI margin compares AI add-on MRR with customer-facing API cost. It is not total customer profitability.

## Project Files

```text
ledgerly-token-cost-analytics/
├── README.md
├── reproducibility.md
├── requirements.txt
├── .gitignore
├── generator/
│   └── generate.py
├── data/
│   ├── cap_rollout.parquet
│   ├── dim_feature.parquet
│   ├── dim_price.parquet
│   ├── dim_tenant.parquet
│   ├── eval_sample.parquet
│   └── vendor_invoice.csv
├── sql/
│   ├── 00_foundation/
│   ├── 01_spend_baseline/
│   ├── 02_customer_economics/
│   └── 03_decision_analysis/
├── powerbi/
│   ├── dashboard.pbix
│   └── exports/
├── prepare_powerbi.py
└── POWERBI_EXPORT_README.md
```

The SQL folders contain the selected analysis and the supporting cost-validation steps needed to reproduce the findings. Exploratory profiling, duplicate diagnostics, and intermediate queries that do not support the two main decisions have been left out of this portfolio copy. The original SQL filenames are preserved.

Note: Large generated request level and cost level Parquet files, along with the local DuckDB database, are excluded from this repository to keep the GitHub project lightweight. The generation script and SQL cost calculation workflow are retained for reproducibility. These files are generated locally and are not included in the repository.