# ============================================================================
# Momentum Lab
# File        : calculate_sector_features.py
# Version     : 1.0
# Purpose     : Calculate daily sector-index features SF001-SF027
# Benchmark   : NIFTY 500
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


BENCHMARK_INDEX_CODE = "NIFTY_500"


# ============================================================================
# DATABASE
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# LOAD ACTIVE SECTOR INDICES
# ============================================================================

def load_active_sector_indices(connection):

    sql = """
        SELECT
            index_id,
            index_code,
            index_name
        FROM ref.ref_sector_index
        ORDER BY index_code;
    """

    return pd.read_sql_query(
        sql,
        connection
    )


# ============================================================================
# LOAD SECTOR INDEX DATA
# ============================================================================

def load_sector_data(
    connection,
    index_id
):

    sql = """
        SELECT
            index_id,
            traded_date,
            open_price,
            high_price,
            low_price,
            close_price
        FROM trn.nse_sector_index_daily
        WHERE index_id = %s
        ORDER BY traded_date;
    """

    df = pd.read_sql_query(
        sql,
        connection,
        params=(index_id,)
    )

    if df.empty:

        return df

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    numeric_columns = [
        "open_price",
        "high_price",
        "low_price",
        "close_price",
    ]

    for column in numeric_columns:

        df[column] = pd.to_numeric(
            df[column],
            errors="coerce"
        )

    return df


# ============================================================================
# LOAD NIFTY 500 BENCHMARK
# ============================================================================

def load_benchmark_data(connection):

    sql = """
        SELECT
            d.traded_date,
            d.close_price
        FROM trn.nse_broad_index_daily d
        JOIN ref.ref_broad_index r
            ON r.index_id = d.index_id
        WHERE r.index_code = %s
        ORDER BY d.traded_date;
    """

    df = pd.read_sql_query(
        sql,
        connection,
        params=(BENCHMARK_INDEX_CODE,)
    )

    if df.empty:

        raise ValueError(
            f"No benchmark data found for "
            f"{BENCHMARK_INDEX_CODE}"
        )

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    df["close_price"] = pd.to_numeric(
        df["close_price"],
        errors="coerce"
    )

    # ------------------------------------------------------------------------
    # Benchmark returns
    # ------------------------------------------------------------------------

    df["benchmark_return_5d_pct"] = (
        df["close_price"].pct_change(5) * 100
    )

    df["benchmark_return_10d_pct"] = (
        df["close_price"].pct_change(10) * 100
    )

    df["benchmark_return_20d_pct"] = (
        df["close_price"].pct_change(20) * 100
    )

    return df[
        [
            "traded_date",
            "benchmark_return_5d_pct",
            "benchmark_return_10d_pct",
            "benchmark_return_20d_pct",
        ]
    ]


# ============================================================================
# FEATURE CALCULATION
# ============================================================================

def calculate_features(
    df,
    benchmark_df
):

    df = df.copy()

    # ------------------------------------------------------------------------
    # Previous-day values
    # ------------------------------------------------------------------------

    df["prev_high"] = (
        df["high_price"].shift(1)
    )

    df["prev_low"] = (
        df["low_price"].shift(1)
    )

    df["prev_close"] = (
        df["close_price"].shift(1)
    )


    # ========================================================================
    # SF001 - EMA20
    # ========================================================================

    df["ema_20"] = (
        df["close_price"]
        .ewm(
            span=20,
            adjust=False
        )
        .mean()
    )


    # ========================================================================
    # SF002 - SMA50
    # ========================================================================

    df["sma_50"] = (
        df["close_price"]
        .rolling(
            window=50,
            min_periods=50
        )
        .mean()
    )


    # ========================================================================
    # SF003 - 52-WEEK HIGH
    #
    # Approximation:
    # 252 trading sessions
    # ========================================================================

    df["high_52w"] = (
        df["high_price"]
        .rolling(
            window=252,
            min_periods=1
        )
        .max()
    )


    # ========================================================================
    # SF004 - AVERAGE RANGE 20
    # ========================================================================

    df["daily_range"] = (
        df["high_price"]
        - df["low_price"]
    )

    df["avg_range_20"] = (
        df["daily_range"]
        .rolling(
            window=20,
            min_periods=20
        )
        .mean()
    )


    # ========================================================================
    # SF005 - CLOSE ABOVE EMA20
    # ========================================================================

    df["close_above_ema_20"] = (
        df["close_price"]
        > df["ema_20"]
    )


    # ========================================================================
    # SF006 - CLOSE ABOVE SMA50
    # ========================================================================

    df["close_above_sma_50"] = (
        df["close_price"]
        > df["sma_50"]
    )


    # ========================================================================
    # SF007 - EMA20 RISING
    # ========================================================================

    df["ema_20_rising"] = (
        df["ema_20"]
        > df["ema_20"].shift(1)
    )


    # ========================================================================
    # SF008 - SMA50 RISING
    # ========================================================================

    df["sma_50_rising"] = (
        df["sma_50"]
        > df["sma_50"].shift(1)
    )


    # ========================================================================
    # SF009 - EMA20 ABOVE SMA50
    # ========================================================================

    df["ema_20_above_sma_50"] = (
        df["ema_20"]
        > df["sma_50"]
    )


    # ========================================================================
    # SF010 - DISTANCE FROM EMA20 %
    # ========================================================================

    df["distance_from_ema_20_pct"] = (
        (
            df["close_price"]
            / df["ema_20"]
        )
        - 1
    ) * 100


    # ========================================================================
    # SF011 - DISTANCE FROM 52-WEEK HIGH %
    #
    # 0     = at 52-week high
    # -5    = 5% below 52-week high
    # ========================================================================

    df["distance_from_52w_high_pct"] = (
        (
            df["close_price"]
            / df["high_52w"]
        )
        - 1
    ) * 100


    # ========================================================================
    # SF012 - RETURN 1D %
    # ========================================================================

    df["return_1d_pct"] = (
        df["close_price"]
        .pct_change(1)
        * 100
    )


    # ========================================================================
    # SF013 - RETURN 5D %
    # ========================================================================

    df["return_5d_pct"] = (
        df["close_price"]
        .pct_change(5)
        * 100
    )


    # ========================================================================
    # SF014 - RETURN 10D %
    # ========================================================================

    df["return_10d_pct"] = (
        df["close_price"]
        .pct_change(10)
        * 100
    )


    # ========================================================================
    # SF015 - RETURN 20D %
    # ========================================================================

    df["return_20d_pct"] = (
        df["close_price"]
        .pct_change(20)
        * 100
    )


    # ========================================================================
    # JOIN NIFTY 500 BENCHMARK RETURNS
    # ========================================================================

    df = df.merge(
        benchmark_df,
        on="traded_date",
        how="left"
    )


    # ========================================================================
    # SF016 - 5D RELATIVE STRENGTH VS NIFTY 500
    # ========================================================================

    df["rs_5d_vs_nifty500_pct"] = (
        df["return_5d_pct"]
        - df["benchmark_return_5d_pct"]
    )


    # ========================================================================
    # SF017 - 10D RELATIVE STRENGTH VS NIFTY 500
    # ========================================================================

    df["rs_10d_vs_nifty500_pct"] = (
        df["return_10d_pct"]
        - df["benchmark_return_10d_pct"]
    )


    # ========================================================================
    # SF018 - 20D RELATIVE STRENGTH VS NIFTY 500
    # ========================================================================

    df["rs_20d_vs_nifty500_pct"] = (
        df["return_20d_pct"]
        - df["benchmark_return_20d_pct"]
    )


    # ========================================================================
    # SF019 - CLOSE POSITION
    #
    # 0 = close at low
    # 1 = close at high
    # ========================================================================

    price_range = (
        df["high_price"]
        - df["low_price"]
    )

    df["close_position"] = np.where(
        price_range != 0,
        (
            df["close_price"]
            - df["low_price"]
        )
        / price_range,
        0.5
    )


    # ========================================================================
    # SF020 - RANGE %
    # ========================================================================

    df["range_pct"] = np.where(
        df["prev_close"] != 0,
        (
            df["high_price"]
            - df["low_price"]
        )
        / df["prev_close"]
        * 100,
        np.nan
    )


    # ========================================================================
    # SF021 - RANGE EXPANSION RATIO
    # ========================================================================

    df["range_expansion_ratio"] = np.where(
        df["avg_range_20"] != 0,
        df["daily_range"]
        / df["avg_range_20"],
        np.nan
    )


    # ========================================================================
    # SF022 - BREAK PREVIOUS HIGH
    # ========================================================================

    df["break_prev_high"] = (
        df["high_price"]
        > df["prev_high"]
    )


    # ========================================================================
    # SF023 - BREAK PREVIOUS LOW
    # ========================================================================

    df["break_prev_low"] = (
        df["low_price"]
        < df["prev_low"]
    )


    # ========================================================================
    # SF024 - INSIDE DAY
    # ========================================================================

    df["inside_day"] = (
        (df["high_price"] < df["prev_high"])
        &
        (df["low_price"] > df["prev_low"])
    )


    # ========================================================================
    # SF025 - OUTSIDE DAY
    # ========================================================================

    df["outside_day"] = (
        (df["high_price"] > df["prev_high"])
        &
        (df["low_price"] < df["prev_low"])
    )


    # ========================================================================
    # SF026 - HIGHER HIGH + HIGHER LOW
    # ========================================================================

    df["higher_high_higher_low"] = (
        (df["high_price"] > df["prev_high"])
        &
        (df["low_price"] > df["prev_low"])
    )


    # ========================================================================
    # SF027 - LOWER HIGH + LOWER LOW
    # ========================================================================

    df["lower_high_lower_low"] = (
        (df["high_price"] < df["prev_high"])
        &
        (df["low_price"] < df["prev_low"])
    )


    return df


# ============================================================================
# SAVE FEATURES
# ============================================================================

def save_features(
    connection,
    df
):

    columns = [
        "index_id",
        "traded_date",
        "ema_20",
        "sma_50",
        "high_52w",
        "avg_range_20",
        "close_above_ema_20",
        "close_above_sma_50",
        "ema_20_rising",
        "sma_50_rising",
        "ema_20_above_sma_50",
        "distance_from_ema_20_pct",
        "distance_from_52w_high_pct",
        "return_1d_pct",
        "return_5d_pct",
        "return_10d_pct",
        "return_20d_pct",
        "rs_5d_vs_nifty500_pct",
        "rs_10d_vs_nifty500_pct",
        "rs_20d_vs_nifty500_pct",
        "close_position",
        "range_pct",
        "range_expansion_ratio",
        "break_prev_high",
        "break_prev_low",
        "inside_day",
        "outside_day",
        "higher_high_higher_low",
        "lower_high_lower_low",
    ]

    save_df = df[columns].copy()

    save_df["traded_date"] = (
        save_df["traded_date"].dt.date
    )

    # Convert NaN to None for PostgreSQL
    save_df = save_df.astype(object).where(
        pd.notnull(save_df),
        None
    )

    rows = list(
        save_df.itertuples(
            index=False,
            name=None
        )
    )

    sql = """
        INSERT INTO trn.sector_index_features_daily
        (
            index_id,
            traded_date,
            ema_20,
            sma_50,
            high_52w,
            avg_range_20,
            close_above_ema_20,
            close_above_sma_50,
            ema_20_rising,
            sma_50_rising,
            ema_20_above_sma_50,
            distance_from_ema_20_pct,
            distance_from_52w_high_pct,
            return_1d_pct,
            return_5d_pct,
            return_10d_pct,
            return_20d_pct,
            rs_5d_vs_nifty500_pct,
            rs_10d_vs_nifty500_pct,
            rs_20d_vs_nifty500_pct,
            close_position,
            range_pct,
            range_expansion_ratio,
            break_prev_high,
            break_prev_low,
            inside_day,
            outside_day,
            higher_high_higher_low,
            lower_high_lower_low
        )
        VALUES %s

        ON CONFLICT
        (
            index_id,
            traded_date
        )

        DO UPDATE SET

            ema_20 = EXCLUDED.ema_20,
            sma_50 = EXCLUDED.sma_50,
            high_52w = EXCLUDED.high_52w,
            avg_range_20 = EXCLUDED.avg_range_20,

            close_above_ema_20 =
                EXCLUDED.close_above_ema_20,

            close_above_sma_50 =
                EXCLUDED.close_above_sma_50,

            ema_20_rising =
                EXCLUDED.ema_20_rising,

            sma_50_rising =
                EXCLUDED.sma_50_rising,

            ema_20_above_sma_50 =
                EXCLUDED.ema_20_above_sma_50,

            distance_from_ema_20_pct =
                EXCLUDED.distance_from_ema_20_pct,

            distance_from_52w_high_pct =
                EXCLUDED.distance_from_52w_high_pct,

            return_1d_pct =
                EXCLUDED.return_1d_pct,

            return_5d_pct =
                EXCLUDED.return_5d_pct,

            return_10d_pct =
                EXCLUDED.return_10d_pct,

            return_20d_pct =
                EXCLUDED.return_20d_pct,

            rs_5d_vs_nifty500_pct =
                EXCLUDED.rs_5d_vs_nifty500_pct,

            rs_10d_vs_nifty500_pct =
                EXCLUDED.rs_10d_vs_nifty500_pct,

            rs_20d_vs_nifty500_pct =
                EXCLUDED.rs_20d_vs_nifty500_pct,

            close_position =
                EXCLUDED.close_position,

            range_pct =
                EXCLUDED.range_pct,

            range_expansion_ratio =
                EXCLUDED.range_expansion_ratio,

            break_prev_high =
                EXCLUDED.break_prev_high,

            break_prev_low =
                EXCLUDED.break_prev_low,

            inside_day =
                EXCLUDED.inside_day,

            outside_day =
                EXCLUDED.outside_day,

            higher_high_higher_low =
                EXCLUDED.higher_high_higher_low,

            lower_high_lower_low =
                EXCLUDED.lower_high_lower_low,

            updated_date =
                CURRENT_TIMESTAMP;
    """

    with connection.cursor() as cursor:

        execute_values(
            cursor,
            sql,
            rows,
            page_size=1000
        )

    return len(rows)


# ============================================================================
# LATEST VALIDATION
# ============================================================================

def print_latest_validation(
    df,
    index_code,
    index_name
):

    latest = df.iloc[-1]

    print()
    print("-" * 100)

    print(
        f"{index_code} - {index_name}"
    )

    print(
        f"Date                       : "
        f"{latest['traded_date'].date()}"
    )

    print(
        f"Close                      : "
        f"{latest['close_price']:.2f}"
    )

    print(
        f"SF005 Close > EMA20        : "
        f"{latest['close_above_ema_20']}"
    )

    print(
        f"SF006 Close > SMA50        : "
        f"{latest['close_above_sma_50']}"
    )

    print(
        f"SF007 EMA20 Rising         : "
        f"{latest['ema_20_rising']}"
    )

    print(
        f"SF008 SMA50 Rising         : "
        f"{latest['sma_50_rising']}"
    )

    print(
        f"SF011 Distance 52W High    : "
        f"{latest['distance_from_52w_high_pct']:.2f}%"
    )

    print(
        f"SF013 Return 5D            : "
        f"{latest['return_5d_pct']:.2f}%"
    )

    print(
        f"SF014 Return 10D           : "
        f"{latest['return_10d_pct']:.2f}%"
    )

    print(
        f"SF015 Return 20D           : "
        f"{latest['return_20d_pct']:.2f}%"
    )

    print(
        f"SF016 RS 5D vs NIFTY500    : "
        f"{latest['rs_5d_vs_nifty500_pct']:.2f}%"
    )

    print(
        f"SF017 RS 10D vs NIFTY500   : "
        f"{latest['rs_10d_vs_nifty500_pct']:.2f}%"
    )

    print(
        f"SF018 RS 20D vs NIFTY500   : "
        f"{latest['rs_20d_vs_nifty500_pct']:.2f}%"
    )


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    try:

        connection = get_connection()

        print()
        print("=" * 100)
        print("MOMENTUMLAB - SECTOR FEATURES V1")
        print("=" * 100)

        # --------------------------------------------------------------------
        # Benchmark
        # --------------------------------------------------------------------

        benchmark_df = load_benchmark_data(
            connection
        )

        print(
            f"NIFTY 500 benchmark loaded: "
            f"{len(benchmark_df)} rows"
        )

        # --------------------------------------------------------------------
        # Sector indices
        # --------------------------------------------------------------------

        sector_indices = load_active_sector_indices(
            connection
        )

        print(
            f"Active sector indices found: "
            f"{len(sector_indices)}"
        )

        total_saved = 0

        # --------------------------------------------------------------------
        # Calculate each sector
        # --------------------------------------------------------------------

        for _, sector_row in sector_indices.iterrows():

            index_id = int(
                sector_row["index_id"]
            )

            index_code = (
                sector_row["index_code"]
            )

            index_name = (
                sector_row["index_name"]
            )

            df = load_sector_data(
                connection,
                index_id
            )

            if df.empty:

                print(
                    f"Skipping {index_code}: "
                    f"no historical data."
                )

                continue

            print()
            print(
                f"Processing {index_code}: "
                f"{len(df)} rows "
                f"({df['traded_date'].min().date()} "
                f"to "
                f"{df['traded_date'].max().date()})"
            )

            # ----------------------------------------------------------------
            # SF001-SF027
            # ----------------------------------------------------------------

            df = calculate_features(
                df,
                benchmark_df
            )

            # ----------------------------------------------------------------
            # Validate latest row
            # ----------------------------------------------------------------

            print_latest_validation(
                df,
                index_code,
                index_name
            )

            # ----------------------------------------------------------------
            # Save
            # ----------------------------------------------------------------

            saved_rows = save_features(
                connection,
                df
            )

            total_saved += saved_rows

            print(
                f"Saved {saved_rows} rows "
                f"for {index_code}"
            )

        # --------------------------------------------------------------------
        # Commit everything
        # --------------------------------------------------------------------

        connection.commit()

        print()
        print("=" * 100)
        print(
            "All sector features calculated "
            "and saved successfully."
        )
        print(
            f"Total rows processed: "
            f"{total_saved}"
        )
        print("=" * 100)

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