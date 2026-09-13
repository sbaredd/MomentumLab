# MomentumLab Candidate Ranking V1 - Feature Architecture Freeze

## Status

FROZEN FOR OUT-OF-SAMPLE VALIDATION

Candidate Ranking V1 feature discovery is complete.

The development sample must no longer be used to add features, optimize
thresholds, or tune ranking weights.

Future observations will be treated as out-of-sample validation evidence.

## Purpose

Candidate Ranking operates only after Candidate Selection V1 eligibility
has been established.

Candidate Selection answers:

Which securities are currently valid setup candidates?

Candidate Ranking answers:

Among those eligible candidates, which setups currently show stronger
evidence of near-term breakout readiness?

The research outcome used for Candidate Ranking is breakout occurrence
within the following five trading sessions.

## Candidate Selection V1 Prerequisite

A security must first satisfy Candidate Selection V1:

SR09 episode_status = ACTIVE

AND breakout_state = BELOW_PIVOT

AND pivot_proximity_pct >= -4.0

AND pivot_proximity_pct < 0

Candidate Ranking does not modify these eligibility conditions.

## Candidate Ranking V1 Architecture

### CR01 - Pivot Proximity

Status: CORE RANKING DIMENSION

Feature:

pivot_proximity_pct

Interpretation:

Measures where the current price is relative to the active pivot.

Development evidence showed a strong relationship between proximity and
five-session breakout probability.

First-V1-entry development results:

| Proximity | Entries | Breakouts | Breakout Rate |
|-----------|---------|-----------|---------------|
| 0-1% | 19 | 15 | 78.95% |
| 1-2% | 44 | 14 | 31.82% |
| 2-3% | 49 | 14 | 28.57% |
| 3-4% | 41 | 9 | 21.95% |

CR01 forms the primary ordering dimension.

### CR03 - Pre-Breakout 5-Day Progression

Status: SUPPORTING RANKING DIMENSION

Feature:

prebreakout_5d_return_pct

Development research split:

- progression < 2%: 108 entries, 28 breakouts, 25.93%
- progression >= 2%: 45 entries, 24 breakouts, 53.33%

The 2% value is retained as a research split for validation.

It is not a Candidate Selection gate.

CR03 describes whether price is making meaningful progress toward the
opportunity.

### CR06 - Recent Volume Participation

Status: SUPPORTING RANKING DIMENSION

Feature:

recent_5_volume_vs_20d_pct

Development quartile results:

| Quartile | Volume vs 20D | Entries | Breakouts | Breakout Rate |
|----------|---------------|---------|-----------|---------------|
| Q1 | 36.82-71.81% | 39 | 13 | 33.33% |
| Q2 | 72.30-92.57% | 38 | 7 | 18.42% |
| Q3 | 92.97-116.93% | 38 | 12 | 31.58% |
| Q4 | 117.14-205.33% | 38 | 20 | 52.63% |

The highest-participation quartile remained stronger after separate
controls for CR01 proximity and CR03 progression.

The observed Q4 boundary near 117% is sample-derived.

It is NOT frozen as a production threshold.

CR06 represents participation building behind the setup.

## Hierarchical Interpretation

Candidate Ranking V1 is not assumed to be a simple additive score.

The development evidence supports the following hierarchy:

Candidate Selection V1
    -> CR01 Pivot Proximity
        -> CR03 Price Progression
        -> CR06 Volume Participation

CR01 determines the opportunity zone.

CR03 and CR06 provide supporting evidence about the quality of the
approach to the pivot.

No assumption is made that the three features should receive equal or
linear weights.

## Combined Development Evidence

The combined validation showed that proximity remains the dominant
dimension.

The 0-1% proximity cohort produced strong breakout conversion across
multiple progression and participation states.

CR03 and CR06 provided greater differentiation when candidates were
farther from the pivot.

A recurring weaker pattern was:

farther from pivot
+ weak progression
+ normal/low participation

This pattern is retained as research evidence only and is not frozen as a
production exclusion rule.

Small high-conversion cells in the combined matrix must not be interpreted
as deterministic trading rules.

## Contextual Feature

### CR04 - Pivot Proximity Direction

Status: CONTEXT ONLY

Feature:

pivot_proximity_direction

Approaching the pivot showed useful separation primarily when price
progression was weak.

Once progression was strong, direction did not provide meaningful
additional separation.

CR04 is therefore not an independent V1 ranking dimension.

It may later be used as contextual information or a tie-breaker.

## Features Excluded from Candidate Ranking V1

### CR05 - Recent Range / ATR

Status: DEFERRED

No stable monotonic relationship was demonstrated.

It remains a descriptive structural feature.

### SR08 - Structural Entry Risk

Status: EXCLUDED FROM BREAKOUT-PROBABILITY RANKING

Feature:

pivot_to_stop_risk_atr

Structural risk did not demonstrate a useful monotonic relationship with
five-session breakout occurrence.

SR08 answers a different question:

If the candidate is traded, how much structural risk must be accepted?

It is retained for downstream tradeability, execution, stop placement,
and position-sizing research.

### Recent Close Tightness

Feature:

recent_5_close_tightness_pct

Status: NOT PROMOTED

Close tightness was strongly entangled with CR03 price progression.

Of the 45 strong-progression observations, 44 occurred in the looser-close
half of the sample.

The feature therefore risks double-counting price behavior already
represented by CR03.

It is excluded from Candidate Ranking V1.

## Candidate Ranking V1 Frozen Feature Set

CORE:

CR01 - Pivot Proximity

SUPPORTING:

CR03 - Pre-Breakout 5-Day Progression

CR06 - Recent Volume Participation

CONTEXT ONLY:

CR04 - Pivot Proximity Direction

DOWNSTREAM EXECUTION / RISK:

SR08 - Structural Entry Risk

## What Is Not Frozen

Candidate Ranking V1 does NOT yet freeze:

- numerical ranking weights
- a point-based ranking score
- production ranking tiers
- a CR06 fixed volume threshold
- execution rules
- entry rules
- stop rules
- position sizing
- portfolio allocation

These require separate validation and design.

## Research Freeze Rules

From this point forward:

1. Do not add Candidate Ranking features using the development sample.

2. Do not optimize the CR03 2% research split on the development sample.

3. Do not convert the CR06 development Q4 boundary into a production
   threshold.

4. Do not assign ranking weights based on the development matrix.

5. Do not promote attractive small-sample combinations into trading rules.

6. Do not modify Candidate Selection V1 based on Candidate Ranking
   validation.

7. Future observations must be treated as out-of-sample evidence.

## Next Phase

The next phase is:

Candidate Ranking V1 Out-of-Sample Validation

The validation mechanism should preserve the frozen feature architecture
and record future candidate observations and subsequent outcomes without
changing the V1 research specification.