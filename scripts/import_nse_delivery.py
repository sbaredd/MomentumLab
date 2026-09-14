# ============================================================================
# Momentum Lab
# File        : import_nse_delivery.py
# Purpose     : Import NSE MTO security-wise delivery data
#
# Usage:
#   Dry run:
#   python scripts\import_nse_delivery.py "C:\path\MTO_11092026.DAT"
#
#   Apply:
#   python scripts\import_nse_delivery.py "C:\path\MTO_11092026.DAT" --apply
#
# Rules:
#   - Only SERIES = EQ is processed
#   - Trade date is read from MTO header
#   - Updates existing rows in trn.nse_sec_bhavdata
#   - Does NOT insert missing bhavdata rows
#   - Dry-run by default
# ============================================================================

from pathlib import Path
import os
import re
import sys

import psycopg2
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parent.parent

load_dotenv(PROJECT_ROOT / ".env")


TARGET_TABLE = "trn.nse_sec_bhavdata"


DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "momentumlab"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD"),
}


def get_input_path():
    if len(sys.argv) < 2:
        raise ValueError(
            "Usage: python scripts\\import_nse_delivery.py "
            "<MTO_file_or_directory> [--apply]"
        )

    input_path = Path(sys.argv[1]).resolve()

    if not input_path.exists():
        raise FileNotFoundError(
            f"Input path does not exist: {input_path}"
        )

    return input_path


def resolve_files(input_path):
    if input_path.is_file():
        return [input_path]

    files = sorted(
        input_path.glob("MTO_*.DAT")
    )

    if not files:
        raise ValueError(
            f"No MTO_*.DAT files found in: {input_path}"
        )

    return files


def is_apply_mode():
    return "--apply" in sys.argv[2:]


def read_trade_date(lines):
    for line in lines[:10]:
        match = re.search(
            r"Trade Date <(\d{2})-([A-Z]{3})-(\d{4})>",
            line
        )

        if match:
            day = match.group(1)
            month_text = match.group(2)
            year = match.group(3)

            month_map = {
                "JAN": "01",
                "FEB": "02",
                "MAR": "03",
                "APR": "04",
                "MAY": "05",
                "JUN": "06",
                "JUL": "07",
                "AUG": "08",
                "SEP": "09",
                "OCT": "10",
                "NOV": "11",
                "DEC": "12",
            }

            month = month_map[month_text]

            return f"{year}-{month}-{day}"

    raise ValueError(
        "Trade date not found in MTO header."
    )


def parse_eq_records(lines):
    records = []

    for line in lines:
        line = line.strip()

        if not line.startswith("20,"):
            continue

        parts = line.split(",")

        if len(parts) != 7:
            continue

        record_type = parts[0].strip()
        symbol = parts[2].strip()
        series = parts[3].strip()

        if record_type != "20":
            continue

        if series != "EQ":
            continue

        traded_quantity = int(parts[4].strip())
        delivery_quantity = int(parts[5].strip())
        delivery_percent = float(parts[6].strip())

        records.append(
            (
                symbol,
                series,
                traded_quantity,
                delivery_quantity,
                delivery_percent,
            )
        )

    return records


def fetch_bhavdata_rows(connection, traded_date):
    sql = f"""
        SELECT
            symbol,
            series,
            traded_quantity
        FROM {TARGET_TABLE}
        WHERE traded_date = %s
          AND series = 'EQ';
    """

    with connection.cursor() as cursor:
        cursor.execute(sql, (traded_date,))
        rows = cursor.fetchall()

    return {
        (symbol, series): traded_quantity
        for symbol, series, traded_quantity in rows
    }


def reconcile(records, bhavdata):

    matched = []
    unmatched_mto = []
    percentage_errors = []

    mto_keys = set()

    for (
        symbol,
        series,
        mto_traded_quantity,
        delivery_quantity,
        delivery_percent,
    ) in records:

        key = (symbol, series)

        mto_keys.add(key)

        # ------------------------------------------------------------
        # Validate MTO delivery percentage internally
        # ------------------------------------------------------------

        if mto_traded_quantity > 0:

            calculated_percent = round(
                (
                    delivery_quantity
                    / mto_traded_quantity
                ) * 100,
                2
            )

            if abs(
                calculated_percent
                - delivery_percent
            ) > 0.01:

                percentage_errors.append(
                    (
                        symbol,
                        mto_traded_quantity,
                        delivery_quantity,
                        delivery_percent,
                        calculated_percent,
                    )
                )

        # ------------------------------------------------------------
        # Match MTO record to bhavdata
        # ------------------------------------------------------------

        if key not in bhavdata:

            unmatched_mto.append(
                key
            )

            continue

        matched.append(
            (
                delivery_quantity,
                delivery_percent,
                symbol,
                series,
            )
        )

    unmatched_bhavdata = [
        key
        for key in bhavdata.keys()
        if key not in mto_keys
    ]

    return (
        matched,
        unmatched_mto,
        unmatched_bhavdata,
        percentage_errors,
    )

def apply_updates(
    connection,
    traded_date,
    matched
):
    sql = f"""
        UPDATE {TARGET_TABLE}
        SET
            delivery_quantity = %s,
            delivery_percent = %s
        WHERE traded_date = %s
          AND symbol = %s
          AND series = %s;
    """

    update_rows = [
        (
            delivery_quantity,
            delivery_percent,
            traded_date,
            symbol,
            series,
        )
        for (
            delivery_quantity,
            delivery_percent,
            symbol,
            series,
        ) in matched
    ]

    with connection.cursor() as cursor:
        cursor.executemany(
            sql,
            update_rows
        )

    connection.commit()

    return len(matched)

def main():
    input_path = get_input_path()
    apply_mode = is_apply_mode()
    files = resolve_files(input_path)

    connection = psycopg2.connect(**DB_CONFIG)

    try:
        for file_path in files:
            print()
            print("=" * 80)
            print(f"Processing: {file_path.name}")
            print("=" * 80)

            lines = file_path.read_text(
                encoding="utf-8",
                errors="replace"
            ).splitlines()

            traded_date = read_trade_date(lines)
            records = parse_eq_records(lines)

            bhavdata = fetch_bhavdata_rows(
                connection,
                traded_date
            )

            (
                matched,
                unmatched_mto,
                unmatched_bhavdata,
                percentage_errors,
            ) = reconcile(
                records,
                bhavdata
            )

            print()
            print("NSE DELIVERY IMPORT RECONCILIATION")
            print("-" * 80)
            print(f"File                  : {file_path.name}")
            print(f"Trade date            : {traded_date}")
            print(f"MTO EQ rows           : {len(records):,}")
            print(f"Bhavdata EQ rows      : {len(bhavdata):,}")
            print(f"Matched rows          : {len(matched):,}")
            print(f"Unmatched MTO rows    : {len(unmatched_mto):,}")
            print(f"Unmatched bhav rows   : {len(unmatched_bhavdata):,}")
            print(f"MTO percentage errors : {len(percentage_errors):,}")
            print(f"Mode                  : {'APPLY' if apply_mode else 'DRY RUN'}")
            print("-" * 80)

            if unmatched_mto:
                print("\nUNMATCHED MTO:")
                for row in unmatched_mto:
                    print(row)

            if unmatched_bhavdata:
                print("\nUNMATCHED BHAVDATA:")
                for row in unmatched_bhavdata:
                    print(row)

            if percentage_errors:
                print("\nMTO PERCENTAGE ERRORS:")
                for row in percentage_errors:
                    print(row)

            if apply_mode:
                updated = apply_updates(
                    connection,
                    traded_date,
                    matched
                )
                print(f"\nDelivery rows updated : {updated:,}")
            else:
                print("\nDry run only. No database changes made.")

    finally:
        connection.close()


if __name__ == "__main__":
    main()