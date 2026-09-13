# MomentumLab Candidate Ranking Research

## Status

Research in progress.

Candidate Selection V1 is frozen separately. Candidate Ranking must not
change Candidate Selection eligibility.

## Research Outcome CR01 - Pivot Proximity

Status: SUPPORTED

Pivot proximity has a strong relationship with 5-session breakout
probability.

Candidate Selection V1 therefore restricts candidates to stocks trading
0-4% below the active pivot.

Within the eligible 0-4% range, proximity may also be used as a ranking
signal.

## Research Outcome CR03 - Pre-Breakout 5-Day Progression

Feature:

prebreakout_5d_return_pct

Observed result:

- Progression < 2%:
  - Entries: 108
  - Breakouts: 28
  - Breakout rate: 25.93%

- Progression >= 2%:
  - Entries: 45
  - Breakouts: 24
  - Breakout rate: 53.33%

Conclusion:

Pre-breakout 5-day progression >= 2% is currently a strong Candidate
Ranking hypothesis.

It approximately doubled observed 5-session breakout conversion relative
to candidates below 2% progression.

Status: PROMOTED TO RANKING CANDIDATE

No ranking weight has been assigned yet.

## Research Outcome CR05 - Recent Range / ATR

Feature:

recent_5_range_pct / atr_pct

Initial band analysis suggested elevated breakout conversion in the
2.5-3.0 range/ATR band.

This was tested further inside the strong-progression cohort
(prebreakout_5d_return_pct >= 2%).

Quartile results:

| Quartile | Range / ATR | Entries | Breakouts | Breakout Rate |
|----------|-------------|---------|-----------|---------------|
| Q1 | 1.46-2.11 | 12 | 6 | 50.00% |
| Q2 | 2.17-2.69 | 11 | 6 | 54.55% |
| Q3 | 2.71-3.27 | 11 | 5 | 45.45% |
| Q4 | 3.32-5.46 | 11 | 7 | 63.64% |

Conclusion:

No stable monotonic relationship was observed.

The earlier apparent 2.5-3.0 sweet spot is not sufficient evidence for
a ranking rule.

Status: DEFERRED

CR05 remains available as a descriptive structural feature but will not
currently contribute to Candidate Ranking.

## Research Discipline

Do not:

- assign ranking weights yet;
- optimize CR05 thresholds further on the current sample;
- convert attractive small-sample cells into production rules;
- modify Candidate Selection V1 based on Candidate Ranking research.

Each additional ranking feature must demonstrate incremental information
beyond the already-supported signals.

## Research Outcome CR06 - Recent Volume Participation

Feature:

recent_5_volume_vs_20d_pct

### Initial Quartile Test

The feature was evaluated using quartiles across the same first-V1-entry
episode sample.

| Quartile | Volume vs 20D | Entries | Breakouts | Breakout Rate |
|----------|---------------|---------|-----------|---------------|
| Q1 | 36.82-71.81% | 39 | 13 | 33.33% |
| Q2 | 72.30-92.57% | 38 | 7 | 18.42% |
| Q3 | 92.97-116.93% | 38 | 12 | 31.58% |
| Q4 | 117.14-205.33% | 38 | 20 | 52.63% |

The relationship was not monotonic in the conventional volume dry-up
direction.

The highest-volume quartile produced the strongest observed breakout
conversion.

### Independence from CR03 - Price Progression

Q4 remained strong after separating candidates by
prebreakout_5d_return_pct.

For progression >= 2%:

- Q4: 18 entries
- Breakouts: 11
- Breakout rate: 61.11%

For progression < 2%:

- Q4: 20 entries
- Breakouts: 9
- Breakout rate: 45.00%

Therefore the Q4 effect was not explained solely by strong pre-breakout
price progression.

### Independence from CR01 - Pivot Proximity

Q4 was compared with Q1-Q3 within each Candidate Selection V1 proximity
band.

| Proximity | Q1-Q3 Rate | Q4 Rate |
|-----------|------------|---------|
| 0-1% | 76.92% | 83.33% |
| 1-2% | 21.62% | 85.71% |
| 2-3% | 25.81% | 33.33% |
| 3-4% | 17.65% | 42.86% |

Q4 outperformed Q1-Q3 in all four proximity bands.

The individual cells are small and must not be converted directly into
trading rules.

### Interpretation

For Candidate Ranking, the evidence currently favors elevated recent
participation rather than volume dry-up.

This does not invalidate volume contraction as a chart-quality concept.
It indicates that, among Candidate Selection V1 eligible securities,
higher recent participation may contain information about the probability
of crossing the pivot within the next five sessions.

The current Q4 boundary of approximately 117% is sample-derived and must
not be treated as a production threshold.

### Conclusion

Status: PROMOTED TO RANKING CANDIDATE

CR06 has demonstrated incremental information after controlling separately
for:

- CR01 pivot proximity
- CR03 pre-breakout price progression

No ranking weight or production threshold has been assigned.

Further threshold optimization on the current sample is intentionally
stopped to avoid threshold mining.
## Research Outcome CR08 - Structural Entry Risk

Feature:

pivot_to_stop_risk_atr

### Quartile Test

Structural entry risk was evaluated using quartiles across the same
first-V1-entry episode sample.

| Quartile | Structural Risk | Entries | Breakouts | Breakout Rate |
|----------|-----------------|---------|-----------|---------------|
| Q1 | 1.08-1.73 ATR | 39 | 11 | 28.21% |
| Q2 | 1.75-2.21 ATR | 38 | 12 | 31.58% |
| Q3 | 2.22-2.96 ATR | 38 | 15 | 39.47% |
| Q4 | 3.01-5.69 ATR | 38 | 14 | 36.84% |

### Interpretation

Lower structural entry risk did not predict a higher probability of
crossing the pivot within the following five sessions.

Breakout conversion increased from Q1 through Q3 and declined only
slightly in Q4.

There is therefore no evidence of a useful monotonic relationship between
lower structural risk and near-term breakout occurrence.

### Separation of Concerns

SR08 answers a different question from the supported Candidate Ranking
features.

Candidate Ranking asks:

Which eligible setup is more likely to break out?

Structural entry risk asks:

If the setup is traded, how much structural risk must be accepted?

A candidate can therefore have high breakout probability while still
requiring an unattractive stop distance.

SR08 should not be forced into the breakout-probability ranking model
solely because structural risk is important to trade execution.

### Conclusion

Status: NOT SUPPORTED AS BREAKOUT-PROBABILITY RANKING FACTOR

SR08 remains valuable for downstream research into:

- tradeability
- entry quality
- stop placement
- position sizing
- expected reward relative to structural risk

Further CR08 threshold optimization and interaction mining on the current
Candidate Ranking sample are intentionally stopped.

SR08 is retained as an execution/risk feature rather than promoted to
Candidate Ranking.
