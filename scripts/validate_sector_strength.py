# ============================================================================
# Momentum Lab
# File        : validate_sector_strength.py
# Version     : 1.0
# Purpose     : Historical validation of Sector Strength V1
#
# Input:
#   trn.sector_strength_daily
#   trn.nse_sector_index_daily
#
# Tests:
#   1. Forward 5D / 10D / 20D sector returns
#   2. Performance by Strength Code
#   3. Performance by Sector Rank Bucket
#   4. Win Rate
#   5. >= 5% move rate
#   6. >= 10% move rate
#
# IMPORTANT:
#   No database writes are performed by this program.
# ============================================================================

from pathlib import Path
import os

import numpy as np
import pandas as pd
import psycopg2
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
# DATABASE CONNECTION
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# LOAD VALIDATION DATA
# ============================================================================

def load_validation_data(connection):

    sql = """
        SELECT
            s.index_id,
            s.traded_date,

            r.index_code,
            r.index_name,

            s.trend_score,
            s.absolute_momentum_score,
            s.relative_strength_score,
            s.price_behaviour_score,

            s.sector_strength_score,
            s.sector_rank,
            s.strength_code,

            d.close_price

        FROM trn.sector_strength_daily s

        JOIN ref.ref_sector_index r
          ON r.index_id = s.index_id

        JOIN trn.nse_sector_index_daily d
          ON d.index_id = s.index_id
         AND d.traded_date = s.traded_date

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
            "No Sector Strength validation data found."
        )

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    return df


# ============================================================================
# CALCULATE FORWARD RETURNS
# ============================================================================

def calculate_forward_returns(df):

    df = df.copy()

    df = df.sort_values(
        [
            "index_id",
            "traded_date"
        ]
    )


    # ------------------------------------------------------------------------
    # IMPORTANT
    #
    # shift(-5) means the close 5 trading observations AFTER the score date.
    #
    # Therefore:
    #
    # Score at T
    #       ↓
    # Future close at T+5
    #       ↓
    # Forward return
    #
    # No future information is used to calculate the score at T.
    # ------------------------------------------------------------------------

    grouped = df.groupby(
        "index_id"
    )["close_price"]


    df["future_close_5d"] = (
        grouped.shift(-5)
    )

    df["future_close_10d"] = (
        grouped.shift(-10)
    )

    df["future_close_20d"] = (
        grouped.shift(-20)
    )


    # ------------------------------------------------------------------------
    # Forward returns
    # ------------------------------------------------------------------------

    df["forward_return_5d_pct"] = (
        (
            df["future_close_5d"]
            / df["close_price"]
        )
        - 1
    ) * 100


    df["forward_return_10d_pct"] = (
        (
            df["future_close_10d"]
            / df["close_price"]
        )
        - 1
    ) * 100


    df["forward_return_20d_pct"] = (
        (
            df["future_close_20d"]
            / df["close_price"]
        )
        - 1
    ) * 100


    return df


# ============================================================================
# RANK BUCKET
# ============================================================================

def assign_rank_bucket(rank):

    if rank <= 5:
        return "01_RANK_01_05"

    elif rank <= 10:
        return "02_RANK_06_10"

    elif rank <= 20:
        return "03_RANK_11_20"

    else:
        return "04_RANK_21_PLUS"


# ============================================================================
# ADD VALIDATION DIMENSIONS
# ============================================================================

def add_validation_dimensions(df):

    df = df.copy()

    df["rank_bucket"] = (
        df["sector_rank"]
        .apply(assign_rank_bucket)
    )

    return df


# ============================================================================
# SUMMARY FUNCTION
# ============================================================================

def create_summary(
    df,
    group_column,
    return_column
):

    working = df[
        [
            group_column,
            return_column
        ]
    ].dropna().copy()


    if working.empty:

        return pd.DataFrame()


    summary = (
        working
        .groupby(
            group_column,
            observed=True
        )
        [return_column]
        .agg(
            sample_size="count",
            avg_return="mean",
            median_return="median",
            min_return="min",
            max_return="max"
        )
        .reset_index()
    )


    # ------------------------------------------------------------------------
    # Win rate
    # ------------------------------------------------------------------------

    win_rate = (
        working
        .assign(
            win=lambda x:
                x[return_column] > 0
        )
        .groupby(
            group_column,
            observed=True
        )["win"]
        .mean()
        .mul(100)
        .reset_index(
            name="win_rate_pct"
        )
    )


    # ------------------------------------------------------------------------
    # >= +5% rate
    # ------------------------------------------------------------------------

    move_5_rate = (
        working
        .assign(
            move_5=lambda x:
                x[return_column] >= 5
        )
        .groupby(
            group_column,
            observed=True
        )["move_5"]
        .mean()
        .mul(100)
        .reset_index(
            name="move_5_pct"
        )
    )


    # ------------------------------------------------------------------------
    # >= +10% rate
    # ------------------------------------------------------------------------

    move_10_rate = (
        working
        .assign(
            move_10=lambda x:
                x[return_column] >= 10
        )
        .groupby(
            group_column,
            observed=True
        )["move_10"]
        .mean()
        .mul(100)
        .reset_index(
            name="move_10_pct"
        )
    )


    summary = summary.merge(
        win_rate,
        on=group_column
    )

    summary = summary.merge(
        move_5_rate,
        on=group_column
    )

    summary = summary.merge(
        move_10_rate,
        on=group_column
    )


    numeric_columns = [
        "avg_return",
        "median_return",
        "min_return",
        "max_return",
        "win_rate_pct",
        "move_5_pct",
        "move_10_pct",
    ]


    summary[numeric_columns] = (
        summary[numeric_columns]
        .round(2)
    )


    return summary


# ============================================================================
# STRENGTH CODE ORDER
# ============================================================================

def sort_strength_summary(summary):

    if summary.empty:
        return summary

    order = {
        "LEADING": 1,
        "STRONG": 2,
        "IMPROVING": 3,
        "WEAK": 4,
        "LAGGING": 5,
    }

    summary = summary.copy()

    summary["_sort_order"] = (
        summary["strength_code"]
        .map(order)
    )

    summary = (
        summary
        .sort_values(
            "_sort_order"
        )
        .drop(
            columns="_sort_order"
        )
    )

    return summary


# ============================================================================
# DISPLAY SUMMARY
# ============================================================================

def print_summary(
    title,
    summary
):

    print()
    print("=" * 120)
    print(title)
    print("=" * 120)

    if summary.empty:

        print(
            "No observations available."
        )

    else:

        print(
            summary.to_string(
                index=False
            )
        )


# ============================================================================
# VALIDATION BY STRENGTH CODE
# ============================================================================

def validate_by_strength_code(df):

    horizons = [
        (
            "5 TRADING DAYS",
            "forward_return_5d_pct"
        ),
        (
            "10 TRADING DAYS",
            "forward_return_10d_pct"
        ),
        (
            "20 TRADING DAYS",
            "forward_return_20d_pct"
        ),
    ]


    for horizon_name, column in horizons:

        summary = create_summary(
            df,
            "strength_code",
            column
        )

        summary = sort_strength_summary(
            summary
        )

        print_summary(
            (
                "SECTOR STRENGTH VALIDATION "
                f"BY STRENGTH CODE - {horizon_name}"
            ),
            summary
        )


# ============================================================================
# VALIDATION BY RANK BUCKET
# ============================================================================

def validate_by_rank_bucket(df):

    horizons = [
        (
            "5 TRADING DAYS",
            "forward_return_5d_pct"
        ),
        (
            "10 TRADING DAYS",
            "forward_return_10d_pct"
        ),
        (
            "20 TRADING DAYS",
            "forward_return_20d_pct"
        ),
    ]


    for horizon_name, column in horizons:

        summary = create_summary(
            df,
            "rank_bucket",
            column
        )

        summary = summary.sort_values(
            "rank_bucket"
        )

        print_summary(
            (
                "SECTOR STRENGTH VALIDATION "
                f"BY RANK BUCKET - {horizon_name}"
            ),
            summary
        )


# ============================================================================
# VALIDATION BY EXACT RANK
# ============================================================================

def validate_by_exact_rank(df):

    summary = create_summary(
        df,
        "sector_rank",
        "forward_return_20d_pct"
    )

    summary = summary.sort_values(
        "sector_rank"
    )

    print_summary(
        (
            "SECTOR STRENGTH VALIDATION "
            "BY EXACT RANK - 20 TRADING DAYS"
        ),
        summary
    )


# ============================================================================
# SCORE CORRELATION
# ============================================================================

def calculate_correlations(df):

    print()
    print("=" * 120)
    print(
        "SECTOR STRENGTH SCORE "
        "VS FUTURE RETURN CORRELATION"
    )
    print("=" * 120)


    columns = [
        "forward_return_5d_pct",
        "forward_return_10d_pct",
        "forward_return_20d_pct",
    ]


    for column in columns:

        working = df[
            [
                "sector_strength_score",
                column
            ]
        ].dropna()


        if len(working) < 2:

            correlation = np.nan

        else:

            correlation = (
                working[
                    "sector_strength_score"
                ]
                .corr(
                    working[column]
                )
            )


        print(
            f"{column:<30}"
            f": {correlation:.4f}"
        )


# ============================================================================
# DATA QUALITY CHECK
# ============================================================================

def print_data_quality(df):

    print()
    print("=" * 120)
    print(
        "VALIDATION DATA QUALITY"
    )
    print("=" * 120)

    print(
        f"Rows loaded               : "
        f"{len(df)}"
    )

    print(
        f"Sector indices            : "
        f"{df['index_id'].nunique()}"
    )

    print(
        f"First date                : "
        f"{df['traded_date'].min().date()}"
    )

    print(
        f"Last date                 : "
        f"{df['traded_date'].max().date()}"
    )

    print(
        f"5D observations           : "
        f"{df['forward_return_5d_pct'].notna().sum()}"
    )

    print(
        f"10D observations          : "
        f"{df['forward_return_10d_pct'].notna().sum()}"
    )

    print(
        f"20D observations          : "
        f"{df['forward_return_20d_pct'].notna().sum()}"
    )


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    try:

        connection = get_connection()


        # --------------------------------------------------------------------
        # Load
        # --------------------------------------------------------------------

        df = load_validation_data(
            connection
        )


        print()
        print("=" * 120)
        print(
            "MOMENTUMLAB - "
            "SECTOR STRENGTH V1 VALIDATION"
        )
        print("=" * 120)

        print(
            f"Loaded {len(df)} observations."
        )


        # --------------------------------------------------------------------
        # Forward returns
        # --------------------------------------------------------------------

        df = calculate_forward_returns(
            df
        )


        # --------------------------------------------------------------------
        # Validation dimensions
        # --------------------------------------------------------------------

        df = add_validation_dimensions(
            df
        )


        # --------------------------------------------------------------------
        # Data quality
        # --------------------------------------------------------------------

        print_data_quality(
            df
        )


        # --------------------------------------------------------------------
        # Strength classification validation
        # --------------------------------------------------------------------

        validate_by_strength_code(
            df
        )


        # --------------------------------------------------------------------
        # Rank validation
        # --------------------------------------------------------------------

        validate_by_rank_bucket(
            df
        )


        # --------------------------------------------------------------------
        # Exact rank diagnostic
        # --------------------------------------------------------------------

        validate_by_exact_rank(
            df
        )


        # --------------------------------------------------------------------
        # Correlation diagnostic
        # --------------------------------------------------------------------

        calculate_correlations(
            df
        )


        print()
        print("=" * 120)
        print(
            "Sector Strength V1 "
            "validation completed."
        )
        print("=" * 120)


    except Exception as exc:

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