# ============================================================================
# Momentum Lab
# File        : calculate_market_regime_score.py
# Purpose     : Calculate daily Market Regime Score
# Stage       : Market Regime V1
#
# Input       : trn.broad_index_features_daily
# Output      : trn.market_regime_daily
#
# Score       : 0 - 100
# ============================================================================

from pathlib import Path
import os

import numpy as np
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv


# ============================================================================
# CONFIGURATION
# ============================================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent

load_dotenv(PROJECT_ROOT / ".env")


DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "momentumlab"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD"),
}


# ============================================================================
# INDEX WEIGHTS
# ============================================================================

INDEX_WEIGHTS = {
    "NIFTY_50": 0.15,
    "NIFTY_500": 0.35,
    "NIFTY_MIDCAP_150": 0.25,
    "NIFTY_SMALLCAP_250": 0.25,
}


# ============================================================================
# DATABASE
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# LOAD BROAD INDEX FEATURES
# ============================================================================

def load_features(connection):

    sql = """
        SELECT
            f.traded_date,
            r.index_code,

            f.close_above_ema_20,
            f.close_above_sma_50,
            f.ema_20_rising,
            f.sma_50_rising,
            f.ema_20_above_sma_50,

            f.distance_from_ema_20_pct,
            f.distance_from_52w_high_pct,

            f.return_1d_pct,
            f.return_5d_pct,
            f.return_10d_pct,
            f.return_20d_pct,

            f.close_position,
            f.range_pct,
            f.avg_range_20,
            f.range_expansion_ratio,

            f.break_prev_high,
            f.break_prev_low,
            f.inside_day,
            f.outside_day,
            f.higher_high_higher_low,
            f.lower_high_lower_low

        FROM trn.broad_index_features_daily f

        JOIN ref.ref_broad_index r
          ON r.index_id = f.index_id

        WHERE r.index_code IN (
            'NIFTY_50',
            'NIFTY_500',
            'NIFTY_MIDCAP_150',
            'NIFTY_SMALLCAP_250'
        )

        ORDER BY
            f.traded_date,
            r.index_code;
    """

    df = pd.read_sql_query(
        sql,
        connection
    )

    if df.empty:

        raise ValueError(
            "No broad-index feature data found."
        )

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    return df


# ============================================================================
# SAFE BOOLEAN
# ============================================================================

def bool_value(value):

    if pd.isna(value):
        return False

    return bool(value)


# ============================================================================
# SCORE ONE INDEX
# ============================================================================

def calculate_index_health(row):

    score = 0.0


    # ========================================================================
    # TREND
    # Maximum = 30
    # ========================================================================

    # MR001
    if bool_value(row["close_above_ema_20"]):
        score += 4

    # MR002
    if bool_value(row["close_above_sma_50"]):
        score += 6

    # MR003
    if bool_value(row["ema_20_rising"]):
        score += 5

    # MR004
    if bool_value(row["sma_50_rising"]):
        score += 6

    # MR005
    if bool_value(row["ema_20_above_sma_50"]):
        score += 6


    # MR007 - Distance from 52-week high

    value = row["distance_from_52w_high_pct"]

    if pd.notna(value):

        if value >= -3:
            score += 3

        elif value >= -6:
            score += 2

        elif value >= -10:
            score += 1


    # ========================================================================
    # MOMENTUM
    # Maximum = 25
    # ========================================================================

    # MR009 - 5 day return

    value = row["return_5d_pct"]

    if pd.notna(value):

        if value > 2:
            score += 5

        elif value >= 0:
            score += 3


    # MR010 - 10 day return

    value = row["return_10d_pct"]

    if pd.notna(value):

        if value > 3:
            score += 8

        elif value >= 1:
            score += 6

        elif value >= 0:
            score += 3


    # MR011 - 20 day return

    value = row["return_20d_pct"]

    if pd.notna(value):

        if value > 5:
            score += 12

        elif value >= 2:
            score += 9

        elif value >= 0:
            score += 5


    # ========================================================================
    # PRICE BEHAVIOUR
    # Maximum = 20
    # ========================================================================

    # MR012 - Close position

    value = row["close_position"]

    if pd.notna(value):

        if value >= 0.75:
            score += 5

        elif value >= 0.50:
            score += 3

        elif value >= 0.25:
            score += 1


    # MR015 - Break previous high

    if bool_value(row["break_prev_high"]):
        score += 3


    # MR016 - Did NOT break previous low

    if not bool_value(row["break_prev_low"]):
        score += 3


    # MR019 - Higher high + higher low

    if bool_value(row["higher_high_higher_low"]):
        score += 5


    # MR020 - Did NOT form lower high + lower low

    if not bool_value(row["lower_high_lower_low"]):
        score += 4


    return score


# ============================================================================
# CALCULATE INDEX SCORES
# ============================================================================

def calculate_index_scores(df):

    df = df.copy()

    df["index_health_score"] = df.apply(
        calculate_index_health,
        axis=1
    )

    return df


# ============================================================================
# GET INDEX ROW
# ============================================================================

def get_index_row(day_df, index_code):

    result = day_df[
        day_df["index_code"] == index_code
    ]

    if result.empty:
        return None

    return result.iloc[0]


# ============================================================================
# PARTICIPATION SCORE
# Maximum = 25
# ============================================================================

def calculate_participation(day_df):

    # ------------------------------------------------------------------------
    # Above SMA50
    # Maximum = 7
    # ------------------------------------------------------------------------

    above_sma_count = (
        day_df["close_above_sma_50"]
        .fillna(False)
        .astype(bool)
        .sum()
    )

    above_sma_score = (
        above_sma_count / 4
    ) * 7


    # ------------------------------------------------------------------------
    # SMA50 Rising
    # Maximum = 6
    # ------------------------------------------------------------------------

    sma_rising_count = (
        day_df["sma_50_rising"]
        .fillna(False)
        .astype(bool)
        .sum()
    )

    sma_rising_score = (
        sma_rising_count / 4
    ) * 6


    # ------------------------------------------------------------------------
    # Above EMA20
    # Maximum = 4
    # ------------------------------------------------------------------------

    above_ema_count = (
        day_df["close_above_ema_20"]
        .fillna(False)
        .astype(bool)
        .sum()
    )

    above_ema_score = (
        above_ema_count / 4
    ) * 4


    # ------------------------------------------------------------------------
    # Positive 10-day return
    # Maximum = 4
    # ------------------------------------------------------------------------

    positive_10d_count = (
        day_df["return_10d_pct"]
        .fillna(-999)
        .gt(0)
        .sum()
    )

    positive_10d_score = (
        positive_10d_count / 4
    ) * 4


    # ------------------------------------------------------------------------
    # Midcap + Smallcap Confirmation
    # Maximum = 4
    #
    # Each receives 2 points if:
    # Close > SMA50 AND 10-day return > 0
    # ------------------------------------------------------------------------

    mid_small_score = 0.0

    for index_code in [
        "NIFTY_MIDCAP_150",
        "NIFTY_SMALLCAP_250"
    ]:

        row = get_index_row(
            day_df,
            index_code
        )

        if row is not None:

            if (
                bool_value(
                    row["close_above_sma_50"]
                )
                and
                pd.notna(
                    row["return_10d_pct"]
                )
                and
                row["return_10d_pct"] > 0
            ):
                mid_small_score += 2


    participation_score = (
        above_sma_score
        + sma_rising_score
        + above_ema_score
        + positive_10d_score
        + mid_small_score
    )


    return {
        "above_sma50_score": above_sma_score,
        "sma50_rising_score": sma_rising_score,
        "above_ema20_score": above_ema_score,
        "positive_10d_score": positive_10d_score,
        "mid_small_confirmation_score": mid_small_score,
        "participation_score": participation_score,
    }


# ============================================================================
# REGIME CLASSIFICATION
# ============================================================================

def classify_regime(score):

    if score >= 80:

        return (
            "GREEN",
            "Strong momentum environment"
        )

    elif score >= 65:

        return (
            "LIGHT_GREEN",
            "Favorable momentum environment"
        )

    elif score >= 50:

        return (
            "YELLOW",
            "Mixed / selective momentum environment"
        )

    elif score >= 35:

        return (
            "ORANGE",
            "Weak momentum environment"
        )

    else:

        return (
            "RED",
            "Unfavorable momentum environment"
        )


# ============================================================================
# CALCULATE DAILY MARKET REGIME
# ============================================================================

def calculate_market_regime(df):

    results = []

    grouped = df.groupby(
        "traded_date"
    )


    for traded_date, day_df in grouped:

        # We expect exactly four broad indices.

        if len(day_df) != 4:

            print(
                f"Skipping {traded_date.date()} - "
                f"only {len(day_df)} indices found"
            )

            continue


        # --------------------------------------------------------------------
        # Individual index scores
        # --------------------------------------------------------------------

        index_scores = {}

        for index_code in INDEX_WEIGHTS:

            row = get_index_row(
                day_df,
                index_code
            )

            if row is None:

                index_scores[index_code] = 0

            else:

                index_scores[index_code] = (
                    row["index_health_score"]
                )


        # --------------------------------------------------------------------
        # Weighted Index Health
        #
        # Each index health score is already 0-75.
        # Weighted result therefore remains 0-75.
        # --------------------------------------------------------------------

        weighted_index_health = 0.0

        for index_code, weight in INDEX_WEIGHTS.items():

            weighted_index_health += (
                index_scores[index_code]
                * weight
            )


        # --------------------------------------------------------------------
        # Participation
        # --------------------------------------------------------------------

        participation = calculate_participation(
            day_df
        )


        # --------------------------------------------------------------------
        # Final Market Regime Score
        # --------------------------------------------------------------------

        market_regime_score = (
            weighted_index_health
            + participation["participation_score"]
        )


        market_regime_score = min(
            100,
            max(
                0,
                market_regime_score
            )
        )


        regime_code, regime_description = (
            classify_regime(
                market_regime_score
            )
        )


        results.append(
            {
                "traded_date": traded_date.date(),

                "nifty_50_score":
                    index_scores["NIFTY_50"],

                "nifty_500_score":
                    index_scores["NIFTY_500"],

                "nifty_midcap_150_score":
                    index_scores["NIFTY_MIDCAP_150"],

                "nifty_smallcap_250_score":
                    index_scores["NIFTY_SMALLCAP_250"],

                "weighted_index_health":
                    weighted_index_health,

                "above_sma50_score":
                    participation["above_sma50_score"],

                "sma50_rising_score":
                    participation["sma50_rising_score"],

                "above_ema20_score":
                    participation["above_ema20_score"],

                "positive_10d_score":
                    participation["positive_10d_score"],

                "mid_small_confirmation_score":
                    participation[
                        "mid_small_confirmation_score"
                    ],

                "participation_score":
                    participation["participation_score"],

                "market_regime_score":
                    market_regime_score,

                "regime_code":
                    regime_code,

                "regime_description":
                    regime_description,
            }
        )


    return pd.DataFrame(
        results
    )


# ============================================================================
# SAVE MARKET REGIME
# ============================================================================

def save_market_regime(
    connection,
    df
):

    if df.empty:

        return 0


    sql = """
        INSERT INTO trn.market_regime_daily
        (
            traded_date,

            nifty_50_score,
            nifty_500_score,
            nifty_midcap_150_score,
            nifty_smallcap_250_score,

            weighted_index_health,

            above_sma50_score,
            sma50_rising_score,
            above_ema20_score,
            positive_10d_score,
            mid_small_confirmation_score,

            participation_score,

            market_regime_score,
            regime_code,
            regime_description,

            created_date,
            updated_date
        )
        VALUES %s

        ON CONFLICT (traded_date)

        DO UPDATE SET

            nifty_50_score =
                EXCLUDED.nifty_50_score,

            nifty_500_score =
                EXCLUDED.nifty_500_score,

            nifty_midcap_150_score =
                EXCLUDED.nifty_midcap_150_score,

            nifty_smallcap_250_score =
                EXCLUDED.nifty_smallcap_250_score,

            weighted_index_health =
                EXCLUDED.weighted_index_health,

            above_sma50_score =
                EXCLUDED.above_sma50_score,

            sma50_rising_score =
                EXCLUDED.sma50_rising_score,

            above_ema20_score =
                EXCLUDED.above_ema20_score,

            positive_10d_score =
                EXCLUDED.positive_10d_score,

            mid_small_confirmation_score =
                EXCLUDED.mid_small_confirmation_score,

            participation_score =
                EXCLUDED.participation_score,

            market_regime_score =
                EXCLUDED.market_regime_score,

            regime_code =
                EXCLUDED.regime_code,

            regime_description =
                EXCLUDED.regime_description,

            updated_date =
                CURRENT_TIMESTAMP;
    """


    values = []

    for _, row in df.iterrows():

        values.append(
            (
                row["traded_date"],

                float(row["nifty_50_score"]),
                float(row["nifty_500_score"]),
                float(row["nifty_midcap_150_score"]),
                float(row["nifty_smallcap_250_score"]),

                float(row["weighted_index_health"]),

                float(row["above_sma50_score"]),
                float(row["sma50_rising_score"]),
                float(row["above_ema20_score"]),
                float(row["positive_10d_score"]),
                float(row["mid_small_confirmation_score"]),

                float(row["participation_score"]),

                float(row["market_regime_score"]),

                row["regime_code"],
                row["regime_description"],

                pd.Timestamp.now(),
                pd.Timestamp.now(),
            )
        )


    with connection.cursor() as cursor:

        execute_values(
            cursor,
            sql,
            values
        )


    connection.commit()

    return len(values)


# ============================================================================
# DISPLAY LATEST RESULT
# ============================================================================

def display_latest(df):

    latest = df.sort_values(
        "traded_date"
    ).iloc[-1]


    print()
    print("=" * 100)
    print("MOMENTUMLAB - MARKET REGIME")
    print("=" * 100)

    print(
        f"Date                         : "
        f"{latest['traded_date']}"
    )

    print()

    print(
        f"NIFTY 50 Health              : "
        f"{latest['nifty_50_score']:.2f} / 75"
    )

    print(
        f"NIFTY 500 Health             : "
        f"{latest['nifty_500_score']:.2f} / 75"
    )

    print(
        f"NIFTY MIDCAP 150 Health      : "
        f"{latest['nifty_midcap_150_score']:.2f} / 75"
    )

    print(
        f"NIFTY SMALLCAP 250 Health    : "
        f"{latest['nifty_smallcap_250_score']:.2f} / 75"
    )

    print()

    print(
        f"Weighted Index Health        : "
        f"{latest['weighted_index_health']:.2f} / 75"
    )

    print(
        f"Participation Score          : "
        f"{latest['participation_score']:.2f} / 25"
    )

    print("-" * 100)

    print(
        f"MARKET REGIME SCORE          : "
        f"{latest['market_regime_score']:.2f} / 100"
    )

    print(
        f"REGIME                       : "
        f"{latest['regime_code']}"
    )

    print(
        f"Description                  : "
        f"{latest['regime_description']}"
    )

    print("=" * 100)


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    try:

        connection = get_connection()


        # --------------------------------------------------------------------
        # Load MR001-MR020
        # --------------------------------------------------------------------

        df = load_features(
            connection
        )

        print()
        print(
            f"Loaded {len(df)} broad-index "
            f"feature rows."
        )


        # --------------------------------------------------------------------
        # Calculate individual index health
        # --------------------------------------------------------------------

        df = calculate_index_scores(
            df
        )


        # --------------------------------------------------------------------
        # Calculate market regime
        # --------------------------------------------------------------------

        regime_df = calculate_market_regime(
            df
        )


        print(
            f"Calculated {len(regime_df)} "
            f"market-regime days."
        )


        # --------------------------------------------------------------------
        # Save
        # --------------------------------------------------------------------

        saved_rows = save_market_regime(
            connection,
            regime_df
        )


        print(
            f"Saved {saved_rows} rows "
            f"to trn.market_regime_daily."
        )


        # --------------------------------------------------------------------
        # Latest regime
        # --------------------------------------------------------------------

        display_latest(
            regime_df
        )


    except Exception as exc:

        if connection is not None:

            connection.rollback()

        print()
        print(
            f"ERROR: {exc}"
        )

        raise


    finally:

        if connection is not None:

            connection.close()


if __name__ == "__main__":

    main()