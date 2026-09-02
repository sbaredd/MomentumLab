"""
MomentumLab
File    : import_security_universe.py
Purpose : Refresh current security membership for a named universe.

Supported universes:
    NIFTY_100
    NIFTY_500
    NIFTY_MIDCAP_250
    NIFTY_SMALLCAP_250
    FO

Input CSV format expected:
    Company Name
    Industry
    Symbol
    Series
    ISIN Code

Matching strategy:
    1. Match by ISIN where available
    2. Validate symbol against ref.ref_nse_equity_security
    3. Reject unmatched or ambiguous rows

Refresh strategy:
    DELETE existing membership for selected universe
    INSERT current resolved membership
    COMMIT only if validation passes
"""

import argparse
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values


SUPPORTED_UNIVERSES = {
    "NIFTY_100",
    "NIFTY_500",
    "NIFTY_MIDCAP_250",
    "NIFTY_SMALLCAP_250",
    "FO",
}

REQUIRED_COLUMNS = {
    "Symbol",
    "ISIN Code",
}


def get_connection():
    load_dotenv()

    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "momentumlab"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


def read_input_csv(file_path: str) -> pd.DataFrame:
    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {path}")

    df = pd.read_csv(path)

    missing = REQUIRED_COLUMNS - set(df.columns)

    if missing:
        raise ValueError(
            f"Missing required CSV columns: {sorted(missing)}"
        )

    df = df.copy()

    df["Symbol"] = (
        df["Symbol"]
        .astype(str)
        .str.strip()
        .str.upper()
    )

    df["ISIN Code"] = (
        df["ISIN Code"]
        .astype(str)
        .str.strip()
        .str.upper()
    )

    if "Series" in df.columns:
        df["Series"] = (
            df["Series"]
            .astype(str)
            .str.strip()
            .str.upper()
        )

        non_eq = df[df["Series"] != "EQ"]

        if not non_eq.empty:
            print(
                f"WARNING: {len(non_eq)} rows are not Series=EQ"
            )

    duplicates = df[df.duplicated(subset=["ISIN Code"], keep=False)]

    if not duplicates.empty:
        print("\nDuplicate ISIN rows found in input:")
        print(
            duplicates[
                ["Symbol", "ISIN Code"]
            ].to_string(index=False)
        )

        raise ValueError("Input CSV contains duplicate ISIN values.")

    return df


def fetch_security_master(conn) -> pd.DataFrame:
    sql = """
        SELECT
            security_id,
            symbol,
            isin
        FROM ref.ref_nse_equity_security
        ORDER BY security_id;
    """

    return pd.read_sql(sql, conn)


def resolve_members(df: pd.DataFrame, master: pd.DataFrame):
    master = master.copy()

    master["symbol"] = (
        master["symbol"]
        .astype(str)
        .str.strip()
        .str.upper()
    )

    master["isin"] = (
        master["isin"]
        .fillna("")
        .astype(str)
        .str.strip()
        .str.upper()
    )

    by_isin = {
        row.isin: row
        for row in master.itertuples(index=False)
        if row.isin
    }

    resolved = []
    unmatched = []
    symbol_mismatch = []

    for row in df.itertuples(index=False):
        symbol = getattr(row, "Symbol")
        isin = getattr(row, "_4") if False else None

    # itertuples sanitizes "ISIN Code", so iterate explicitly
    for _, row in df.iterrows():
        symbol = row["Symbol"]
        isin = row["ISIN Code"]

        security = by_isin.get(isin)

        if security is None:
            unmatched.append(
                {
                    "symbol": symbol,
                    "isin": isin,
                    "reason": "ISIN not found in security master",
                }
            )
            continue

        if security.symbol != symbol:
            symbol_mismatch.append(
                {
                    "csv_symbol": symbol,
                    "master_symbol": security.symbol,
                    "isin": isin,
                    "security_id": security.security_id,
                }
            )

        resolved.append(
            (
                int(security.security_id),
                symbol,
                isin,
            )
        )

    return resolved, unmatched, symbol_mismatch


def ensure_universe_exists(conn, universe_code: str):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT 1
            FROM ref.ref_security_universe
            WHERE universe_code = %s
              AND is_active = TRUE;
            """,
            (universe_code,),
        )

        if cur.fetchone() is None:
            raise ValueError(
                f"Universe {universe_code} does not exist or is inactive."
            )


def refresh_membership(
    conn,
    universe_code: str,
    resolved_members,
):
    security_ids = [
        member[0]
        for member in resolved_members
    ]

    if len(security_ids) != len(set(security_ids)):
        raise ValueError(
            "Duplicate security_id values detected after resolution."
        )

    with conn.cursor() as cur:
        cur.execute(
            """
            DELETE FROM ref.security_universe_membership
            WHERE universe_code = %s;
            """,
            (universe_code,),
        )

        rows = [
            (universe_code, security_id)
            for security_id in security_ids
        ]

        execute_values(
            cur,
            """
            INSERT INTO ref.security_universe_membership
            (
                universe_code,
                security_id
            )
            VALUES %s
            """,
            rows,
        )


def validate_database_count(conn, universe_code: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COUNT(*)
            FROM ref.security_universe_membership
            WHERE universe_code = %s;
            """,
            (universe_code,),
        )

        return cur.fetchone()[0]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Refresh MomentumLab security universe membership."
    )

    parser.add_argument(
        "--universe",
        required=True,
        choices=sorted(SUPPORTED_UNIVERSES),
        help="Universe code to refresh.",
    )

    parser.add_argument(
        "--file",
        required=True,
        help="Path to NSE constituent CSV.",
    )

    parser.add_argument(
        "--expected-count",
        type=int,
        default=None,
        help="Optional expected membership count.",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    universe_code = args.universe.upper()

    print("=" * 72)
    print("MomentumLab - Security Universe Import")
    print("=" * 72)
    print(f"Universe : {universe_code}")
    print(f"File     : {args.file}")

    try:
        df = read_input_csv(args.file)

        print(f"CSV rows : {len(df)}")

        if args.expected_count is not None:
            if len(df) != args.expected_count:
                raise ValueError(
                    f"CSV row count {len(df)} does not match "
                    f"expected count {args.expected_count}."
                )

        conn = get_connection()

        try:
            ensure_universe_exists(conn, universe_code)

            master = fetch_security_master(conn)

            resolved, unmatched, mismatches = resolve_members(
                df,
                master,
            )

            print(f"Resolved : {len(resolved)}")
            print(f"Unmatched: {len(unmatched)}")
            print(f"Mismatch : {len(mismatches)}")

            if mismatches:
                print("\nSymbol / ISIN mismatches:")
                for item in mismatches:
                    print(
                        f"  ISIN={item['isin']} "
                        f"CSV={item['csv_symbol']} "
                        f"MASTER={item['master_symbol']}"
                    )

            if unmatched:
                print("\nUnmatched securities:")
                for item in unmatched:
                    print(
                        f"  {item['symbol']} | "
                        f"{item['isin']} | "
                        f"{item['reason']}"
                    )

                raise ValueError(
                    "Universe refresh aborted because "
                    "one or more securities could not be resolved."
                )

            if len(resolved) != len(df):
                raise ValueError(
                    "Resolved row count does not match CSV row count."
                )

            refresh_membership(
                conn,
                universe_code,
                resolved,
            )

            db_count = validate_database_count(
                conn,
                universe_code,
            )

            if db_count != len(resolved):
                raise ValueError(
                    f"Database count {db_count} does not match "
                    f"resolved count {len(resolved)}."
                )

            if args.expected_count is not None:
                if db_count != args.expected_count:
                    raise ValueError(
                        f"Database count {db_count} does not match "
                        f"expected count {args.expected_count}."
                    )

            conn.commit()

            print("\nRefresh completed successfully.")
            print(f"Database membership count: {db_count}")

        except Exception:
            conn.rollback()
            raise

        finally:
            conn.close()

    except Exception as exc:
        print(f"\nERROR: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()