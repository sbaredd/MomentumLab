# ============================================================================
# Momentum Lab
# File        : calculate_sector_strength.py
# Version     : 1.0
# Purpose     : Calculate daily Sector Strength Score and Rank
# Input       : trn.sector_index_features_daily
# Output      : trn.sector_strength_daily
# ============================================================================

from pathlib import Path
import os

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
# DATABASE
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# LOAD SECTOR FEATURES
# ============================================================================

def load_sector_features(connection):

    sql = """
        SELECT
            f.index_id,
            f.traded_date,
            r.index_code,
            r.index_name,

            f.close_above_ema_20,
            f.close_above_sma_50,
            f.ema_20_rising,
            f.sma_50_rising,
            f.ema_20_above_sma_50,

            f.distance_from_52w_high_pct,

            f.return_5d_pct,
            f.return_10d_pct,
            f.return_20d_pct,

            f.rs_5d_vs_nifty500_pct,
            f.rs_10d_vs_nifty500_pct,
            f.rs_20d_vs_nifty500_pct,

            f.close_position,

            f.break_prev_high,
            f.break_prev_low,

            f.higher_high_higher_low,
            f.lower_high_lower_low

        FROM trn.sector_index_features_daily f

        JOIN ref.ref_sector_index r
          ON r.index_id = f.index_id

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
            "No sector feature data found."
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
# SS01 - TREND STRUCTURE
# Maximum = 30
# ============================================================================

def calculate_trend_score(row):

    score = 0.0

    if bool_value(
        row["close_above_ema_20"]
    ):
        score += 6

    if bool_value(
        row["close_above_sma_50"]
    ):
        score += 6

    if bool_value(
        row["ema_20_rising"]
    ):
        score += 6

    if bool_value(
        row["sma_50_rising"]
    ):
        score += 6

    if bool_value(
        row["ema_20_above_sma_50"]
    ):
        score += 6

    return score


# ============================================================================
# SS02 - ABSOLUTE MOMENTUM
# Maximum = 20
# ============================================================================

def calculate_absolute_momentum_score(row):

    score = 0.0


    # ------------------------------------------------------------------------
    # SS006 - 5D return
    # Maximum = 5
    # ------------------------------------------------------------------------

    value = row["return_5d_pct"]

    if pd.notna(value):

        if value >= 3:
            score += 5

        elif value >= 2:
            score += 4

        elif value >= 1:
            score += 3

        elif value >= 0:
            score += 2


    # ------------------------------------------------------------------------
    # SS007 - 10D return
    # Maximum = 6
    # ------------------------------------------------------------------------

    value = row["return_10d_pct"]

    if pd.notna(value):

        if value >= 5:
            score += 6

        elif value >= 3:
            score += 5

        elif value >= 2:
            score += 4

        elif value >= 1:
            score += 3

        elif value >= 0:
            score += 2


    # ------------------------------------------------------------------------
    # SS008 - 20D return
    # Maximum = 9
    # ------------------------------------------------------------------------

    value = row["return_20d_pct"]

    if pd.notna(value):

        if value >= 8:
            score += 9

        elif value >= 6:
            score += 8

        elif value >= 4:
            score += 7

        elif value >= 3:
            score += 6

        elif value >= 2:
            score += 5

        elif value >= 1:
            score += 3

        elif value >= 0:
            score += 2


    return score


# ============================================================================
# SS03 - RELATIVE STRENGTH VS NIFTY 500
# Maximum = 35
# ============================================================================

def calculate_relative_strength_score(row):

    score = 0.0


    # ------------------------------------------------------------------------
    # SS009 - 5D RS
    # Maximum = 8
    # ------------------------------------------------------------------------

    value = row["rs_5d_vs_nifty500_pct"]

    if pd.notna(value):

        if value >= 3:
            score += 8

        elif value >= 2:
            score += 7

        elif value >= 1:
            score += 5

        elif value >= 0.5:
            score += 3

        elif value >= 0:
            score += 2


    # ------------------------------------------------------------------------
    # SS010 - 10D RS
    # Maximum = 11
    # ------------------------------------------------------------------------

    value = row["rs_10d_vs_nifty500_pct"]

    if pd.notna(value):

        if value >= 5:
            score += 11

        elif value >= 3:
            score += 9

        elif value >= 2:
            score += 7

        elif value >= 1:
            score += 5

        elif value >= 0:
            score += 2


    # ------------------------------------------------------------------------
    # SS011 - 20D RS
    # Maximum = 16
    # ------------------------------------------------------------------------

    value = row["rs_20d_vs_nifty500_pct"]

    if pd.notna(value):

        if value >= 8:
            score += 16

        elif value >= 6:
            score += 14

        elif value >= 4:
            score += 12

        elif value >= 3:
            score += 10

        elif value >= 2:
            score += 8

        elif value >= 1:
            score += 5

        elif value >= 0:
            score += 2


    return score


# ============================================================================
# SS04 - PRICE BEHAVIOUR
# Maximum = 15
# ============================================================================

def calculate_price_behaviour_score(row):

    score = 0.0


    # ------------------------------------------------------------------------
    # SS012 - Distance from 52W high
    # Maximum = 4
    # ------------------------------------------------------------------------

    value = row[
        "distance_from_52w_high_pct"
    ]

    if pd.notna(value):

        if value >= -3:
            score += 4

        elif value >= -6:
            score += 3

        elif value >= -10:
            score += 1


    # ------------------------------------------------------------------------
    # SS013 - Close position
    # Maximum = 3
    # ------------------------------------------------------------------------

    value = row["close_position"]

    if pd.notna(value):

        if value >= 0.75:
            score += 3

        elif value >= 0.50:
            score += 2

        elif value >= 0.25:
            score += 1


    # ------------------------------------------------------------------------
    # SS014 - Break previous high
    # Maximum = 2
    # ------------------------------------------------------------------------

    if bool_value(
        row["break_prev_high"]
    ):
        score += 2


    # ------------------------------------------------------------------------
    # SS015 - Did NOT break previous low
    # Maximum = 2
    # ------------------------------------------------------------------------

    if not bool_value(
        row["break_prev_low"]
    ):
        score += 2


    # ------------------------------------------------------------------------
    # SS016 - Higher High + Higher Low
    # Maximum = 2
    # ------------------------------------------------------------------------

    if bool_value(
        row["higher_high_higher_low"]
    ):
        score += 2


    # ------------------------------------------------------------------------
    # SS017 - Did NOT form Lower High + Lower Low
    # Maximum = 2
    # ------------------------------------------------------------------------

    if not bool_value(
        row["lower_high_lower_low"]
    ):
        score += 2


    return score


# ============================================================================
# CLASSIFICATION
# ============================================================================

def classify_strength(score):

    if score >= 80:

        return (
            "LEADING",
            "Leading sector"
        )

    elif score >= 65:

        return (
            "STRONG",
            "Strong sector"
        )

    elif score >= 50:

        return (
            "IMPROVING",
            "Improving sector"
        )

    elif score >= 35:

        return (
            "WEAK",
            "Weak sector"
        )

    else:

        return (
            "LAGGING",
            "Lagging sector"
        )


# ============================================================================
# CALCULATE SCORES
# ============================================================================

def calculate_sector_scores(df):

    df = df.copy()


    # ------------------------------------------------------------------------
    # Component scores
    # ------------------------------------------------------------------------

    df["trend_score"] = df.apply(
        calculate_trend_score,
        axis=1
    )

    df["absolute_momentum_score"] = (
        df.apply(
            calculate_absolute_momentum_score,
            axis=1
        )
    )

    df["relative_strength_score"] = (
        df.apply(
            calculate_relative_strength_score,
            axis=1
        )
    )

    df["price_behaviour_score"] = (
        df.apply(
            calculate_price_behaviour_score,
            axis=1
        )
    )


    # ------------------------------------------------------------------------
    # Final score
    # ------------------------------------------------------------------------

    df["sector_strength_score"] = (
        df["trend_score"]
        + df["absolute_momentum_score"]
        + df["relative_strength_score"]
        + df["price_behaviour_score"]
    )


    # ------------------------------------------------------------------------
    # Classification
    # ------------------------------------------------------------------------

    classifications = (
        df["sector_strength_score"]
        .apply(
            classify_strength
        )
    )

    df["strength_code"] = (
        classifications.apply(
            lambda x: x[0]
        )
    )

    df["strength_description"] = (
        classifications.apply(
            lambda x: x[1]
        )
    )


    # ========================================================================
    # DAILY RANK
    #
    # Rank 1 = strongest sector
    #
    # Dense ranking:
    # Same score receives same rank.
    # ========================================================================

    df["sector_rank"] = (
        df.groupby(
            "traded_date"
        )["sector_strength_score"]
        .rank(
            method="dense",
            ascending=False
        )
        .astype(int)
    )


    return df


# ============================================================================
# SAVE TO DATABASE
# ============================================================================

def save_sector_strength(
    connection,
    df
):

    sql = """
        INSERT INTO trn.sector_strength_daily
        (
            index_id,
            traded_date,

            trend_score,
            absolute_momentum_score,
            relative_strength_score,
            price_behaviour_score,

            sector_strength_score,
            sector_rank,

            strength_code,
            strength_description
        )
        VALUES %s

        ON CONFLICT
        (
            index_id,
            traded_date
        )

        DO UPDATE SET

            trend_score =
                EXCLUDED.trend_score,

            absolute_momentum_score =
                EXCLUDED.absolute_momentum_score,

            relative_strength_score =
                EXCLUDED.relative_strength_score,

            price_behaviour_score =
                EXCLUDED.price_behaviour_score,

            sector_strength_score =
                EXCLUDED.sector_strength_score,

            sector_rank =
                EXCLUDED.sector_rank,

            strength_code =
                EXCLUDED.strength_code,

            strength_description =
                EXCLUDED.strength_description,

            updated_date =
                CURRENT_TIMESTAMP;
    """


    values = []

    for _, row in df.iterrows():

        values.append(
            (
                int(row["index_id"]),

                row["traded_date"].date(),

                float(
                    row["trend_score"]
                ),

                float(
                    row[
                        "absolute_momentum_score"
                    ]
                ),

                float(
                    row[
                        "relative_strength_score"
                    ]
                ),

                float(
                    row[
                        "price_behaviour_score"
                    ]
                ),

                float(
                    row[
                        "sector_strength_score"
                    ]
                ),

                int(
                    row["sector_rank"]
                ),

                row["strength_code"],

                row[
                    "strength_description"
                ],
            )
        )


    with connection.cursor() as cursor:

        execute_values(
            cursor,
            sql,
            values,
            page_size=1000
        )


    connection.commit()

    return len(values)


# ============================================================================
# DISPLAY LATEST LEADERBOARD
# ============================================================================

def display_latest_leaderboard(df):

    latest_date = (
        df["traded_date"].max()
    )


    latest = (
        df[
            df["traded_date"]
            == latest_date
        ]
        .sort_values(
            [
                "sector_rank",
                "sector_strength_score",
                "index_code"
            ],
            ascending=[
                True,
                False,
                True
            ]
        )
    )


    print()
    print("=" * 120)

    print(
        f"MOMENTUMLAB - SECTOR LEADERBOARD "
        f"{latest_date.date()}"
    )

    print("=" * 120)


    display_columns = [
        "sector_rank",
        "index_code",
        "trend_score",
        "absolute_momentum_score",
        "relative_strength_score",
        "price_behaviour_score",
        "sector_strength_score",
        "strength_code",
    ]


    print(
        latest[
            display_columns
        ]
        .head(15)
        .to_string(
            index=False
        )
    )


    print("=" * 120)


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    try:

        connection = get_connection()


        # --------------------------------------------------------------------
        # Load historical sector features
        # --------------------------------------------------------------------

        df = load_sector_features(
            connection
        )


        print()
        print(
            f"Loaded {len(df)} "
            f"sector feature rows."
        )

        print(
            f"Sector indices: "
            f"{df['index_id'].nunique()}"
        )

        print(
            f"Date range: "
            f"{df['traded_date'].min().date()} "
            f"to "
            f"{df['traded_date'].max().date()}"
        )


        # --------------------------------------------------------------------
        # Calculate score + rank
        # --------------------------------------------------------------------

        df = calculate_sector_scores(
            df
        )


        # --------------------------------------------------------------------
        # Save historical scores
        # --------------------------------------------------------------------

        saved_rows = save_sector_strength(
            connection,
            df
        )


        print(
            f"Saved {saved_rows} rows "
            f"to trn.sector_strength_daily."
        )


        # --------------------------------------------------------------------
        # Latest leaderboard
        # --------------------------------------------------------------------

        display_latest_leaderboard(
            df
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