# ============================================================================
# Momentum Lab
# File        : import_bulk_bhavacopies.py
# Purpose     : Bulk import NEW NSE daily security bhavcopies into PostgreSQL
#
# Usage:
#
#   python scripts\import_bulk_bhavacopies.py \
#       "C:\My Musings\Bhavcopy\2025\Dec"
#
# Rules:
#   - Designed for NEW NSE BhavCopy_NSE_CM_* files
#   - Only SERIES = EQ is loaded
#   - Actual trading date is taken from TradDt inside the file
#   - NEW NSE TradDt is parsed as YYYY-MM-DD
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

def normalize_column_name(column_name):

    name = str(column_name)

    # Remove non-breaking spaces
    name = name.replace(
        "\xa0",
        " "
    )

    # Remove leading / trailing spaces
    name = name.strip()

    # Convert spaces to underscores
    name = re.sub(
        r"\s+",
        "_",
        name
    )

    return name.lower()


# ============================================================================
# READ NEW NSE BHAVCOPY
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

    # ------------------------------------------------------------------------
    # Normalize column names
    # ------------------------------------------------------------------------

    df.columns = [
        normalize_column_name(col)
        for col in df.columns
    ]

    # ------------------------------------------------------------------------
    # Validate NEW NSE format
    # ------------------------------------------------------------------------

    if "tckrsymb" not in df.columns:

        raise ValueError(
            f"{file_path.name} is not in the "
            f"expected NEW NSE bhavcopy format. "
            f"Column TckrSymb was not found."
        )

    print(
        "Detected format       : NEW NSE bhavcopy"
    )

    # ------------------------------------------------------------------------
    # NEW NSE -> MomentumLab column mapping
    # ------------------------------------------------------------------------

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

    # ------------------------------------------------------------------------
    # Fields not supplied in the NEW NSE bhavcopy
    # ------------------------------------------------------------------------

    if "prev_close" not in df.columns:
        df["prev_close"] = None

    if "avg_price" not in df.columns:
        df["avg_price"] = None

    if "deliv_qty" not in df.columns:
        df["deliv_qty"] = None

    if "deliv_per" not in df.columns:
        df["deliv_per"] = None

    return df


# ============================================================================
# CLEAN DATA
# ============================================================================

def clean_data(df):

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
    # ONLY SERIES = EQ
    # ========================================================================

    df = df[
        df["series"] == "EQ"
    ].copy()

    # ------------------------------------------------------------------------
    # Trading date
    #
    # CRITICAL:
    # NEW NSE TradDt is YYYY-MM-DD.
    #
    # DO NOT USE:
    #     dayfirst=True
    #
    # Example:
    #     2025-12-01 = 01-Dec-2025
    #
    # ------------------------------------------------------------------------

    raw_dates = (
        df["date1"]
        .astype(str)
        .str.strip()
    )

    df["date1"] = pd.to_datetime(
        raw_dates,
        format="%Y-%m-%d",
        errors="coerce"
    )

    # ------------------------------------------------------------------------
    # Fail if NEW NSE dates could not be parsed
    # ------------------------------------------------------------------------

    invalid_date_count = (
        df["date1"].isna().sum()
    )

    if invalid_date_count > 0:

        raise ValueError(
            f"Unable to parse {invalid_date_count} "
            f"TradDt value(s) using YYYY-MM-DD."
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
              AND series = 'EQ'
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

    return len(records)


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

            WHERE series = 'EQ'
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
    # Calendar status
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
# EXTRACT DATE FROM NEW NSE FILENAME
# ============================================================================

def extract_filename_date(
    file_path
):

    # Example:
    #
    # BhavCopy_NSE_CM_0_0_0_20251201_F_0000.csv
    #
    #                         YYYYMMDD

    match = re.search(
        r"(20\d{6})",
        file_path.name
    )

    if not match:
        return None

    try:

        return pd.to_datetime(
            match.group(1),
            format="%Y%m%d"
        ).date()

    except ValueError:

        return None


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
    # Read
    # ------------------------------------------------------------------------

    df = read_bhavdata(
        file_path
    )

    print(
        f"Rows read            : "
        f"{len(df):,}"
    )

    # ------------------------------------------------------------------------
    # Clean + SERIES EQ filter
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
    # Determine actual trading date from TradDt
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
            f"multiple TradDt values: "
            f"{trading_dates}"
        )

    traded_date = trading_dates[0]

    print(
        f"Trading date         : "
        f"{traded_date}"
    )

    # ------------------------------------------------------------------------
    # Filename / TradDt cross-check
    # ------------------------------------------------------------------------

    filename_date = extract_filename_date(
        file_path
    )

    if filename_date is not None:

        print(
            f"Filename date        : "
            f"{filename_date}"
        )

        if filename_date != traded_date:

            raise ValueError(
                f"DATE MISMATCH in {file_path.name}: "
                f"filename={filename_date}, "
                f"TradDt={traded_date}"
            )

    # ------------------------------------------------------------------------
    # Duplicate protection
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
# RESOLVE INPUT DIRECTORY
# ============================================================================

def get_input_path():

    if len(
        sys.argv
    ) < 2:

        raise ValueError(
            "Usage: "
            "python scripts\\import_bulk_bhavacopies.py "
            "<directory>"
        )

    input_path = Path(
        sys.argv[1]
    ).resolve()

    if not input_path.exists():

        raise FileNotFoundError(
            f"Input path does not exist: "
            f"{input_path}"
        )

    if not input_path.is_dir():

        raise ValueError(
            "Bulk loader expects a directory: "
            f"{input_path}"
        )

    return input_path


# ============================================================================
# MAIN
# ============================================================================

def main():

    connection = None

    try:

        input_path = get_input_path()

        print()
        print(
            "=" * 80
        )

        print(
            "MomentumLab - NEW NSE Bulk Bhavcopy Import"
        )

        print(
            "=" * 80
        )

        print(
            f"Input path           : "
            f"{input_path}"
        )

        print(
            "Series filter        : EQ ONLY"
        )

        print(
            "TradDt format        : YYYY-MM-DD"
        )

        # --------------------------------------------------------------------
        # Find NEW NSE files
        #
        # We intentionally don't require a .csv extension here because
        # Windows may hide extensions / source files can vary.
        # --------------------------------------------------------------------

        files = [
            file_path
            for file_path
            in input_path.glob(
                "BhavCopy_NSE_CM_*"
            )
            if file_path.is_file()
        ]

        # --------------------------------------------------------------------
        # Sort by embedded YYYYMMDD
        # --------------------------------------------------------------------

        files = sorted(
            files,
            key=lambda file_path: (
                extract_filename_date(file_path)
                or pd.Timestamp.max.date()
            )
        )

        if not files:

            raise FileNotFoundError(
                f"No BhavCopy_NSE_CM_* files "
                f"found in: {input_path}"
            )

        print(
            f"Files found          : "
            f"{len(files)}"
        )

        print(
            "=" * 80
        )

        # --------------------------------------------------------------------
        # Database
        # --------------------------------------------------------------------

        connection = get_connection()

        loaded_count = 0
        skipped_count = 0

        # --------------------------------------------------------------------
        # Process files
        # --------------------------------------------------------------------

        for file_number, file_path in enumerate(
            files,
            start=1
        ):

            print()
            print(
                f"[{file_number:03d}/{len(files):03d}]"
            )

            loaded = process_file(
                connection,
                file_path
            )

            if loaded:
                loaded_count += 1

            else:
                skipped_count += 1

        # --------------------------------------------------------------------
        # Refresh trading calendar
        # --------------------------------------------------------------------

        if loaded_count > 0:

            refresh_trading_calendar(
                connection
            )

        # --------------------------------------------------------------------
        # Summary
        # --------------------------------------------------------------------

        print()
        print(
            "=" * 80
        )

        print(
            "BULK BHAVCOPY IMPORT COMPLETED"
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
            "BULK BHAVCOPY IMPORT FAILED"
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

            print()
            print(
                "Database             : Connection closed"
            )


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()