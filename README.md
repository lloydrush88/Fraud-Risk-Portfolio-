# Fraud Signal Analysis & Detection Framework

**Lloyd Rush** | Fraud Risk & Trust Safety Analyst
[linkedin.com/in/lloydrush](https://linkedin.com/in/lloydrush) · [lloydrush88@gmail.com](mailto:lloydrush88@gmail.com)

---

## 📊 [View Live Tableau Dashboard →](https://public.tableau.com/views/FraudSignalAnalysis/FraudDetectionFramework)

*Interactive visualizations: fraud distribution by type, threshold tradeoff curve, rule precision and recall comparison, and financial impact summary*

---

## Overview

Across 6.3 million synthetic mobile money transactions, this analysis identified **$12.06 billion in fraud exposure** — and designed a layered detection framework that captures **$8.96B of it at an estimated operational review cost of $183K**.

This project applies the analytical approach I use in real fraud operations work: interrogate the data, test candidate signals, eliminate weak ones with documented reasoning, design deployable detection rules, measure performance honestly, and translate findings into business-ready recommendations. All analysis is written in SQL against the PaySim dataset — a realistic simulation of 30 days of mobile money transactions.

---

## Dataset

**Source:** [PaySim — Kaggle](https://www.kaggle.com/datasets/ealaxi/paysim1)
**Size:** 6,362,620 transactions | 30-day simulation
**Transaction types:** CASH_IN, CASH_OUT, DEBIT, PAYMENT, TRANSFER
**Key columns:** `step`, `type`, `amount`, `nameOrig`, `oldbalanceOrg`, `newbalanceOrig`, `nameDest`, `oldbalanceDest`, `newbalanceDest`, `isFraud`

---

## Key Findings

### Finding 1 — Fraud Is 100% Concentrated in TRANSFER and CASH_OUT — All Other Types Are Clean

TRANSFER has a 0.77% fraud rate. CASH_OUT has a 0.18% fraud rate. PAYMENT, CASH_IN, and DEBIT show zero confirmed fraud across 3.6 million transactions. All subsequent analysis is scoped to TRANSFER and CASH_OUT.

### Finding 2 — Fraudulent Transactions Are Nearly 5x Larger Than Legitimate Ones

Average fraudulent transaction: **$1,467,967**
Average legitimate transaction: **$314,115**

Fraudsters consistently hit the $10M platform cap — suggesting deliberate maximum-drain behavior rather than incremental extraction.

### Finding 3 — Full Account Drain Is the Strongest Signal: 97.55% of Fraud Drains 90%+ of Balance in One Transaction

While zero balance after a transaction is common in legitimate activity (90.1%), the combination of a non-zero starting balance and 90%+ drain in a single transaction creates a highly separating fraud signal.

### Finding 4 — Three Candidate Signals Were Tested and Eliminated With Documented Reasoning

- **Zero balance after transaction (standalone):** 90.1% of legitimate transactions also drain to zero — not a useful standalone signal
- **Account velocity (3+ transactions):** Near-zero prevalence in both fraud and legitimate populations — fraudsters operate as one-and-done actors in this dataset
- **Destination account reuse:** Inverted signal — legitimate transactions show *higher* destination reuse (89.75%) than fraudulent ones (51.47%), indicating fraudsters use fresh mule accounts

Eliminating weak signals with reasoning is as analytically important as finding signals that work.

### Finding 5 — Fraud Volume Escalates 19x From Week 1 to Week 4

Fraud rate climbs from 0.11% in Day 1 to 2.09% in Week 4. Total fraud volume in Week 4 ($3.93B) is 19x higher than Day 1 ($211M). One anomaly: Day 3 shows a 72% fraud rate on only 429 transactions — almost certainly a simulation artifact, flagged and excluded from trend conclusions.

### Finding 6 — Rule 1 and Rule 2 Catch Almost Entirely Different Fraud Populations

Signal correlation analysis shows Rule 2 uniquely catches 66.53% of all fraud. Rule 1 adds only 0.04% unique coverage — but when both rules fire simultaneously, the transaction is a high-confidence fraud candidate. The rules are complementary, not redundant: Rule 2 is the coverage layer, Rule 1 is the escalation trigger.

---

## Detection Framework

### Rule 1 — High Value Transaction with Complete Balance Drain

```sql
WHERE type IN ('TRANSFER', 'CASH_OUT')
  AND amount > 1000000
  AND newbalanceOrig = 0
```

| Metric | Value |
|---|---|
| True Positives | 2,551 |
| False Positives | 127,683 |
| Precision | 1.96% |
| Recall | 31.06% |
| Fraud Value Caught | $8.96B |
| Est. Review Cost | $372K |
| Est. Net Benefit | $8.96B |

**Recommended deployment:** Priority escalation queue. Low precision makes it unsuitable as a standalone block — but when combined with Rule 2, it identifies the highest-confidence fraud cases for immediate action.

---

### Rule 2 — Full Account Drain

```sql
WHERE type IN ('TRANSFER', 'CASH_OUT')
  AND oldbalanceOrg > 0
  AND newbalanceOrig = 0
  AND amount >= oldbalanceOrg * 0.9
```

| Metric | Value |
|---|---|
| True Positives | 8,012 |
| False Positives | 1,180,062 |
| Precision | 0.67% |
| Recall | 97.55% |
| Fraud Value Caught | $10.55B |
| Est. Review Cost | $3.44M |
| Est. Net Benefit | $10.54B |

**Recommended deployment:** First-layer monitoring flag or soft step-up trigger. Near-complete fraud coverage makes this the primary detection layer, but the false positive burden ($3.44M review cost) makes it unsuitable as a hard block without additional signal enrichment.

---

### Combined Framework — Both Rules

```sql
WHERE type IN ('TRANSFER', 'CASH_OUT')
  AND amount > 1000000
  AND newbalanceOrig = 0
  AND oldbalanceOrg > 0
  AND amount >= oldbalanceOrg * 0.9
```

| Metric | Value |
|---|---|
| True Positives | 2,548 |
| False Positives | 62,918 |
| Precision | 3.89% |
| Recall | 31.02% |
| Fraud Value Caught | $8.96B |
| Est. Review Cost | $183K |
| Est. Net Benefit | $8.96B |

**Recommended deployment:** Immediate escalation trigger. Delivers Rule 1-equivalent fraud capture while reducing false positive review volume by 51% compared to Rule 1 alone — at an estimated review cost of $183K against $8.96B in fraud value caught. This is the most operationally efficient deployment option.

---

## Financial Impact Summary

**Total fraud exposure in scope: $12.06B across 8,213 confirmed fraud cases**

| Rule | Fraud Value Caught | False Positive Reviews | Est. Review Cost | Est. Net Benefit |
|---|---|---|---|---|
| Rule 1 — High Value + Zero Balance | $8.96B | 127,683 | $372K | $8.96B |
| Rule 2 — Full Account Drain | $10.55B | 1,180,062 | $3.44M | $10.54B |
| Combined — Both Rules | $8.96B | 62,918 | $183K | $8.96B |

*Assumptions: $35/hour analyst cost, 5 minutes average review time per flagged transaction. Figures are illustrative estimates for framework comparison — actual costs vary by organization.*

---

## Rule 3 Candidate Analysis

False negative characterization revealed 41 fraud cases where both rules fail: transactions originating from accounts with zero starting balance. A third rule was tested:

```sql
WHERE type IN ('TRANSFER', 'CASH_OUT')
  AND oldbalanceOrg = 0
  AND amount > 1000000
```

**Result:** Catches 3 fraud cases ($4.4M) at the cost of 64,765 false positive reviews — a precision of 0.005%. Not recommended for standalone deployment. In a production environment with device fingerprinting, account age, and IP geolocation signals, this pattern warrants revisiting as a supplementary signal.

---

## Limitations

| Limitation | Production Implication |
|---|---|
| PaySim is synthetic — labels are algorithmically generated | Real fraud patterns are more varied and adaptive; signal performance would differ on live data |
| No behavioral signals (device, IP, session) | Adding device fingerprinting and geolocation would meaningfully improve Rule 2 precision |
| Compressed time dimension (30 days) | Limits velocity analysis; real deployment would test 6-hour and 24-hour windows |
| $1M threshold optimized for this dataset | Requires calibration against live transaction data before production deployment |
| Review cost assumptions are illustrative | Actual costs depend on team size, tooling, and case complexity |

---

## What I'd Build Next

1. **Rule 2 precision improvement** — test whether adding account age as a qualifying condition reduces false positives without significant recall loss
2. **Shorter velocity windows** — the `step` column supports hourly granularity; test velocity signals within 6-hour and 24-hour windows
3. **Destination account risk scoring** — build a composite risk score based on inbound volume, unique sender count, and account age rather than a binary reuse threshold
4. **Week 4 escalation model** — test whether time-based threshold tightening during high-risk periods improves overall framework performance
5. **Rule 3 with enriched signals** — revisit zero-origin-balance detection with device fingerprint and account age signals added as qualifying conditions

---

## SQL Queries

All 8 queries are in [`fraud_signal_analysis.sql`](./fraud_signal_analysis.sql), organized sequentially and commented to explain the analytical intent of each step. Queries cover:

- Exploratory analysis and fraud distribution
- Signal identification and elimination (3 signals tested, 2 eliminated with reasoning)
- Threshold optimization across 5 levels
- Full precision, recall, and false negative framework
- Temporal fraud distribution
- Financial impact modeling with operational cost assumptions
- Signal correlation analysis

---

## About

I have 10+ years of experience in fraud risk, trust & safety, and payments fraud across Block (Cash App) and Indeed. This project reflects how I think about fraud problems — rigorously, honestly, and always in business terms.

**[View Interactive Dashboard →](https://public.tableau.com/views/FraudSignalAnalysis/FraudDetectionFramework)**
