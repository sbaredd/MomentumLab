# ============================================================================
# Momentum Lab
# File        : calculate_market_regime_features.py
# Purpose     : Calculate and persist V1 broad-index Market Regime features
# Stage       : Stage 3 - All broad indices calculation and persistence
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
# DATABASE CONNECTION
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# LOAD ACTIVE BROAD INDICES
# ============================================================================

def load_active_broad_indices(connection):

    sql = """
        SELECT
            index_id,
            index_code,
            index_name
        FROM ref.ref_broad_index
        WHERE is_active = TRUE
        ORDER BY index_id;
    """

    df = pd.read_sql_query(
        sql,
        connection
    )

    if df.empty:
        raise ValueError(
            "No active broad indices found."
        )

    return df


# ============================================================================
# LOAD BROAD INDEX HISTORICAL DATA
# ============================================================================

def load_broad_index_data(
    connection,
    index_id
):

    sql = """
        SELECT
            d.index_id,
            r.index_code,
            r.index_name,
            d.traded_date,
            d.open_price,
            d.high_price,
            d.low_price,
            d.close_price,
            d.shares_traded,
            d.turnover_lacs
        FROM trn.nse_broad_index_daily d
        INNER JOIN ref.ref_broad_index r
            ON r.index_id = d.index_id
        WHERE d.index_id = %s
          AND r.is_active = TRUE
        ORDER BY d.traded_date;
    """

    df = pd.read_sql_query(
        sql,
        connection,
        params=(index_id,)
    )

    if df.empty:
        raise ValueError(
            f"No broad-index data found for index_id: {index_id}"
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


    # ========================================================================
    # NUMERIC CONVERSION
    # ========================================================================

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


    # ========================================================================
    # FOUNDATION CALCULATIONS
    # ========================================================================

    # ------------------------------------------------------------------------
    # EMA 20
    # ------------------------------------------------------------------------

    df["ema_20"] = (
        df["close_price"]
        .ewm(
            span=20,
            adjust=False,
            min_periods=20
        )
        .mean()
    )


    # ------------------------------------------------------------------------
    # SMA 50
    # ------------------------------------------------------------------------

    df["sma_50"] = (
        df["close_price"]
        .rolling(
            window=50,
            min_periods=50
        )
        .mean()
    )


    # ------------------------------------------------------------------------
    # 52-week high = 252 trading sessions
    # ------------------------------------------------------------------------

    df["high_52w"] = (
        df["high_price"]
        .rolling(
            window=252,
            min_periods=252
        )
        .max()
    )


    # ------------------------------------------------------------------------
    # Daily range
    # ------------------------------------------------------------------------

    df["daily_range"] = (
        df["high_price"]
        - df["low_price"]
    )


    # ------------------------------------------------------------------------
    # Average range - 20 sessions
    # ------------------------------------------------------------------------

    df["avg_range_20"] = (
        df["daily_range"]
        .rolling(
            window=20,
            min_periods=20
        )
        .mean()
    )


    # ========================================================================
    # LOOKBACK VALUES
    # ========================================================================

    prev_high = df["high_price"].shift(1)

    prev_low = df["low_price"].shift(1)

    prev_close = df["close_price"].shift(1)

    ema_20_5d_ago = df["ema_20"].shift(5)

    sma_50_5d_ago = df["sma_50"].shift(5)


    # ========================================================================
    # TREND FEATURES
    # MR001 - MR007
    # ========================================================================

    # ------------------------------------------------------------------------
    # MR001 - Close above EMA20
    # ------------------------------------------------------------------------

    df["close_above_ema_20"] = pd.Series(
        np.where(
            df["ema_20"].notna(),

            df["close_price"]
            > df["ema_20"],

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR002 - Close above SMA50
    # ------------------------------------------------------------------------

    df["close_above_sma_50"] = pd.Series(
        np.where(
            df["sma_50"].notna(),

            df["close_price"]
            > df["sma_50"],

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR003 - EMA20 rising vs 5 sessions ago
    # ------------------------------------------------------------------------

    df["ema_20_rising"] = pd.Series(
        np.where(
            df["ema_20"].notna()
            & ema_20_5d_ago.notna(),

            df["ema_20"]
            > ema_20_5d_ago,

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR004 - SMA50 rising vs 5 sessions ago
    # ------------------------------------------------------------------------

    df["sma_50_rising"] = pd.Series(
        np.where(
            df["sma_50"].notna()
            & sma_50_5d_ago.notna(),

            df["sma_50"]
            > sma_50_5d_ago,

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR005 - EMA20 above SMA50
    # ------------------------------------------------------------------------

    df["ema_20_above_sma_50"] = pd.Series(
        np.where(
            df["ema_20"].notna()
            & df["sma_50"].notna(),

            df["ema_20"]
            > df["sma_50"],

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR006 - Distance from EMA20 %
    # ------------------------------------------------------------------------

    df["distance_from_ema_20_pct"] = np.where(
        df["ema_20"].notna()
        & (df["ema_20"] != 0),

        (
            (
                df["close_price"]
                / df["ema_20"]
            )
            - 1
        )
        * 100,

        np.nan
    )


    # ------------------------------------------------------------------------
    # MR007 - Distance from 52-week high %
    # ------------------------------------------------------------------------

    df["distance_from_52w_high_pct"] = np.where(
        df["high_52w"].notna()
        & (df["high_52w"] != 0),

        (
            (
                df["close_price"]
                / df["high_52w"]
            )
            - 1
        )
        * 100,

        np.nan
    )


    # ========================================================================
    # MOMENTUM FEATURES
    # MR008 - MR011
    # ========================================================================

    # MR008 - 1-session return %

    df["return_1d_pct"] = (
        df["close_price"]
        .pct_change(
            periods=1,
            fill_method=None
        )
        * 100
    )


    # MR009 - 5-session return %

    df["return_5d_pct"] = (
        df["close_price"]
        .pct_change(
            periods=5,
            fill_method=None
        )
        * 100
    )


    # MR010 - 10-session return %

    df["return_10d_pct"] = (
        df["close_price"]
        .pct_change(
            periods=10,
            fill_method=None
        )
        * 100
    )


    # MR011 - 20-session return %

    df["return_20d_pct"] = (
        df["close_price"]
        .pct_change(
            periods=20,
            fill_method=None
        )
        * 100
    )


    # ========================================================================
    # PRICE BEHAVIOUR FEATURES
    # MR012 - MR020
    # ========================================================================

    # ------------------------------------------------------------------------
    # MR012 - Close position
    #
    # 0.00 = Close at low
    # 1.00 = Close at high
    # ------------------------------------------------------------------------

    df["close_position"] = np.where(
        df["high_price"].notna()
        & df["low_price"].notna()
        & df["close_price"].notna()
        & (
            df["high_price"]
            != df["low_price"]
        ),

        (
            (
                df["close_price"]
                - df["low_price"]
            )
            /
            (
                df["high_price"]
                - df["low_price"]
            )
        ),

        np.nan
    )


    # ------------------------------------------------------------------------
    # MR013 - Daily range % of previous close
    # ------------------------------------------------------------------------

    df["range_pct"] = np.where(
        prev_close.notna()
        & (prev_close != 0),

        (
            df["daily_range"]
            / prev_close
        )
        * 100,

        np.nan
    )


    # ------------------------------------------------------------------------
    # MR014 - Range expansion ratio
    # ------------------------------------------------------------------------

    df["range_expansion_ratio"] = np.where(
        df["avg_range_20"].notna()
        & (
            df["avg_range_20"]
            != 0
        ),

        (
            df["daily_range"]
            / df["avg_range_20"]
        ),

        np.nan
    )


    # ------------------------------------------------------------------------
    # Previous-session availability
    # ------------------------------------------------------------------------

    previous_session_available = (
        prev_high.notna()
        & prev_low.notna()
        & df["high_price"].notna()
        & df["low_price"].notna()
    )


    # ------------------------------------------------------------------------
    # MR015 - Break previous high
    # ------------------------------------------------------------------------

    df["break_prev_high"] = pd.Series(
        np.where(
            previous_session_available,

            df["high_price"]
            > prev_high,

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR016 - Break previous low
    # ------------------------------------------------------------------------

    df["break_prev_low"] = pd.Series(
        np.where(
            previous_session_available,

            df["low_price"]
            < prev_low,

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR017 - Inside day
    # ------------------------------------------------------------------------

    df["inside_day"] = pd.Series(
        np.where(
            previous_session_available,

            (
                (df["high_price"] < prev_high)
                &
                (df["low_price"] > prev_low)
            ),

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR018 - Outside day
    # ------------------------------------------------------------------------

    df["outside_day"] = pd.Series(
        np.where(
            previous_session_available,

            (
                (df["high_price"] > prev_high)
                &
                (df["low_price"] < prev_low)
            ),

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR019 - Higher high + higher low
    # ------------------------------------------------------------------------

    df["higher_high_higher_low"] = pd.Series(
        np.where(
            previous_session_available,

            (
                (df["high_price"] > prev_high)
                &
                (df["low_price"] > prev_low)
            ),

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    # ------------------------------------------------------------------------
    # MR020 - Lower high + lower low
    # ------------------------------------------------------------------------

    df["lower_high_lower_low"] = pd.Series(
        np.where(
            previous_session_available,

            (
                (df["high_price"] < prev_high)
                &
                (df["low_price"] < prev_low)
            ),

            pd.NA
        ),
        index=df.index,
        dtype="boolean"
    )


    return df


# ============================================================================
# DATABASE VALUE CONVERSION
# ============================================================================

def db_numeric(value):

    if pd.isna(value):
        return None

    return float(value)


def db_boolean(value):

    if pd.isna(value):
        return None

    return bool(value)


# ============================================================================
# SAVE FEATURES
# ============================================================================

def save_features(
    connection,
    df
):

    sql = """
        INSERT INTO trn.broad_index_features_daily
        (
            index_id,
            traded_date,

            ema_20,
            sma_50,
            high_52w,

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

            close_position,
            range_pct,
            avg_range_20,
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

            ema_20 =
                EXCLUDED.ema_20,

            sma_50 =
                EXCLUDED.sma_50,

            high_52w =
                EXCLUDED.high_52w,

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

            close_position =
                EXCLUDED.close_position,

            range_pct =
                EXCLUDED.range_pct,

            avg_range_20 =
                EXCLUDED.avg_range_20,

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


    rows = []

    for _, row in df.iterrows():

        rows.append(
            (
                int(row["index_id"]),

                row["traded_date"].date(),

                db_numeric(
                    row["ema_20"]
                ),

                db_numeric(
                    row["sma_50"]
                ),

                db_numeric(
                    row["high_52w"]
                ),

                db_boolean(
                    row["close_above_ema_20"]
                ),

                db_boolean(
                    row["close_above_sma_50"]
                ),

                db_boolean(
                    row["ema_20_rising"]
                ),

                db_boolean(
                    row["sma_50_rising"]
                ),

                db_boolean(
                    row["ema_20_above_sma_50"]
                ),

                db_numeric(
                    row["distance_from_ema_20_pct"]
                ),

                db_numeric(
                    row["distance_from_52w_high_pct"]
                ),

                db_numeric(
                    row["return_1d_pct"]
                ),

                db_numeric(
                    row["return_5d_pct"]
                ),

                db_numeric(
                    row["return_10d_pct"]
                ),

                db_numeric(
                    row["return_20d_pct"]
                ),

                db_numeric(
                    row["close_position"]
                ),

                db_numeric(
                    row["range_pct"]
                ),

                db_numeric(
                    row["avg_range_20"]
                ),

                db_numeric(
                    row["range_expansion_ratio"]
                ),

                db_boolean(
                    row["break_prev_high"]
                ),

                db_boolean(
                    row["break_prev_low"]
                ),

                db_boolean(
                    row["inside_day"]
                ),

                db_boolean(
                    row["outside_day"]
                ),

                db_boolean(
                    row["higher_high_higher_low"]
                ),

                db_boolean(
                    row["lower_high_lower_low"]
                )
            )
        )


    with connection.cursor() as cursor:

        execute_values(
            cursor,
            sql,
            rows,
            page_size=500
        )


    connection.commit()

    return len(rows)


# ============================================================================
# VALIDATION OUTPUT
# ============================================================================

def print_latest_validation(
    df,
    index_code,
    index_name
):

    latest = df.iloc[-1]

    print()
    print("=" * 100)

    print(
        f"{index_code} - {index_name}"
    )

    print("=" * 100)

    print(
        f"Latest Date                   : "
        f"{latest['traded_date'].date()}"
    )

    print(
        f"Close                         : "
        f"{latest['close_price']:.2f}"
    )

    print(
        f"EMA20                         : "
        f"{latest['ema_20']:.2f}"
    )

    print(
        f"SMA50                         : "
        f"{latest['sma_50']:.2f}"
    )

    print(
        f"52W High                      : "
        f"{latest['high_52w']:.2f}"
    )


    print()
    print("TREND")

    print(
        f"MR001 Close > EMA20           : "
        f"{latest['close_above_ema_20']}"
    )

    print(
        f"MR002 Close > SMA50           : "
        f"{latest['close_above_sma_50']}"
    )

    print(
        f"MR003 EMA20 Rising            : "
        f"{latest['ema_20_rising']}"
    )

    print(
        f"MR004 SMA50 Rising            : "
        f"{latest['sma_50_rising']}"
    )

    print(
        f"MR005 EMA20 > SMA50           : "
        f"{latest['ema_20_above_sma_50']}"
    )

    print(
        f"MR006 Distance EMA20 %        : "
        f"{latest['distance_from_ema_20_pct']:.4f}"
    )

    print(
        f"MR007 Distance 52W High %     : "
        f"{latest['distance_from_52w_high_pct']:.4f}"
    )


    print()
    print("MOMENTUM")

    print(
        f"MR008 Return 1D %             : "
        f"{latest['return_1d_pct']:.4f}"
    )

    print(
        f"MR009 Return 5D %             : "
        f"{latest['return_5d_pct']:.4f}"
    )

    print(
        f"MR010 Return 10D %            : "
        f"{latest['return_10d_pct']:.4f}"
    )

    print(
        f"MR011 Return 20D %            : "
        f"{latest['return_20d_pct']:.4f}"
    )


    print()
    print("PRICE BEHAVIOUR")

    print(
        f"MR012 Close Position          : "
        f"{latest['close_position']:.4f}"
    )

    print(
        f"MR013 Range %                 : "
        f"{latest['range_pct']:.4f}"
    )

    print(
        f"Average Range 20              : "
        f"{latest['avg_range_20']:.4f}"
    )

    print(
        f"MR014 Range Expansion         : "
        f"{latest['range_expansion_ratio']:.4f}"
    )

    print(
        f"MR015 Break Previous High     : "
        f"{latest['break_prev_high']}"
    )

    print(
        f"MR016 Break Previous Low      : "
        f"{latest['break_prev_low']}"
    )

    print(
        f"MR017 Inside Day              : "
        f"{latest['inside_day']}"
    )

    print(
        f"MR018 Outside Day             : "
        f"{latest['outside_day']}"
    )

    print(
        f"MR019 Higher High + Higher Low: "
        f"{latest['higher_high_higher_low']}"
    )

    print(
        f"MR020 Lower High + Lower Low  : "
        f"{latest['lower_high_lower_low']}"
    )


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    total_saved = 0

    try:

        connection = get_connection()

        broad_indices = load_active_broad_indices(
            connection
        )


        print()
        print("=" * 100)
        print("MOMENTUMLAB - MARKET REGIME V1")
        print("=" * 100)

        print(
            f"Active broad indices found: "
            f"{len(broad_indices)}"
        )

        print()


        for _, index_row in broad_indices.iterrows():

            index_id = int(
                index_row["index_id"]
            )

            index_code = (
                index_row["index_code"]
            )

            index_name = (
                index_row["index_name"]
            )


            # ----------------------------------------------------------------
            # Load history
            # ----------------------------------------------------------------

            df = load_broad_index_data(
                connection,
                index_id
            )


            print(
                f"Processing {index_code}: "
                f"{len(df)} rows "
                f"({df['traded_date'].min().date()} "
                f"to {df['traded_date'].max().date()})"
            )


            # ----------------------------------------------------------------
            # Calculate MR001 - MR020
            # ----------------------------------------------------------------

            df = calculate_features(
                df
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


            # ----------------------------------------------------------------
            # Latest validation
            # ----------------------------------------------------------------

            print_latest_validation(
                df,
                index_code,
                index_name
            )


        print()
        print("=" * 100)

        print(
            "All broad indices calculated "
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