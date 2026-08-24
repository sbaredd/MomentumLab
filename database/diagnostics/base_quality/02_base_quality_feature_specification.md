# MomentumLab
## Base Quality Feature Specification — V1

### Purpose

This document defines the production feature contract for the Base Quality layer of MomentumLab.

The features defined here are derived from validated diagnostic research conducted in:

- `01b_corrected_pullback_behaviour.sql`
- `01c_post_low_range_contraction.sql`
- `01d_post_low_price_structure.sql`
- `01e_post_low_volume_behaviour.sql`

This specification defines **raw features only**.

No scoring thresholds are defined here.

Scoring thresholds will be introduced only after population-level validation and backtesting.

---

# Base Episode Terminology

MomentumLab uses the following structural terminology:

- `prior_swing_high_date`
- `prior_swing_high`
- `base_low_date`
- `base_low`
- `as_of_date`

The correction episode follows:

```text
Prior Swing High
        ↓
        ↓  Correction
        ↓
Base Low
        ↓
Right-Side Recovery / Consolidation
        ↓
As-Of Date