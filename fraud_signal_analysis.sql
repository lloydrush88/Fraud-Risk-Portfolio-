-- ============================================================
-- FRAUD SIGNAL ANALYSIS & DETECTION FRAMEWORK
-- Lloyd Rush | Fraud Risk Analytics Portfolio
-- Dataset: PaySim Synthetic Mobile Money Transactions
-- github.com/lloydrush
-- ============================================================


-- ============================================================
-- Q1: TRANSACTION TYPE BREAKDOWN
-- Understand fraud distribution across transaction types
-- ============================================================

SELECT
    type,
    COUNT(*)                              AS txn_count,
    ROUND(SUM(amount), 2)                 AS total_volume,
    ROUND(AVG(amount), 2)                 AS avg_amount,
    SUM(isFraud)                          AS fraud_count,
    ROUND(SUM(isFraud) * 100.0
          / COUNT(*), 4)                  AS fraud_rate_pct
FROM transactions
GROUP BY type
ORDER BY txn_count DESC;


-- ============================================================
-- Q2: AMOUNT DISTRIBUTION — FRAUD VS. LEGITIMATE
-- Do fraudulent transactions differ in size?
-- Scoped to TRANSFER and CASH_OUT where all fraud occurs
-- ============================================================

SELECT
    isFraud,
    COUNT(*)                        AS txn_count,
    ROUND(MIN(amount), 2)           AS min_amount,
    ROUND(AVG(amount), 2)           AS avg_amount,
    ROUND(MAX(amount), 2)           AS max_amount,
    ROUND(SUM(amount), 2)           AS total_amount
FROM transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
GROUP BY isFraud;


-- ============================================================
-- Q3: FULL PRECISION / RECALL / FALSE NEGATIVE FRAMEWORK
-- Complete performance metrics for all three rules
-- ============================================================

WITH flagged AS (
    SELECT
        isFraud,
        amount,
        oldbalanceOrg,
        newbalanceOrig,

        CASE WHEN amount > 1000000
              AND newbalanceOrig = 0
             THEN 1 ELSE 0 END             AS rule1,

        CASE WHEN oldbalanceOrg > 0
              AND newbalanceOrig = 0
              AND amount >= oldbalanceOrg * 0.9
             THEN 1 ELSE 0 END             AS rule2,

        CASE WHEN amount > 1000000
              AND newbalanceOrig = 0
              AND oldbalanceOrg > 0
              AND amount >= oldbalanceOrg * 0.9
             THEN 1 ELSE 0 END             AS both_rules

    FROM transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
),

metrics AS (
    SELECT
        SUM(CASE WHEN rule1 = 1 AND isFraud = 1 THEN 1 ELSE 0 END)      AS r1_tp,
        SUM(CASE WHEN rule1 = 1 AND isFraud = 0 THEN 1 ELSE 0 END)      AS r1_fp,
        SUM(CASE WHEN rule1 = 0 AND isFraud = 1 THEN 1 ELSE 0 END)      AS r1_fn,
        SUM(rule1)                                                        AS r1_total_flags,

        SUM(CASE WHEN rule2 = 1 AND isFraud = 1 THEN 1 ELSE 0 END)      AS r2_tp,
        SUM(CASE WHEN rule2 = 1 AND isFraud = 0 THEN 1 ELSE 0 END)      AS r2_fp,
        SUM(CASE WHEN rule2 = 0 AND isFraud = 1 THEN 1 ELSE 0 END)      AS r2_fn,
        SUM(rule2)                                                        AS r2_total_flags,

        SUM(CASE WHEN both_rules = 1 AND isFraud = 1 THEN 1 ELSE 0 END) AS cb_tp,
        SUM(CASE WHEN both_rules = 1 AND isFraud = 0 THEN 1 ELSE 0 END) AS cb_fp,
        SUM(CASE WHEN both_rules = 0 AND isFraud = 1 THEN 1 ELSE 0 END) AS cb_fn,
        SUM(both_rules)                                                   AS cb_total_flags,

        SUM(isFraud)                                                      AS total_fraud
    FROM flagged
)

SELECT
    'Rule 1 - High Value + Zero Balance'        AS rule_name,
    r1_tp                                        AS true_positives,
    r1_fp                                        AS false_positives,
    r1_fn                                        AS false_negatives,
    r1_total_flags                               AS total_flags,
    ROUND(r1_tp * 100.0 / r1_total_flags, 2)    AS precision_pct,
    ROUND(r1_tp * 100.0 / total_fraud, 2)       AS recall_pct
FROM metrics

UNION ALL

SELECT
    'Rule 2 - Full Account Drain',
    r2_tp, r2_fp, r2_fn, r2_total_flags,
    ROUND(r2_tp * 100.0 / r2_total_flags, 2),
    ROUND(r2_tp * 100.0 / total_fraud, 2)
FROM metrics

UNION ALL

SELECT
    'Combined - Both Rules',
    cb_tp, cb_fp, cb_fn, cb_total_flags,
    ROUND(cb_tp * 100.0 / cb_total_flags, 2),
    ROUND(cb_tp * 100.0 / total_fraud, 2)
FROM metrics;


-- ============================================================
-- Q4: THRESHOLD OPTIMIZATION
-- Test five amount thresholds to find the optimal balance
-- between fraud coverage and false positive rate
-- ============================================================

SELECT
    threshold,
    SUM(CASE WHEN isFraud = 1
             AND amount > threshold
             AND newbalanceOrig = 0
             THEN 1 ELSE 0 END)                         AS fraud_caught,
    ROUND(SUM(CASE WHEN isFraud = 1
                   AND amount > threshold
                   AND newbalanceOrig = 0
                   THEN 1 ELSE 0 END) * 100.0
          / SUM(isFraud), 2)                            AS fraud_coverage_pct,
    SUM(CASE WHEN isFraud = 0
             AND amount > threshold
             AND newbalanceOrig = 0
             THEN 1 ELSE 0 END)                         AS false_positives,
    ROUND(SUM(CASE WHEN isFraud = 0
                   AND amount > threshold
                   AND newbalanceOrig = 0
                   THEN 1 ELSE 0 END) * 100.0
          / SUM(CASE WHEN isFraud = 0
                     THEN 1 ELSE 0 END), 2)             AS false_positive_pct
FROM transactions
CROSS JOIN (
    SELECT 200000  AS threshold UNION ALL
    SELECT 500000  UNION ALL
    SELECT 1000000 UNION ALL
    SELECT 2000000 UNION ALL
    SELECT 5000000
) thresholds
WHERE type IN ('TRANSFER', 'CASH_OUT')
GROUP BY threshold
ORDER BY threshold;


-- ============================================================
-- Q5: TEMPORAL FRAUD DISTRIBUTION
-- Does fraud concentrate at specific points in the month?
-- ============================================================

WITH hourly_stats AS (
    SELECT
        step,
        COUNT(*)                                    AS total_txns,
        SUM(isFraud)                                AS fraud_txns,
        ROUND(SUM(isFraud) * 100.0
              / COUNT(*), 4)                        AS fraud_rate_pct,
        ROUND(SUM(CASE WHEN isFraud = 1
                       THEN amount ELSE 0 END), 2)  AS fraud_volume
    FROM transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
    GROUP BY step
),

period_summary AS (
    SELECT
        CASE
            WHEN step <= 24  THEN 'Days 1'
            WHEN step <= 48  THEN 'Day 2'
            WHEN step <= 72  THEN 'Day 3'
            WHEN step <= 168 THEN 'Days 4-7'
            WHEN step <= 336 THEN 'Week 2'
            WHEN step <= 504 THEN 'Week 3'
            ELSE                  'Week 4'
        END                                         AS period,
        CASE
            WHEN step <= 24  THEN 1
            WHEN step <= 48  THEN 2
            WHEN step <= 72  THEN 3
            WHEN step <= 168 THEN 4
            WHEN step <= 336 THEN 5
            WHEN step <= 504 THEN 6
            ELSE                  7
        END                                         AS sort_order,
        total_txns,
        fraud_txns,
        fraud_rate_pct,
        fraud_volume
    FROM hourly_stats
)

SELECT
    period,
    SUM(total_txns)                                 AS total_txns,
    SUM(fraud_txns)                                 AS fraud_txns,
    ROUND(SUM(fraud_txns) * 100.0
          / SUM(total_txns), 4)                     AS fraud_rate_pct,
    ROUND(AVG(fraud_rate_pct), 4)                   AS avg_hourly_fraud_rate,
    ROUND(SUM(fraud_volume), 2)                     AS fraud_volume
FROM period_summary
GROUP BY period, sort_order
ORDER BY sort_order;


-- ============================================================
-- Q6: FALSE NEGATIVE CHARACTERIZATION
-- What does the fraud we miss look like?
-- ============================================================

WITH flagged AS (
    SELECT
        isFraud,
        amount,
        oldbalanceOrg,
        newbalanceOrig,
        type,
        step,
        CASE WHEN amount > 1000000
              AND newbalanceOrig = 0
             THEN 1 ELSE 0 END             AS rule1,
        CASE WHEN oldbalanceOrg > 0
              AND newbalanceOrig = 0
              AND amount >= oldbalanceOrg * 0.9
             THEN 1 ELSE 0 END             AS rule2
    FROM transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
)

SELECT
    'Rule 1 False Negatives'                AS segment,
    COUNT(*)                                AS count,
    ROUND(MIN(amount), 2)                   AS min_amount,
    ROUND(AVG(amount), 2)                   AS avg_amount,
    ROUND(MAX(amount), 2)                   AS max_amount,
    SUM(CASE WHEN newbalanceOrig = 0
             THEN 1 ELSE 0 END)             AS zero_bal_after,
    SUM(CASE WHEN oldbalanceOrg = 0
             THEN 1 ELSE 0 END)             AS zero_bal_before
FROM flagged
WHERE isFraud = 1 AND rule1 = 0

UNION ALL

SELECT
    'Rule 2 False Negatives',
    COUNT(*),
    ROUND(MIN(amount), 2),
    ROUND(AVG(amount), 2),
    ROUND(MAX(amount), 2),
    SUM(CASE WHEN newbalanceOrig = 0
             THEN 1 ELSE 0 END),
    SUM(CASE WHEN oldbalanceOrg = 0
             THEN 1 ELSE 0 END)
FROM flagged
WHERE isFraud = 1 AND rule2 = 0

UNION ALL

SELECT
    'All Fraud - Baseline',
    COUNT(*),
    ROUND(MIN(amount), 2),
    ROUND(AVG(amount), 2),
    ROUND(MAX(amount), 2),
    SUM(CASE WHEN newbalanceOrig = 0
             THEN 1 ELSE 0 END),
    SUM(CASE WHEN oldbalanceOrg = 0
             THEN 1 ELSE 0 END)
FROM flagged
WHERE isFraud = 1;


-- ============================================================
-- Q7: FINANCIAL IMPACT MODEL
-- Translate detection performance into business dollar terms
-- Assumptions: $35/hr analyst cost, 5 min avg review per flag
-- ============================================================

WITH rule_performance AS (
    SELECT
        SUM(isFraud)                                                AS total_fraud_cases,
        ROUND(AVG(CASE WHEN isFraud = 1
                       THEN amount END), 2)                         AS avg_fraud_amount,
        ROUND(SUM(CASE WHEN isFraud = 1
                       THEN amount ELSE 0 END), 2)                  AS total_fraud_exposure,

        SUM(CASE WHEN amount > 1000000
                  AND newbalanceOrig = 0
                  AND isFraud = 1
                  THEN 1 ELSE 0 END)                                AS r1_fraud_caught,
        ROUND(SUM(CASE WHEN amount > 1000000
                        AND newbalanceOrig = 0
                        AND isFraud = 1
                        THEN amount ELSE 0 END), 2)                 AS r1_value_caught,
        SUM(CASE WHEN amount > 1000000
                  AND newbalanceOrig = 0
                  AND isFraud = 0
                  THEN 1 ELSE 0 END)                                AS r1_fp,

        SUM(CASE WHEN oldbalanceOrg > 0
                  AND newbalanceOrig = 0
                  AND amount >= oldbalanceOrg * 0.9
                  AND isFraud = 1
                  THEN 1 ELSE 0 END)                                AS r2_fraud_caught,
        ROUND(SUM(CASE WHEN oldbalanceOrg > 0
                        AND newbalanceOrig = 0
                        AND amount >= oldbalanceOrg * 0.9
                        AND isFraud = 1
                        THEN amount ELSE 0 END), 2)                 AS r2_value_caught,
        SUM(CASE WHEN oldbalanceOrg > 0
                  AND newbalanceOrig = 0
                  AND amount >= oldbalanceOrg * 0.9
                  AND isFraud = 0
                  THEN 1 ELSE 0 END)                                AS r2_fp,

        SUM(CASE WHEN amount > 1000000
                  AND newbalanceOrig = 0
                  AND oldbalanceOrg > 0
                  AND amount >= oldbalanceOrg * 0.9
                  AND isFraud = 1
                  THEN 1 ELSE 0 END)                                AS cb_fraud_caught,
        ROUND(SUM(CASE WHEN amount > 1000000
                        AND newbalanceOrig = 0
                        AND oldbalanceOrg > 0
                        AND amount >= oldbalanceOrg * 0.9
                        AND isFraud = 1
                        THEN amount ELSE 0 END), 2)                 AS cb_value_caught,
        SUM(CASE WHEN amount > 1000000
                  AND newbalanceOrig = 0
                  AND oldbalanceOrg > 0
                  AND amount >= oldbalanceOrg * 0.9
                  AND isFraud = 0
                  THEN 1 ELSE 0 END)                                AS cb_fp

    FROM transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
),

impact AS (
    SELECT
        total_fraud_cases,
        avg_fraud_amount,
        total_fraud_exposure,

        r1_fraud_caught,
        r1_value_caught,
        r1_fp,
        ROUND(r1_fp * 5.0 / 60 * 35, 2)                           AS r1_review_cost,
        ROUND(r1_value_caught - (r1_fp * 5.0 / 60 * 35), 2)       AS r1_net_benefit,

        r2_fraud_caught,
        r2_value_caught,
        r2_fp,
        ROUND(r2_fp * 5.0 / 60 * 35, 2)                           AS r2_review_cost,
        ROUND(r2_value_caught - (r2_fp * 5.0 / 60 * 35), 2)       AS r2_net_benefit,

        cb_fraud_caught,
        cb_value_caught,
        cb_fp,
        ROUND(cb_fp * 5.0 / 60 * 35, 2)                           AS cb_review_cost,
        ROUND(cb_value_caught - (cb_fp * 5.0 / 60 * 35), 2)       AS cb_net_benefit

    FROM rule_performance
)

SELECT
    'Rule 1 - High Value + Zero Balance'    AS rule,
    total_fraud_cases                        AS total_fraud_in_scope,
    total_fraud_exposure                     AS total_exposure_usd,
    r1_fraud_caught                          AS fraud_cases_caught,
    r1_value_caught                          AS fraud_value_caught_usd,
    r1_fp                                    AS false_positive_reviews,
    r1_review_cost                           AS est_review_cost_usd,
    r1_net_benefit                           AS est_net_benefit_usd
FROM impact

UNION ALL

SELECT
    'Rule 2 - Full Account Drain',
    total_fraud_cases, total_fraud_exposure,
    r2_fraud_caught, r2_value_caught,
    r2_fp, r2_review_cost, r2_net_benefit
FROM impact

UNION ALL

SELECT
    'Combined - Both Rules',
    total_fraud_cases, total_fraud_exposure,
    cb_fraud_caught, cb_value_caught,
    cb_fp, cb_review_cost, cb_net_benefit
FROM impact;


-- ============================================================
-- Q8: SIGNAL CORRELATION ANALYSIS
-- Are the two rules catching the same fraud or different fraud?
-- Scoped to confirmed fraud cases only
-- ============================================================

WITH flagged AS (
    SELECT
        isFraud,
        CASE WHEN amount > 1000000
              AND newbalanceOrig = 0
             THEN 1 ELSE 0 END                  AS rule1,
        CASE WHEN oldbalanceOrg > 0
              AND newbalanceOrig = 0
              AND amount >= oldbalanceOrg * 0.9
             THEN 1 ELSE 0 END                  AS rule2
    FROM transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
    AND isFraud = 1
)

SELECT
    SUM(CASE WHEN rule1 = 1
             AND rule2 = 1 THEN 1 ELSE 0 END)   AS both_rules,
    SUM(CASE WHEN rule1 = 1
             AND rule2 = 0 THEN 1 ELSE 0 END)   AS rule1_only,
    SUM(CASE WHEN rule1 = 0
             AND rule2 = 1 THEN 1 ELSE 0 END)   AS rule2_only,
    SUM(CASE WHEN rule1 = 0
             AND rule2 = 0 THEN 1 ELSE 0 END)   AS neither_rule,
    COUNT(*)                                     AS total_fraud,
    ROUND(SUM(CASE WHEN rule1 = 1
                   AND rule2 = 1
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                         AS both_pct,
    ROUND(SUM(CASE WHEN rule1 = 1
                   AND rule2 = 0
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                         AS rule1_unique_pct,
    ROUND(SUM(CASE WHEN rule1 = 0
                   AND rule2 = 1
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                         AS rule2_unique_pct,
    ROUND(SUM(CASE WHEN rule1 = 0
                   AND rule2 = 0
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                         AS neither_pct
FROM flagged;