# ============================================================================
# Momentum Lab
# File        : calculate_sector_strength_momentum.py
# Version     : 1.0
# Purpose     : Calculate Sector Strength Momentum features SSM001-SSM005
#
# Input       : trn.sector_strength_daily
# Output      : trn.sector_strength_momentum_daily
#
# Notes:
#   - 5D / 10D mean trading observations, not calendar days.
#   - Positive rank change = improving rank.
#   - SSM006 momentum_score and SSM007 momentum_code are intentionally
#     left NULL until the raw features are validated historically.
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
# LOAD SECTOR STRENGTH HISTORY
# ============================================================================

def load_sector_strength(connection):

    sql = """
        SELECT
            s.index_id,
            s.traded_date,
            r.index_code,
            r.index_name,
            s.sector_strength_score,
            s.sector_rank
        FROM trn.sector_strength_daily s
        JOIN ref.ref_sector_index r
          ON r.index_id = s.index_id
        ORDER BY
            s.index_id,
            s.traded_date;
    """

    df = pd.read_sql_query(
        sql,
        connection
    )

    if df.empty:

        raise ValueError(
            "No sector strength history found."
        )

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    df["sector_strength_score"] = pd.to_numeric(
        df["sector_strength_score"],
        errors="coerce"
    )

    df["sector_rank"] = pd.to_numeric(
        df["sector_rank"],
        errors="coerce"
    )

    return df


# ============================================================================
# IMPROVING STREAK
# ============================================================================

def calculate_improving_streak(score_series):

    result = []

    streak = 0

    previous_score = None

    for score in score_series:

        if pd.isna(score):

            streak = 0
            result.append(0)
            previous_score = score
            continue

        if previous_score is None or pd.isna(previous_score):

            streak = 0

        elif score > previous_score:

            streak += 1

        else:

            streak = 0

        result.append(streak)

        previous_score = score

    return result


# ============================================================================
# CALCULATE SSM001-SSM005
# ============================================================================

def calculate_momentum_features(df):

    df = df.copy()

    df = df.sort_values(
        [
            "index_id",
            "traded_date"
        ]
    )


    # ========================================================================
    # SSM001 - SCORE CHANGE 5D
    #
    # Current score - score 5 trading observations ago
    #
    # Positive = improving
    # Negative = deteriorating
    # ========================================================================

    df["score_change_5d"] = (
        df["sector_strength_score"]
        -
        df.groupby(
            "index_id"
        )["sector_strength_score"]
        .shift(5)
    )


    # ========================================================================
    # SSM002 - SCORE CHANGE 10D
    # ========================================================================

    df["score_change_10d"] = (
        df["sector_strength_score"]
        -
        df.groupby(
            "index_id"
        )["sector_strength_score"]
        .shift(10)
    )


    # ========================================================================
    # SSM003 - RANK CHANGE 5D
    #
    # Previous rank - current rank
    #
    # Example:
    # 18 -> 8 = +10
    # Positive = improving
    # ========================================================================

    previous_rank_5d = (
        df.groupby(
            "index_id"
        )["sector_rank"]
        .shift(5)
    )

    df["rank_change_5d"] = (
        previous_rank_5d
        - df["sector_rank"]
    )


    # ========================================================================
    # SSM004 - RANK CHANGE 10D
    # ========================================================================

    previous_rank_10d = (
        df.groupby(
            "index_id"
        )["sector_rank"]
        .shift(10)
    )

    df["rank_change_10d"] = (
        previous_rank_10d
        - df["sector_rank"]
    )


    # ========================================================================
    # SSM005 - IMPROVING STREAK
    #
    # Consecutive sessions where:
    # current sector_strength_score > previous session's score
    #
    # Example:
    #
    # 48 -> 51 -> 55 -> 59
    #
    # streak values:
    #  0     1     2     3
    # ========================================================================

    streak_series = (
        df.groupby(
            "index_id",
            group_keys=False
        )["sector_strength_score"]
        .apply(
            calculate_improving_streak
        )
    )


    # groupby/apply returns lists per group, so flatten cleanly
    streak_values = []

    for values in streak_series:

        streak_values.extend(
            values
        )

    df["improving_streak"] = (
        streak_values
    )


    # ------------------------------------------------------------------------
    # Convert rank changes to nullable integer
    # ------------------------------------------------------------------------

    df["rank_change_5d"] = (
        df["rank_change_5d"]
        .round()
        .astype("Int64")
    )

    df["rank_change_10d"] = (
        df["rank_change_10d"]
        .round()
        .astype("Int64")
    )


    # ------------------------------------------------------------------------
    # SSM006 / SSM007
    #
    # Deliberately left empty until validation.
    # ------------------------------------------------------------------------

    df["momentum_score"] = None

    df["momentum_code"] = None

    df["momentum_description"] = None


    return df


# ============================================================================
# SAVE
# ============================================================================

def save_momentum_features(
    connection,
    df
):

    sql = """
        INSERT INTO trn.sector_strength_momentum_daily
        (
            index_id,
            traded_date,

            sector_strength_score,
            sector_rank,

            score_change_5d,
            score_change_10d,

            rank_change_5d,
            rank_change_10d,

            improving_streak,

            momentum_score,
            momentum_code,
            momentum_description
        )
        VALUES %s

        ON CONFLICT
        (
            index_id,
            traded_date
        )

        DO UPDATE SET

            sector_strength_score =
                EXCLUDED.sector_strength_score,

            sector_rank =
                EXCLUDED.sector_rank,

            score_change_5d =
                EXCLUDED.score_change_5d,

            score_change_10d =
                EXCLUDED.score_change_10d,

            rank_change_5d =
                EXCLUDED.rank_change_5d,

            rank_change_10d =
                EXCLUDED.rank_change_10d,

            improving_streak =
                EXCLUDED.improving_streak,

            momentum_score =
                EXCLUDED.momentum_score,

            momentum_code =
                EXCLUDED.momentum_code,

            momentum_description =
                EXCLUDED.momentum_description,

            updated_date =
                CURRENT_TIMESTAMP;
    """

    values = []

    for _, row in df.iterrows():

        values.append(
            (
                int(
                    row["index_id"]
                ),

                row["traded_date"].date(),

                float(
                    row["sector_strength_score"]
                ),

                int(
                    row["sector_rank"]
                ),

                None
                if pd.isna(
                    row["score_change_5d"]
                )
                else float(
                    row["score_change_5d"]
                ),

                None
                if pd.isna(
                    row["score_change_10d"]
                )
                else float(
                    row["score_change_10d"]
                ),

                None
                if pd.isna(
                    row["rank_change_5d"]
                )
                else int(
                    row["rank_change_5d"]
                ),

                None
                if pd.isna(
                    row["rank_change_10d"]
                )
                else int(
                    row["rank_change_10d"]
                ),

                int(
                    row["improving_streak"]
                ),

                None,
                None,
                None,
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
# DISPLAY LATEST EMERGING SECTORS
# ============================================================================

def display_latest(df):

    latest_date = (
        df["traded_date"].max()
    )


    latest = (
        df[
            df["traded_date"]
            == latest_date
        ]
        .copy()
    )


    # ------------------------------------------------------------------------
    # Sort primarily by 10D rank improvement, then 10D score improvement.
    # ------------------------------------------------------------------------

    latest = latest.sort_values(
        [
            "rank_change_10d",
            "score_change_10d",
            "sector_strength_score"
        ],
        ascending=[
            False,
            False,
            False
        ],
        na_position="last"
    )


    display_columns = [
        "index_code",
        "sector_rank",
        "sector_strength_score",
        "score_change_5d",
        "score_change_10d",
        "rank_change_5d",
        "rank_change_10d",
        "improving_streak",
    ]


    print()
    print("=" * 120)

    print(
        "MOMENTUMLAB - "
        f"SECTOR STRENGTH MOMENTUM {latest_date.date()}"
    )

    print("=" * 120)

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
# DATA QUALITY
# ============================================================================

def print_data_quality(df):

    print()
    print("=" * 120)
    print(
        "SECTOR STRENGTH MOMENTUM - DATA QUALITY"
    )
    print("=" * 120)

    print(
        f"Rows                       : "
        f"{len(df)}"
    )

    print(
        f"Sector indices             : "
        f"{df['index_id'].nunique()}"
    )

    print(
        f"First date                 : "
        f"{df['traded_date'].min().date()}"
    )

    print(
        f"Last date                  : "
        f"{df['traded_date'].max().date()}"
    )

    print(
        f"Valid score change 5D      : "
        f"{df['score_change_5d'].notna().sum()}"
    )

    print(
        f"Valid score change 10D     : "
        f"{df['score_change_10d'].notna().sum()}"
    )

    print(
        f"Valid rank change 5D       : "
        f"{df['rank_change_5d'].notna().sum()}"
    )

    print(
        f"Valid rank change 10D      : "
        f"{df['rank_change_10d'].notna().sum()}"
    )


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    try:

        connection = get_connection()


        print()
        print("=" * 120)
        print(
            "MOMENTUMLAB - "
            "SECTOR STRENGTH MOMENTUM V1"
        )
        print("=" * 120)


        # --------------------------------------------------------------------
        # Load
        # --------------------------------------------------------------------

        df = load_sector_strength(
            connection
        )

        print(
            f"Loaded {len(df)} "
            f"sector-strength observations."
        )


        # --------------------------------------------------------------------
        # Calculate SSM001-SSM005
        # --------------------------------------------------------------------

        df = calculate_momentum_features(
            df
        )


        # --------------------------------------------------------------------
        # Data quality
        # --------------------------------------------------------------------

        print_data_quality(
            df
        )


        # --------------------------------------------------------------------
        # Save
        # --------------------------------------------------------------------

        saved_rows = (
            save_momentum_features(
                connection,
                df
            )
        )

        print()

        print(
            f"Saved {saved_rows} rows "
            f"to "
            f"trn.sector_strength_momentum_daily."
        )


        # --------------------------------------------------------------------
        # Latest emerging sectors
        # --------------------------------------------------------------------

        display_latest(
            df
        )


        print()
        print("=" * 120)
        print(
            "Sector Strength Momentum "
            "features calculated successfully."
        )
        print("=" * 120)


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