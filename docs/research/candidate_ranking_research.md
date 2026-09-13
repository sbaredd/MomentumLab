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