# ============================================================================
# Momentum Lab
# File        : import_bhavcopy.py
# Purpose     : Import NSE daily security bhavcopy into PostgreSQL
#
# Usage:
#
#   Single file:
#   python scripts\import_bhavcopy.py "C:\path\to\sec_bhavdata_full_17082026.csv"
#
#   Directory:
#   python scripts\import_bhavcopy.py "C:\path\to\folder"
#
# Rules:
#   - Only SERIES = EQ is loaded
#   - Actual trading date is taken from DATE1 inside the file
#   - A file must contain exactly one trading date
#   - Existing trading dates are skipped
#   - Trading calendar is refreshed after successful loads
# ============================================================================

from pathlib import Path
import os
import re
import sys

import pandas as pd
import psycopg2
from dotenv import load_dotenv


# ============================================================================
# CONFIGURATION
# ============================================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent

load_dotenv(
    PROJECT_ROOT / ".env"
)


TARGET_TABLE = "trn.nse_sec_bhavdata"

CALENDAR_TABLE = "ref.trading_calendar"


DB_CONFIG = {
    "host": os.getenv(
        "DB_HOST",
        "localhost"
    ),

    "port": int(
        os.getenv(
            "DB_PORT",
            "5432"
        )
    ),

    "dbname": os.getenv(
        "DB_NAME",
        "momentumlab"
    ),

    "user": os.getenv(
        "DB_USER",
        "postgres"
    ),

    "password": os.getenv(
        "DB_PASSWORD"
    ),
}


# ============================================================================
# COLUMN NAME NORMALIZATION
# ============================================================================

def normalize_column_name(
    column_name
):

    name = str(
        column_name
    )

    # Remove non-breaking spaces
    name = name.replace(
        "\xa0",
        " "
    )

    # Remove leading/trailing spaces
    name = name.strip()

    # Convert spaces to underscores
    name = re.sub(
        r"\s+",
        "_",
        name
    )

    return name.lower()


# ============================================================================
# READ NSE FILE
# ============================================================================

def read_bhavdata(file_path):

    try:
        df = pd.read_csv(
            file_path,
            encoding="utf-8-sig"
        )

    except UnicodeDecodeError:
        df = pd.read_csv(
            file_path,
            encoding="cp1252"
        )

    # --------------------------------------------------------
    # Normalize column names
    # --------------------------------------------------------

    df.columns = [
        normalize_column_name(col)
        for col in df.columns
    ]


    # --------------------------------------------------------
    # Detect NEW NSE bhavcopy format
    # --------------------------------------------------------

    if "tckrsymb" in df.columns:

        df.attrs["bhavcopy_format"] = "NEW"

        print(
            "Detected format       : NEW NSE bhavcopy"
        )

        rename_map = {
            "traddt": "date1",
            "tckrsymb": "symbol",
            "sctysrs": "series",

            "opnpric": "open_price",
            "hghpric": "high_price",
            "lwpric": "low_price",
            "clspric": "close_price",
            "lastpric": "last_price",

            "ttltradgvol": "ttl_trd_qnty",
            "ttltrfval": "turnover_lacs",
            "ttlnboftxsexctd": "no_of_trades",
        }

        df = df.rename(
            columns=rename_map
        )


        # ----------------------------------------------------
        # Fields not available in the new file
        # ----------------------------------------------------

        if "prev_close" not in df.columns:
            df["prev_close"] = None

        if "avg_price" not in df.columns:
            df["avg_price"] = None

        if "deliv_qty" not in df.columns:
            df["deliv_qty"] = None

        if "deliv_per" not in df.columns:
            df["deliv_per"] = None


    else:

        df.attrs["bhavcopy_format"] = "OLD"
        print(
            "Detected format       : OLD NSE bhavcopy"
        )


    return df

# ============================================================================
# CLEAN DATA
# ============================================================================

def clean_data(
    df
):

    # ------------------------------------------------------------------------
    # Remove completely empty rows
    # ------------------------------------------------------------------------

    df = df.dropna(
        how="all"
    ).copy()


    # ------------------------------------------------------------------------
    # Validate required columns
    # ------------------------------------------------------------------------

    required_columns = [
        "symbol",
        "series",
        "date1",
        "prev_close",
        "open_price",
        "high_price",
        "low_price",
        "last_price",
        "close_price",
        "avg_price",
        "ttl_trd_qnty",
        "turnover_lacs",
        "no_of_trades",
        "deliv_qty",
        "deliv_per",
    ]


    missing_columns = [
        column
        for column in required_columns
        if column not in df.columns
    ]


    if missing_columns:

        raise ValueError(
            "Missing required columns: "
            + ", ".join(
                missing_columns
            )
        )


    # ------------------------------------------------------------------------
    # Text fields
    # ------------------------------------------------------------------------

    df["symbol"] = (
        df["symbol"]
        .astype(str)
        .str.strip()
    )


    df["series"] = (
        df["series"]
        .astype(str)
        .str.strip()
        .str.upper()
    )


    # ========================================================================
    # MOMENTUMLAB EQUITY UNIVERSE
    #
    # IMPORTANT:
    # Only NSE SERIES = EQ is loaded.
    # ========================================================================

    df = df[
        df["series"] == "EQ"
    ].copy()


    # ------------------------------------------------------------------------
    # Trading date
    # ------------------------------------------------------------------------

    bhavcopy_format = df.attrs.get(
        "bhavcopy_format"
    )

    if bhavcopy_format == "NEW":

        df["date1"] = pd.to_datetime(
            df["date1"],
            format="%Y-%m-%d",
            errors="coerce"
        )

    else:

        df["date1"] = pd.to_datetime(
            df["date1"],
            errors="coerce",
            dayfirst=True
        )


    # ------------------------------------------------------------------------
    # Numeric fields
    # ------------------------------------------------------------------------

    numeric_columns = [
        "prev_close",
        "open_price",
        "high_price",
        "low_price",
        "last_price",
        "close_price",
        "avg_price",
        "ttl_trd_qnty",
        "turnover_lacs",
        "no_of_trades",
        "deliv_qty",
        "deliv_per",
    ]


    for column in numeric_columns:

        df[column] = pd.to_numeric(
            df[column],
            errors="coerce"
        )


    # ------------------------------------------------------------------------
    # Remove invalid dates
    # ------------------------------------------------------------------------

    df = df[
        df["date1"].notna()
    ].copy()


    return df

# ============================================================================
# DATABASE CONNECTION
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# CHECK WHETHER TRADING DATE ALREADY EXISTS
# ============================================================================

def trading_date_exists(
    connection,
    traded_date
):

    sql = f"""
        SELECT EXISTS
        (
            SELECT 1
            FROM {TARGET_TABLE}
            WHERE traded_date = %s
        );
    """


    with connection.cursor() as cursor:

        cursor.execute(
            sql,
            (
                traded_date,
            )
        )

        return cursor.fetchone()[0]


# ============================================================================
# INSERT BHAVCOPY DATA
# ============================================================================

def insert_data(
    connection,
    df
):

    sql = f"""
        INSERT INTO {TARGET_TABLE}
        (
            traded_date,
            symbol,
            series,
            prev_close,
            open_price,
            high_price,
            low_price,
            last_price,
            close_price,
            avg_price,
            traded_quantity,
            turnover_lacs,
            no_of_trades,
            delivery_quantity,
            delivery_percent
        )
        VALUES
        (
            %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s
        );
    """


    records = []


    for _, row in df.iterrows():

        records.append(
            (
                row["date1"].date(),

                row["symbol"],

                row["series"],

                None
                if pd.isna(
                    row["prev_close"]
                )
                else float(
                    row["prev_close"]
                ),

                None
                if pd.isna(
                    row["open_price"]
                )
                else float(
                    row["open_price"]
                ),

                None
                if pd.isna(
                    row["high_price"]
                )
                else float(
                    row["high_price"]
                ),

                None
                if pd.isna(
                    row["low_price"]
                )
                else float(
                    row["low_price"]
                ),

                None
                if pd.isna(
                    row["last_price"]
                )
                else float(
                    row["last_price"]
                ),

                None
                if pd.isna(
                    row["close_price"]
                )
                else float(
                    row["close_price"]
                ),

                None
                if pd.isna(
                    row["avg_price"]
                )
                else float(
                    row["avg_price"]
                ),

                None
                if pd.isna(
                    row["ttl_trd_qnty"]
                )
                else int(
                    row["ttl_trd_qnty"]
                ),

                None
                if pd.isna(
                    row["turnover_lacs"]
                )
                else float(
                    row["turnover_lacs"]
                ),

                None
                if pd.isna(
                    row["no_of_trades"]
                )
                else int(
                    row["no_of_trades"]
                ),

                None
                if pd.isna(
                    row["deliv_qty"]
                )
                else int(
                    row["deliv_qty"]
                ),

                None
                if pd.isna(
                    row["deliv_per"]
                )
                else float(
                    row["deliv_per"]
                ),
            )
        )


    with connection.cursor() as cursor:

        cursor.executemany(
            sql,
            records
        )


    connection.commit()


    return len(
        records
    )


# ============================================================================
# REFRESH TRADING CALENDAR
# ============================================================================

def refresh_trading_calendar(
    connection
):

    print()

    print(
        "Refreshing trading calendar..."
    )


    # ------------------------------------------------------------------------
    # Rebuild trading date relationships from actual bhavcopy dates.
    #
    # This:
    # - adds new trading dates
    # - maintains previous trading date
    # - maintains trading-day numbering
    # ------------------------------------------------------------------------

    refresh_sql = f"""
        INSERT INTO {CALENDAR_TABLE}
        (
            traded_date,
            previous_trading_date,
            trading_day_number
        )

        SELECT
            d.traded_date,

            LAG(
                d.traded_date
            )
            OVER
            (
                ORDER BY d.traded_date
            )
            AS previous_trading_date,

            ROW_NUMBER()
            OVER
            (
                ORDER BY d.traded_date
            )
            AS trading_day_number

        FROM
        (
            SELECT DISTINCT
                traded_date

            FROM {TARGET_TABLE}
        ) d

        ON CONFLICT
        (
            traded_date
        )

        DO UPDATE SET

            previous_trading_date =
                EXCLUDED.previous_trading_date,

            trading_day_number =
                EXCLUDED.trading_day_number;
    """


    with connection.cursor() as cursor:

        cursor.execute(
            refresh_sql
        )


    connection.commit()


    # ------------------------------------------------------------------------
    # Report calendar status
    # ------------------------------------------------------------------------

    status_sql = f"""
        SELECT
            MIN(traded_date),
            MAX(traded_date),
            COUNT(*)

        FROM {CALENDAR_TABLE};
    """


    with connection.cursor() as cursor:

        cursor.execute(
            status_sql
        )

        (
            first_date,
            last_date,
            trading_days
        ) = cursor.fetchone()


    print(
        f"Trading calendar    : "
        f"{first_date} -> {last_date}"
    )


    print(
        f"Trading days        : "
        f"{trading_days}"
    )


# ============================================================================
# PROCESS ONE FILE
# ============================================================================

def process_file(
    connection,
    file_path
):

    print()

    print(
        "=" * 80
    )

    print(
        f"FILE                 : "
        f"{file_path.name}"
    )

    print(
        "=" * 80
    )


    # ------------------------------------------------------------------------
    # Read source file
    # ------------------------------------------------------------------------

    df = read_bhavdata(
        file_path
    )


    print(
        f"Rows read            : "
        f"{len(df):,}"
    )


    # ------------------------------------------------------------------------
    # Clean and filter SERIES = EQ
    # ------------------------------------------------------------------------

    df = clean_data(
        df
    )


    print(
        f"EQ rows              : "
        f"{len(df):,}"
    )


    if df.empty:

        print(
            "STATUS               : "
            "SKIPPED - no EQ records"
        )

        return False


    # ------------------------------------------------------------------------
    # Determine actual trading date from DATE1
    # ------------------------------------------------------------------------

    trading_dates = (
        df["date1"]
        .dt
        .date
        .unique()
    )


    if len(
        trading_dates
    ) != 1:

        raise ValueError(
            f"{file_path.name} contains "
            f"multiple DATE1 values: "
            f"{trading_dates}"
        )


    traded_date = (
        trading_dates[0]
    )


    print(
        f"Trading date         : "
        f"{traded_date}"
    )


    # ------------------------------------------------------------------------
    # Filename/date diagnostic
    #
    # We intentionally trust DATE1, not the filename.
    # ------------------------------------------------------------------------

    date_match = re.search(
        r"(\d{8})",
        file_path.name
    )


    if date_match:

        filename_date_text = (
            date_match.group(1)
        )

        try:

            filename_date = (
                pd.to_datetime(
                    filename_date_text,
                    format="%Y%m%d"
                )
                .date()
            )


            if filename_date != traded_date:

                print()

                print(
                    "WARNING              : "
                    "filename date does not "
                    "match DATE1"
                )

                print(
                    f"Filename date        : "
                    f"{filename_date}"
                )

                print(
                    f"Actual DATE1         : "
                    f"{traded_date}"
                )

        except ValueError:

            pass


    # ------------------------------------------------------------------------
    # Duplicate-date protection
    # ------------------------------------------------------------------------

    if trading_date_exists(
        connection,
        traded_date
    ):

        print(
            "STATUS               : "
            f"SKIPPED - {traded_date} "
            f"already exists"
        )

        return False


    # ------------------------------------------------------------------------
    # Insert
    # ------------------------------------------------------------------------

    try:

        inserted = insert_data(
            connection,
            df
        )


        print(
            "STATUS               : LOADED"
        )


        print(
            f"Rows inserted        : "
            f"{inserted:,}"
        )


        return True


    except Exception:

        connection.rollback()

        raise


# ============================================================================
# RESOLVE INPUT PATH
# ============================================================================

def get_input_path():

    if len(
        sys.argv
    ) < 2:

        raise ValueError(
            "Usage: "
            "python scripts\\import_bhavcopy.py "
            "<csv_file_or_directory>"
        )


    input_path = Path(
        sys.argv[1]
    ).resolve()


    if not input_path.exists():

        raise FileNotFoundError(
            f"Input path does not exist: "
            f"{input_path}"
        )


    return input_path


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None


    try:

        # ====================================================================
        # INPUT
        # ====================================================================

        input_path = get_input_path()


        print()

        print(
            "=" * 80
        )

        print(
            "MomentumLab - NSE Bhavcopy Import"
        )

        print(
            "=" * 80
        )


        print(
            f"Input path           : "
            f"{input_path}"
        )


        print(
            "Series filter        : EQ"
        )


        # ====================================================================
        # DETERMINE FILES
        # ====================================================================

        if input_path.is_file():

            files = [
                input_path
            ]


        elif input_path.is_dir():

            files = sorted(
                input_path.glob(
                    "sec_bhavdata_full_*.csv*"
                )
            )


        else:

            raise ValueError(
                f"Unsupported input path: "
                f"{input_path}"
            )


        if not files:

            raise FileNotFoundError(
                f"No bhavcopy files found in: "
                f"{input_path}"
            )


        print(
            f"Files found          : "
            f"{len(files)}"
        )


        print(
            "=" * 80
        )


        # ====================================================================
        # DATABASE CONNECTION
        # ====================================================================

        connection = get_connection()


        # ====================================================================
        # PROCESS FILES
        # ====================================================================

        loaded_count = 0

        skipped_count = 0


        for file_path in files:

            loaded = process_file(
                connection,
                file_path
            )


            if loaded:

                loaded_count += 1

            else:

                skipped_count += 1


        # ====================================================================
        # REFRESH TRADING CALENDAR
        # ====================================================================

        if loaded_count > 0:

            refresh_trading_calendar(
                connection
            )


        # ====================================================================
        # SUMMARY
        # ====================================================================

        print()

        print(
            "=" * 80
        )

        print(
            "Bhavcopy import completed."
        )

        print(
            "=" * 80
        )


        print(
            f"Files loaded         : "
            f"{loaded_count}"
        )


        print(
            f"Files skipped        : "
            f"{skipped_count}"
        )


        print(
            "=" * 80
        )


    except Exception as exc:

        if connection is not None:

            connection.rollback()


        print()

        print(
            "=" * 80
        )

        print(
            "BHAVCOPY IMPORT FAILED"
        )

        print(
            "=" * 80
        )


        print(
            f"ERROR                : "
            f"{exc}"
        )


        print(
            "=" * 80
        )


        raise


    finally:

        if connection is not None:

            connection.close()


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()