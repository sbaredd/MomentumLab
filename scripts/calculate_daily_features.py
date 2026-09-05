# ============================================================================
# Momentum Lab
# File        : calculate_daily_features.py
# Purpose     : Calculate V1 daily quantitative features for ALL NSE EQ stocks
# Stage       : Stage 1 - Production
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
# DATABASE
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# LOAD ALL EQ PRICE DATA
# ============================================================================

def load_all_stock_data(connection):

    sql = """
        SELECT
            traded_date,
            symbol,
            prev_close,
            adjusted_open_price  AS open_price,
            adjusted_high_price  AS high_price,
            adjusted_low_price   AS low_price,
            adjusted_close_price AS close_price,
            traded_quantity,
            delivery_quantity,
            delivery_percent
        FROM trn.vw_nse_sec_bhavdata_adjusted
        WHERE series = 'EQ'
        ORDER BY symbol, traded_date;
    """

    df = pd.read_sql_query(
        sql,
        connection
    )

    if df.empty:

        raise ValueError(
            "No EQ data found in trn.vw_nse_sec_bhavdata_adjusted"
        )

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    return df


# ============================================================================
# FEATURE CALCULATION
# ============================================================================

def calculate_features(df):

    df = df.copy()

    numeric_columns = [
        "prev_close",
        "open_price",
        "high_price",
        "low_price",
        "close_price",
        "traded_quantity",
        "delivery_quantity",
        "delivery_percent",
    ]

    for column in numeric_columns:

        df[column] = pd.to_numeric(
            df[column],
            errors="coerce"
        )

    # ============================================================
    # PREVIOUS CLOSE
    # Derive from MomentumLab history instead of relying on
    # prev_close supplied by the NSE bhavcopy.
    # ============================================================

    df = df.sort_values(["symbol", "traded_date"]).copy()

    df["prev_close"] = (
        df.groupby("symbol")["close_price"]
      .shift(1)
    )

    # 1. DAILY RETURN %

    df["daily_return_pct"] = (
        (
            df["close_price"]
            - df["prev_close"]
        )
        / df["prev_close"]
    ) * 100


    # 2. GAP %

    df["gap_pct"] = (
        (
            df["open_price"]
            - df["prev_close"]
        )
        / df["prev_close"]
    ) * 100


    # 3. RANGE %

    df["range_pct"] = (
        (
            df["high_price"]
            - df["low_price"]
        )
        / df["prev_close"]
    ) * 100


    # 4. CLOSE POSITION

    daily_range = (
        df["high_price"]
        - df["low_price"]
    )

    df["close_position"] = np.where(
        daily_range != 0,
        (
            df["close_price"]
            - df["low_price"]
        )
        / daily_range,
        np.nan
    )


    # 5. SIMPLE MOVING AVERAGES

    df["sma_20"] = (
        df["close_price"]
        .rolling(
            window=20,
            min_periods=20
        )
        .mean()
    )

    df["sma_50"] = (
        df["close_price"]
        .rolling(
            window=50,
            min_periods=50
        )
        .mean()
    )

    df["sma_200"] = (
        df["close_price"]
        .rolling(
            window=200,
            min_periods=200
        )
        .mean()
    )


    # 6. EXPONENTIAL MOVING AVERAGES

    df["ema_20"] = (
        df["close_price"]
        .ewm(
            span=20,
            adjust=False,
            min_periods=20
        )
        .mean()
    )

    df["ema_50"] = (
        df["close_price"]
        .ewm(
            span=50,
            adjust=False,
            min_periods=50
        )
        .mean()
    )

    # ============================================================
    # EMA20 TREND FEATURES
    # ============================================================

    # Previous session EMA20
    df["ema20_1d_ago"] = (
    df.groupby("symbol")["ema_20"]
      .shift(1)
    )

    # EMA20 rising today?
    df["ema20_rising_1d"] = (
    df["ema_20"] > df["ema20_1d_ago"]
    )

    # EMA20 five sessions ago
    df["ema20_5d_ago"] = (
    df.groupby("symbol")["ema_20"]
      .shift(5)
    )

    # EMA20 5-session slope %
    df["ema20_slope_5d_pct"] = (
    (
        df["ema_20"]
        - df["ema20_5d_ago"]
    )
    / df["ema20_5d_ago"]
    ) * 100

    # 7. TRUE RANGE

    high_low = (
        df["high_price"]
        - df["low_price"]
    )

    high_prev_close = (
        df["high_price"]
        - df["prev_close"]
    ).abs()

    low_prev_close = (
        df["low_price"]
        - df["prev_close"]
    ).abs()

    df["true_range"] = pd.concat(
        [
            high_low,
            high_prev_close,
            low_prev_close,
        ],
        axis=1
    ).max(axis=1)


    # 8. ATR 14

    df["atr_14"] = (
        df["true_range"]
        .rolling(
            window=14,
            min_periods=14
        )
        .mean()
    )


    # 9. ATR %

    df["atr_pct"] = (
        df["atr_14"]
        / df["close_price"]
    ) * 100


    # 10. AVERAGE VOLUME - PREVIOUS 20 SESSIONS

    df["avg_volume_20"] = (
        df["traded_quantity"]
        .shift(1)
        .rolling(
            window=20,
            min_periods=20
        )
        .mean()
    )


    # 11. RELATIVE VOLUME

    df["relative_volume_20"] = (
        df["traded_quantity"]
        / df["avg_volume_20"]
    )


    # 12. PRIOR HIGHEST HIGH - 20

    df["highest_high_20"] = (
        df["high_price"]
        .shift(1)
        .rolling(
            window=20,
            min_periods=20
        )
        .max()
    )


    # 13. PRIOR HIGHEST HIGH - 50

    df["highest_high_50"] = (
        df["high_price"]
        .shift(1)
        .rolling(
            window=50,
            min_periods=50
        )
        .max()
    )


    # 14. PRIOR HIGHEST HIGH - 252

    df["highest_high_252"] = (
        df["high_price"]
        .shift(1)
        .rolling(
            window=252,
            min_periods=252
        )
        .max()
    )


    # 15. PRIOR LOWEST LOW - 20

    df["lowest_low_20"] = (
        df["low_price"]
        .shift(1)
        .rolling(
            window=20,
            min_periods=20
        )
        .min()
    )


    # 16. PRIOR LOWEST LOW - 50

    df["lowest_low_50"] = (
        df["low_price"]
        .shift(1)
        .rolling(
            window=50,
            min_periods=50
        )
        .min()
    )


    # 17. 5-DAY RETURN

    df["return_5d"] = (
        (
            df["close_price"]
            / df["close_price"].shift(5)
        )
        - 1
    ) * 100


    # 18. 10-DAY RETURN

    df["return_10d"] = (
        (
            df["close_price"]
            / df["close_price"].shift(10)
        )
        - 1
    ) * 100


    # 19. 20-DAY RETURN

    df["return_20d"] = (
        (
            df["close_price"]
            / df["close_price"].shift(20)
        )
        - 1
    ) * 100


    return df


# ============================================================================
# CALCULATE ALL SYMBOLS
# ============================================================================

def calculate_all_symbols(df):

    feature_frames = []

    grouped = df.groupby(
        "symbol",
        sort=False
    )

    total_symbols = df["symbol"].nunique()

    print(
        f"Symbols to process    : {total_symbols:,}"
    )

    for index, (symbol, symbol_df) in enumerate(
        grouped,
        start=1
    ):

        symbol_df = (
            symbol_df
            .sort_values("traded_date")
            .reset_index(drop=True)
        )

        calculated_df = calculate_features(
            symbol_df
        )

        feature_frames.append(
            calculated_df
        )

        if (
            index % 100 == 0
            or index == total_symbols
        ):

            print(
                f"Processed symbols     : "
                f"{index:,}/{total_symbols:,}"
            )

    result_df = pd.concat(
        feature_frames,
        ignore_index=True
    )

    return result_df


# ============================================================================
# PREPARE DATA FOR POSTGRESQL
# ============================================================================

def to_db_value(value):

    if pd.isna(value):
        return None

    if isinstance(
        value,
        np.generic
    ):
        return value.item()

    return value


def prepare_records(df):

    records = []

    for _, row in df.iterrows():

        records.append(
            (
                row["traded_date"].date(),
                row["symbol"],

                to_db_value(
                    row["daily_return_pct"]
                ),

                to_db_value(
                    row["gap_pct"]
                ),

                to_db_value(
                    row["range_pct"]
                ),

                to_db_value(
                    row["close_position"]
                ),

                to_db_value(
                    row["sma_20"]
                ),

                to_db_value(
                    row["sma_50"]
                ),

                to_db_value(
                    row["sma_200"]
                ),

                to_db_value(
                    row["ema_20"]
                ),

                to_db_value(
                    row["ema20_rising_1d"]
                ),

                to_db_value(
                    row["ema20_slope_5d_pct"]
                ),
                
                to_db_value(
                    row["ema_50"]
                ),

                to_db_value(
                    row["true_range"]
                ),

                to_db_value(
                    row["atr_14"]
                ),

                to_db_value(
                    row["atr_pct"]
                ),

                to_db_value(
                    row["avg_volume_20"]
                ),

                to_db_value(
                    row["relative_volume_20"]
                ),

                to_db_value(
                    row["highest_high_20"]
                ),

                to_db_value(
                    row["highest_high_50"]
                ),

                to_db_value(
                    row["highest_high_252"]
                ),

                to_db_value(
                    row["lowest_low_20"]
                ),

                to_db_value(
                    row["lowest_low_50"]
                ),

                to_db_value(
                    row["return_5d"]
                ),

                to_db_value(
                    row["return_10d"]
                ),

                to_db_value(
                    row["return_20d"]
                ),
            )
        )

    return records


# ============================================================================
# SAVE FEATURES
# ============================================================================

def save_features(
    connection,
    df
):

    records = prepare_records(
        df
    )

    sql = """
        INSERT INTO trn.stock_daily_features
        (
            trade_date,
            symbol,

            daily_return_pct,
            gap_pct,
            range_pct,
            close_position,

            sma_20,
            sma_50,
            sma_200,

            ema_20,
            ema20_rising_1d,
            ema20_slope_5d_pct,
            ema_50,

            true_range,
            atr_14,
            atr_pct,

            avg_volume_20,
            relative_volume_20,

            highest_high_20,
            highest_high_50,
            highest_high_252,

            lowest_low_20,
            lowest_low_50,

            return_5d,
            return_10d,
            return_20d
        )
        VALUES %s

        ON CONFLICT
            (trade_date, symbol)

        DO UPDATE SET

            daily_return_pct =
                EXCLUDED.daily_return_pct,

            gap_pct =
                EXCLUDED.gap_pct,

            range_pct =
                EXCLUDED.range_pct,

            close_position =
                EXCLUDED.close_position,

            sma_20 =
                EXCLUDED.sma_20,

            sma_50 =
                EXCLUDED.sma_50,

            sma_200 =
                EXCLUDED.sma_200,

            ema_20 =
                EXCLUDED.ema_20,

            ema20_rising_1d =
                EXCLUDED.ema20_rising_1d,

            ema20_slope_5d_pct =
                EXCLUDED.ema20_slope_5d_pct,

            ema_50 =
                EXCLUDED.ema_50,

            true_range =
                EXCLUDED.true_range,

            atr_14 =
                EXCLUDED.atr_14,

            atr_pct =
                EXCLUDED.atr_pct,

            avg_volume_20 =
                EXCLUDED.avg_volume_20,

            relative_volume_20 =
                EXCLUDED.relative_volume_20,

            highest_high_20 =
                EXCLUDED.highest_high_20,

            highest_high_50 =
                EXCLUDED.highest_high_50,

            highest_high_252 =
                EXCLUDED.highest_high_252,

            lowest_low_20 =
                EXCLUDED.lowest_low_20,

            lowest_low_50 =
                EXCLUDED.lowest_low_50,

            return_5d =
                EXCLUDED.return_5d,

            return_10d =
                EXCLUDED.return_10d,

            return_20d =
                EXCLUDED.return_20d,

            calculated_date =
                CURRENT_TIMESTAMP;
    """

    with connection.cursor() as cursor:

        execute_values(
            cursor,
            sql,
            records,
            page_size=5000
        )

    connection.commit()

    return len(
        records
    )


# ============================================================================
# VALIDATION OUTPUT
# ============================================================================

def display_validation(df):

    print()
    print("=" * 90)
    print("PRODUCTION FEATURE SUMMARY")
    print("=" * 90)

    print(
        f"Feature rows          : "
        f"{len(df):,}"
    )

    print(
        f"Distinct symbols      : "
        f"{df['symbol'].nunique():,}"
    )

    print(
        f"First trading date    : "
        f"{df['traded_date'].min().date()}"
    )

    print(
        f"Last trading date     : "
        f"{df['traded_date'].max().date()}"
    )


# ============================================================================
# MAIN
# ============================================================================

def main():

    print()
    print("=" * 70)
    print("MOMENTUM LAB - DAILY FEATURE ENGINE")
    print("STAGE 1 - PRODUCTION ALL EQ STOCKS")
    print("=" * 70)

    connection = None

    try:

        connection = get_connection()

        print(
            "Database               : Connected"
        )

        
        # Load all corporate-action-adjusted EQ data

        df = load_all_stock_data(
            connection
        )

        
        print(
            f"Adjusted EQ rows loaded: "
            f"{len(df):,}"
        )

        print(
            f"Distinct symbols       : "
            f"{df['symbol'].nunique():,}"
        )

        print(
            f"First trading date     : "
            f"{df['traded_date'].min().date()}"
        )

        print(
            f"Last trading date      : "
            f"{df['traded_date'].max().date()}"
        )

        # Calculate per-symbol features

        feature_df = calculate_all_symbols(
            df
        )

        print(
            "Feature calculation    : Complete"
        )

        display_validation(
            feature_df
        )

        # Save

        inserted = save_features(
            connection,
            feature_df
        )

        print()
        print(
            f"Feature rows saved     : "
            f"{inserted:,}"
        )

        print(
            "Target table           : "
            "trn.stock_daily_features"
        )

    except Exception as exc:

        if connection is not None:

            connection.rollback()

        print()
        print("ERROR")
        print(exc)

        raise

    finally:

        if connection is not None:

            connection.close()

            print(
                "Database               : "
                "Connection closed"
            )

    print()
    print("=" * 70)
    print("STAGE-1 PRODUCTION FEATURE CALCULATION COMPLETE")
    print("=" * 70)


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()