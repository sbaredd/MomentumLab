"""
MomentumLab
Import NSE Corporate Actions CSV

Target:
    trn.nse_corporate_action

Responsibilities:
    - Read NSE Corporate Actions CSV
    - Normalize blanks / "-" to NULL
    - Parse NSE dates
    - Insert raw corporate-action records
    - Skip records already loaded
"""

import sys
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
import os


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parents[1]

load_dotenv(PROJECT_ROOT / ".env")


def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        database=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def clean_text(value):
    if pd.isna(value):
        return None

    value = str(value).strip()

    if value in ("", "-", "--"):
        return None

    return value


def parse_date(value):
    value = clean_text(value)

    if value is None:
        return None

    return pd.to_datetime(
        value,
        format="%d-%b-%Y",
        errors="raise"
    ).date()


def parse_numeric(value):
    value = clean_text(value)

    if value is None:
        return None

    return float(value)


# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------

def import_corporate_actions(csv_path):

    csv_path = Path(csv_path)

    if not csv_path.exists():
        raise FileNotFoundError(f"File not found: {csv_path}")

    print("=" * 80)
    print("NSE CORPORATE ACTION IMPORT")
    print("=" * 80)
    print(f"File                  : {csv_path}")

    df = pd.read_csv(csv_path)

    print(f"Rows read             : {len(df):,}")
    print(f"Columns               : {len(df.columns)}")

    # Normalize NSE column names.
    #
    # Expected source:
    # SYMBOL
    # COMPANY NAME
    # SERIES
    # PURPOSE
    # FACE VALUE
    # EX-DATE
    # RECORD DATE
    # BOOK CLOSURE START DATE
    # BOOK CLOSURE END DATE

    df.columns = [
        str(column).strip().upper()
        for column in df.columns
    ]

    required_columns = {
        "SYMBOL",
        "COMPANY NAME",
        "SERIES",
        "PURPOSE",
        "FACE VALUE",
        "EX-DATE",
        "RECORD DATE",
        "BOOK CLOSURE START DATE",
        "BOOK CLOSURE END DATE",
    }

    missing_columns = required_columns - set(df.columns)

    if missing_columns:
        raise ValueError(
            "Missing required NSE columns: "
            + ", ".join(sorted(missing_columns))
        )

    insert_sql = """
        INSERT INTO trn.nse_corporate_action
        (
            symbol,
            company_name,
            series,
            purpose,
            face_value,
            ex_date,
            record_date,
            book_closure_start_date,
            book_closure_end_date
        )
        VALUES
        (
            %s, %s, %s, %s, %s,
            %s, %s, %s, %s
        )
        ON CONFLICT
        (
            symbol,
            series,
            purpose,
            ex_date
        )
        DO NOTHING
    """

    rows_inserted = 0
    rows_skipped = 0

    conn = None

    try:
        conn = get_connection()

        with conn.cursor() as cur:

            for _, row in df.iterrows():

                symbol = clean_text(row["SYMBOL"])
                company_name = clean_text(row["COMPANY NAME"])
                series = clean_text(row["SERIES"])
                purpose = clean_text(row["PURPOSE"])

                face_value = parse_numeric(row["FACE VALUE"])

                ex_date = parse_date(row["EX-DATE"])
                record_date = parse_date(row["RECORD DATE"])

                book_start = parse_date(
                    row["BOOK CLOSURE START DATE"]
                )

                book_end = parse_date(
                    row["BOOK CLOSURE END DATE"]
                )

                if symbol is None:
                    raise ValueError(
                        "Corporate-action row has NULL SYMBOL"
                    )

                if purpose is None:
                    raise ValueError(
                        f"{symbol}: NULL PURPOSE"
                    )

                if ex_date is None:
                    raise ValueError(
                        f"{symbol}: NULL EX-DATE"
                    )

                cur.execute(
                    insert_sql,
                    (
                        symbol,
                        company_name,
                        series,
                        purpose,
                        face_value,
                        ex_date,
                        record_date,
                        book_start,
                        book_end,
                    ),
                )

                if cur.rowcount == 1:
                    rows_inserted += 1
                else:
                    rows_skipped += 1

        conn.commit()

        print()
        print(f"Rows inserted         : {rows_inserted:,}")
        print(f"Rows skipped          : {rows_skipped:,}")
        print(f"Rows processed        : {rows_inserted + rows_skipped:,}")
        print()
        print("Transaction           : COMMITTED")

    except Exception:
        if conn:
            conn.rollback()

        print()
        print("Transaction           : ROLLED BACK")
        raise

    finally:
        if conn:
            conn.close()

        print("Database              : Connection closed")
        print()
        print("=" * 80)
        print("NSE CORPORATE ACTION IMPORT COMPLETE")
        print("=" * 80)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":

    if len(sys.argv) != 2:
        print(
            "Usage:\n"
            "python scripts/03_import_nse_corporate_actions.py "
            "<corporate_actions.csv>"
        )
        sys.exit(1)

    import_corporate_actions(sys.argv[1])