# ============================================================================
# Momentum Lab
# Program      : calculate_stock_market_structure.py
# Stage        : Stage 2 - Stock Market Structure
#
# Purpose:
#   Calculate backtest-safe stock market structure using confirmed
#   swing highs and swing lows.
#
# Source:
#   trn.nse_sec_bhavdata
#
# Target:
#   trn.stock_market_structure_daily
#
# Swing definition:
#   2 bars left + pivot + 2 bars right
#
# Important:
#   A swing point becomes usable only on its confirmation date.
#   This prevents look-ahead bias during historical screening/backtesting.
# ============================================================================

import os

import pandas as pd
import psycopg2

from dotenv import load_dotenv
from psycopg2.extras import execute_values


# ============================================================================
# CONFIGURATION
# ============================================================================

load_dotenv()


# ============================================================================
# DATABASE CONNECTION
# ============================================================================

def get_connection():

    connection = psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        database=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD")
    )

    return connection


# ============================================================================
# READ BHAVDATA
# ============================================================================

def read_bhavdata(connection):

    sql = """
        SELECT
            traded_date,
            symbol,
            high_price,
            low_price
        FROM trn.nse_sec_bhavdata
        WHERE series = 'EQ'
        ORDER BY
            symbol,
            traded_date;
    """

    df = pd.read_sql_query(
        sql,
        connection
    )

    df["traded_date"] = pd.to_datetime(
        df["traded_date"]
    )

    return df


# ============================================================================
# CALCULATE SWING POINTS
# ============================================================================

def calculate_swing_points(df):

    df = df.copy()

    # ------------------------------------------------------------------------
    # Ensure correct ordering
    # ------------------------------------------------------------------------

    df = df.sort_values(
        [
            "symbol",
            "traded_date"
        ]
    ).reset_index(drop=True)

    grouped = df.groupby(
        "symbol",
        group_keys=False
    )

    # ------------------------------------------------------------------------
    # Previous / next two trading bars
    # ------------------------------------------------------------------------

    df["high_m1"] = grouped["high_price"].shift(1)
    df["high_m2"] = grouped["high_price"].shift(2)

    df["high_p1"] = grouped["high_price"].shift(-1)
    df["high_p2"] = grouped["high_price"].shift(-2)

    df["low_m1"] = grouped["low_price"].shift(1)
    df["low_m2"] = grouped["low_price"].shift(2)

    df["low_p1"] = grouped["low_price"].shift(-1)
    df["low_p2"] = grouped["low_price"].shift(-2)

    # ------------------------------------------------------------------------
    # Swing High
    #
    # Pivot high must be greater than:
    #   previous 2 highs
    #   next 2 highs
    # ------------------------------------------------------------------------

    swing_high_condition = (
        (df["high_price"] > df["high_m1"]) &
        (df["high_price"] > df["high_m2"]) &
        (df["high_price"] > df["high_p1"]) &
        (df["high_price"] > df["high_p2"])
    )

    df["swing_high"] = df["high_price"].where(
        swing_high_condition
    )

    # ------------------------------------------------------------------------
    # Swing Low
    #
    # Pivot low must be lower than:
    #   previous 2 lows
    #   next 2 lows
    # ------------------------------------------------------------------------

    swing_low_condition = (
        (df["low_price"] < df["low_m1"]) &
        (df["low_price"] < df["low_m2"]) &
        (df["low_price"] < df["low_p1"]) &
        (df["low_price"] < df["low_p2"])
    )

    df["swing_low"] = df["low_price"].where(
        swing_low_condition
    )

    # ------------------------------------------------------------------------
    # Confirmation Date
    #
    # A 2-right-bar pivot is confirmed only after two later trading
    # sessions have occurred.
    #
    # We use actual trading sessions, not pivot_date + 2 calendar days.
    # ------------------------------------------------------------------------

    df["confirmation_date"] = grouped[
        "traded_date"
    ].shift(-2)

    # ------------------------------------------------------------------------
    # Keep swing points only
    # ------------------------------------------------------------------------

    swings = df[
        df["swing_high"].notna() |
        df["swing_low"].notna()
    ][
        [
            "symbol",
            "traded_date",
            "confirmation_date",
            "swing_high",
            "swing_low"
        ]
    ].copy()

    swings = swings.rename(
        columns={
            "traded_date": "pivot_date"
        }
    )

    return swings


# ============================================================================
# BUILD BACKTEST-SAFE DAILY MARKET STRUCTURE
# ============================================================================

def build_daily_market_structure(df, swings):

    print()
    print("Building backtest-safe daily market structure...")

    # ------------------------------------------------------------------------
    # Only confirmed swings are usable
    # ------------------------------------------------------------------------

    confirmed = swings[
        swings["confirmation_date"].notna()
    ].copy()

    confirmed = confirmed.sort_values(
        [
            "symbol",
            "confirmation_date",
            "pivot_date"
        ]
    )

    results = []

    # ------------------------------------------------------------------------
    # Process stock by stock
    # ------------------------------------------------------------------------

    for symbol, price_group in df.groupby(
        "symbol",
        sort=False
    ):

        price_group = price_group.sort_values(
            "traded_date"
        )

        symbol_swings = confirmed[
            confirmed["symbol"] == symbol
        ]

        swing_highs = symbol_swings[
            symbol_swings["swing_high"].notna()
        ]

        swing_lows = symbol_swings[
            symbol_swings["swing_low"].notna()
        ]

        # --------------------------------------------------------------------
        # Calculate structure as known on EACH historical trade date
        # --------------------------------------------------------------------

        for trade_date in price_group["traded_date"]:

            # ----------------------------------------------------------------
            # Critical backtest rule:
            #
            # only use swings whose confirmation date is <= current trade date
            # ----------------------------------------------------------------

            usable_highs = swing_highs[
                swing_highs["confirmation_date"] <= trade_date
            ].tail(2)

            usable_lows = swing_lows[
                swing_lows["confirmation_date"] <= trade_date
            ].tail(2)

            # ----------------------------------------------------------------
            # Default values
            # ----------------------------------------------------------------

            previous_swing_high = None
            previous_swing_high_date = None

            latest_swing_high = None
            latest_swing_high_date = None

            high_structure = None

            previous_swing_low = None
            previous_swing_low_date = None

            latest_swing_low = None
            latest_swing_low_date = None

            low_structure = None

            market_structure = "NEUTRAL"

            # ----------------------------------------------------------------
            # HIGH STRUCTURE
            #
            # HH = Higher High
            # LH = Lower High
            # EQ = Equal High
            # ----------------------------------------------------------------

            if len(usable_highs) >= 2:

                previous_high = usable_highs.iloc[-2]
                latest_high = usable_highs.iloc[-1]

                previous_swing_high = previous_high[
                    "swing_high"
                ]

                previous_swing_high_date = previous_high[
                    "pivot_date"
                ]

                latest_swing_high = latest_high[
                    "swing_high"
                ]

                latest_swing_high_date = latest_high[
                    "pivot_date"
                ]

                if (
                    latest_swing_high
                    > previous_swing_high
                ):
                    high_structure = "HH"

                elif (
                    latest_swing_high
                    < previous_swing_high
                ):
                    high_structure = "LH"

                else:
                    high_structure = "EQ"

            # ----------------------------------------------------------------
            # LOW STRUCTURE
            #
            # HL = Higher Low
            # LL = Lower Low
            # EQ = Equal Low
            # ----------------------------------------------------------------

            if len(usable_lows) >= 2:

                previous_low = usable_lows.iloc[-2]
                latest_low = usable_lows.iloc[-1]

                previous_swing_low = previous_low[
                    "swing_low"
                ]

                previous_swing_low_date = previous_low[
                    "pivot_date"
                ]

                latest_swing_low = latest_low[
                    "swing_low"
                ]

                latest_swing_low_date = latest_low[
                    "pivot_date"
                ]

                if (
                    latest_swing_low
                    > previous_swing_low
                ):
                    low_structure = "HL"

                elif (
                    latest_swing_low
                    < previous_swing_low
                ):
                    low_structure = "LL"

                else:
                    low_structure = "EQ"

            # ----------------------------------------------------------------
            # FINAL MARKET STRUCTURE
            #
            # HH + HL = UPTREND
            # LH + LL = DOWNTREND
            # HH + LL = EXPANDING
            # LH + HL = CONTRACTING
            # Other   = NEUTRAL
            # ----------------------------------------------------------------

            if (
                high_structure == "HH"
                and low_structure == "HL"
            ):
                market_structure = "UPTREND"

            elif (
                high_structure == "LH"
                and low_structure == "LL"
            ):
                market_structure = "DOWNTREND"

            elif (
                high_structure == "HH"
                and low_structure == "LL"
            ):
                market_structure = "EXPANDING"

            elif (
                high_structure == "LH"
                and low_structure == "HL"
            ):
                market_structure = "CONTRACTING"

            # ----------------------------------------------------------------
            # Save calculated row
            # ----------------------------------------------------------------

            results.append(
                {
                    "trade_date":
                        trade_date,

                    "symbol":
                        symbol,

                    "previous_swing_high":
                        previous_swing_high,

                    "previous_swing_high_date":
                        previous_swing_high_date,

                    "latest_swing_high":
                        latest_swing_high,

                    "latest_swing_high_date":
                        latest_swing_high_date,

                    "high_structure":
                        high_structure,

                    "previous_swing_low":
                        previous_swing_low,

                    "previous_swing_low_date":
                        previous_swing_low_date,

                    "latest_swing_low":
                        latest_swing_low,

                    "latest_swing_low_date":
                        latest_swing_low_date,

                    "low_structure":
                        low_structure,

                    "market_structure":
                        market_structure
                }
            )

    structure_df = pd.DataFrame(
        results
    )

    print(
        f"Daily structure rows : "
        f"{len(structure_df):,}"
    )

    return structure_df


# ============================================================================
# DATABASE VALUE CONVERSION
# ============================================================================

def to_db_value(value):

    if pd.isna(value):
        return None

    if hasattr(value, "item"):
        return value.item()

    return value


# ============================================================================
# DATABASE DATE CONVERSION
# ============================================================================

def to_db_date(value):

    if pd.isna(value):
        return None

    if isinstance(value, pd.Timestamp):
        return value.date()

    return value


# ============================================================================
# SAVE DAILY MARKET STRUCTURE
# ============================================================================

def save_market_structure(
    connection,
    structure_df
):

    if structure_df.empty:

        print(
            "No market structure rows to save."
        )

        return 0

    sql = """
        INSERT INTO trn.stock_market_structure_daily
        (
            trade_date,
            symbol,

            previous_swing_high,
            previous_swing_high_date,

            latest_swing_high,
            latest_swing_high_date,

            high_structure,

            previous_swing_low,
            previous_swing_low_date,

            latest_swing_low,
            latest_swing_low_date,

            low_structure,
            market_structure
        )

        VALUES %s

        ON CONFLICT
            (trade_date, symbol)

        DO UPDATE SET

            previous_swing_high =
                EXCLUDED.previous_swing_high,

            previous_swing_high_date =
                EXCLUDED.previous_swing_high_date,

            latest_swing_high =
                EXCLUDED.latest_swing_high,

            latest_swing_high_date =
                EXCLUDED.latest_swing_high_date,

            high_structure =
                EXCLUDED.high_structure,

            previous_swing_low =
                EXCLUDED.previous_swing_low,

            previous_swing_low_date =
                EXCLUDED.previous_swing_low_date,

            latest_swing_low =
                EXCLUDED.latest_swing_low,

            latest_swing_low_date =
                EXCLUDED.latest_swing_low_date,

            low_structure =
                EXCLUDED.low_structure,

            market_structure =
                EXCLUDED.market_structure,

            calculated_date =
                CURRENT_TIMESTAMP;
    """

    records = []

    # ------------------------------------------------------------------------
    # Convert dataframe rows to database tuples
    # ------------------------------------------------------------------------

    for row in structure_df.itertuples(
        index=False
    ):

        records.append(
            (
                to_db_date(
                    row.trade_date
                ),

                row.symbol,

                to_db_value(
                    row.previous_swing_high
                ),

                to_db_date(
                    row.previous_swing_high_date
                ),

                # HH / LH / EQ / NULL    
                to_db_value(
                    row.latest_swing_high
                ),

                to_db_date(
                    row.latest_swing_high_date
                ),

                to_db_value(
                    row.high_structure
                ),

                to_db_value(
                    row.previous_swing_low
                ),

                to_db_date(
                    row.previous_swing_low_date
                ),

                to_db_value(
                    row.latest_swing_low
                ),

                to_db_date(
                    row.latest_swing_low_date
                ),

                # HL / LL / EQ / NULL

                to_db_value(
                    row.low_structure
                ),

                to_db_value(
                    row.market_structure
                )
            )
        )

    # ------------------------------------------------------------------------
    # Bulk UPSERT
    # ------------------------------------------------------------------------

    with connection.cursor() as cursor:

        invalid_high = structure_df[
            structure_df["high_structure"].notna()
            & ~structure_df["high_structure"].isin(
                ["HH", "LH", "EQ"]
            )
        ]

        invalid_low = structure_df[
            structure_df["low_structure"].notna()
            & ~structure_df["low_structure"].isin(
                ["HL", "LL", "EQ"]
            )
        ]

        if not invalid_high.empty:
            raise ValueError(
                f"Invalid high_structure values: "
                f"{invalid_high['high_structure'].unique()}"
            )   

        if not invalid_low.empty:
            raise ValueError(
                f"Invalid low_structure values: "
                f"{invalid_low['low_structure'].unique()}"
            )
            
        execute_values(
            cursor,
            sql,
            records,
            page_size=5000
        )

    connection.commit()

    return len(records)


# ============================================================================
# MAIN
# ============================================================================

def main():

    print()
    print("=" * 72)
    print("MOMENTUM LAB - STOCK MARKET STRUCTURE")
    print("=" * 72)

    connection = None

    try:

        # --------------------------------------------------------------------
        # Connect
        # --------------------------------------------------------------------

        connection = get_connection()

        print()
        print(
            "Database connection : OK"
        )

        # --------------------------------------------------------------------
        # Read Bhavdata
        # --------------------------------------------------------------------

        df = read_bhavdata(
            connection
        )

        print()
        print(
            f"Bhavdata rows       : "
            f"{len(df):,}"
        )

        print(
            f"Symbols             : "
            f"{df['symbol'].nunique():,}"
        )

        if not df.empty:

            print(
                f"First trading date  : "
                f"{df['traded_date'].min().date()}"
            )

            print(
                f"Last trading date   : "
                f"{df['traded_date'].max().date()}"
            )

        # --------------------------------------------------------------------
        # Calculate Swing Points
        # --------------------------------------------------------------------

        swings = calculate_swing_points(
            df
        )

        print()

        print(
            f"Swing points        : "
            f"{len(swings):,}"
        )

        print(
            f"Swing highs         : "
            f"{swings['swing_high'].notna().sum():,}"
        )

        print(
            f"Swing lows          : "
            f"{swings['swing_low'].notna().sum():,}"
        )

        # --------------------------------------------------------------------
        # Build Historical Daily Structure
        # --------------------------------------------------------------------

        structure_df = build_daily_market_structure(
            df,
            swings
        )

        # --------------------------------------------------------------------
        # Save to Database
        # --------------------------------------------------------------------

        rows_saved = save_market_structure(
            connection,
            structure_df
        )

        print()

        print(
            f"Market structure rows saved : "
            f"{rows_saved:,}"
        )

        print(
            "Target table                : "
            "trn.stock_market_structure_daily"
        )

        # --------------------------------------------------------------------
        # Validation - HDFCBANK Swing Points
        # --------------------------------------------------------------------

        print()
        print(
            "Latest HDFCBANK swings:"
        )
        print()

        hdfc_swings = swings[
            swings["symbol"] == "HDFCBANK"
        ].tail(15)

        print(
            hdfc_swings.to_string(
                index=False
            )
        )

        # --------------------------------------------------------------------
        # Validation - HDFCBANK Market Structure
        # --------------------------------------------------------------------

        print()
        print(
            "Latest HDFCBANK market structure:"
        )
        print()

        hdfc_structure = structure_df[
            structure_df["symbol"] == "HDFCBANK"
        ][
            [
                "trade_date",

                "previous_swing_high",
                "latest_swing_high",
                "high_structure",

                "previous_swing_low",
                "latest_swing_low",
                "low_structure",

                "market_structure"
            ]
        ].tail(15)

        print(
            hdfc_structure.to_string(
                index=False
            )
        )

    except Exception as exc:

        if connection is not None:

            connection.rollback()

        print()
        print(
            f"ERROR                 : "
            f"{exc}"
        )

        raise

    finally:

        if connection is not None:

            connection.close()

            print()
            print(
                "Database              : "
                "Connection closed"
            )

    print()
    print("=" * 72)
    print(
        "STAGE-2 MARKET STRUCTURE - "
        "CALCULATION COMPLETE"
    )
    print("=" * 72)


# ============================================================================
# PROGRAM ENTRY
# ============================================================================

if __name__ == "__main__":
    main()