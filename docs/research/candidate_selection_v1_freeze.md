# MomentumLab — Candidate Selection V1 Freeze

**Status:** FROZEN  
**Freeze date:** 2026-09-13  
**Pipeline stage:** Candidate Selection  
**Predecessors:** SR01–SR08 Setup Readiness, SR09 Setup Episode Lifecycle  
**Successor:** Candidate Ranking

---

## 1. Purpose

Candidate Selection determines which active setup episodes are sufficiently
close to their structural pivot to become actionable watchlist candidates.

It is deliberately separate from Candidate Ranking.

Candidate Selection answers:

> Is this setup eligible for consideration now?

Candidate Ranking will answer:

> Among eligible candidates, which setups deserve the most attention?

---

## 2. Frozen Candidate Selection V1 Rule

A security is Candidate Selection V1 eligible when:

```text
SR09 episode_status = ACTIVE
AND breakout_state = BELOW_PIVOT
AND pivot_proximity_pct >= -4.0
AND pivot_proximity_pct < 0