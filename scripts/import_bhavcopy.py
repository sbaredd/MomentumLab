# Requirements: pandas psycopg2-binary python-dotenv
#!/usr/bin/env python3
"""
Momentum Lab - NSE Bhavcopy Sanitizer + PostgreSQL Importer

What this program does
----------------------
1. Reads NSE Bhavcopy CSV files directly or from ZIP files.
2. Sanitizes the NSE column names to the exact names used by:
       trn.nse_bhavcopy
3. Normalizes dates and numeric columns.
4. Validates required fields.
5. Removes exact duplicates within the incoming data.
6. Loads the sanitized data into a PostgreSQL staging table.
7. Inserts only records that are not already present in
       trn.nse_bhavcopy
   using (trad_dt, fin_instrm_id) as the natural key.
8. Prints an import summary.

Expected PostgreSQL table:
    trn.nse_bhavcopy

The program is deliberately designed so that running it twice will NOT
duplicate records already imported.

Install:
    pip install pandas psycopg2-binary

Example:
    python import_bhavcopy.py --input "C:\\MomentumLab\\BhavCopy\\Feb2026"

Or:
    python import_bhavcopy.py --input "C:\\MomentumLab\\BhavCopy\\Feb2026.zip"

Edit DB_CONFIG below to match your PostgreSQL installation.
"""

import argparse
import io
import os
import sys
import tempfile
import zipfile
from pathlib import Path

import pandas as pd
import psycopg2


# ============================================================
# 1. DATABASE CONFIGURATION
# ============================================================

# PostgreSQL connection is read from the project's .env file.
# Example .env:
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=momentumlab
# DB_USER=postgres
# DB_PASSWORD=your_password

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT_DIR = Path(r"C:\My Musings\2026\Bhavcopy\Feb2026\BhavCopy_NSE_CM_0_0_0_20260216_F_0000.csv")
ENV_FILE = PROJECT_ROOT / ".env"
load_dotenv(ENV_FILE)

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "momentumlab"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "GoodMenPrevail@25"),
}


# ============================================================
# 2. TARGET TABLE / COLUMN DEFINITIONS
# ============================================================

TARGET_SCHEMA = "trn"
TARGET_TABLE = "nse_bhavcopy"

# Exact 34-column order used by trn.nse_bhavcopy.
TARGET_COLUMNS = [
    "trad_dt",
    "biz_dt",
    "sgmt",
    "src",
    "fin_instrm_tp",
    "fin_instrm_id",
    "isin",
    "tckr_symb",
    "scty_srs",
    "xpry_dt",
    "fin_instrm_actl_xpry_dt",
    "strk_pric",
    "optn_tp",
    "fin_instrm_nm",
    "opn_pric",
    "hgh_pric",
    "lw_pric",
    "cls_pric",
    "last_pric",
    "prvs_clsg_pric",
    "undrlyg_pric",
    "sttlm_pric",
    "opn_intrst",
    "chng_in_opn_intrst",
    "ttl_tradg_vol",
    "ttl_trf_val",
    "ttl_nb_of_txs_exctd",
    "ssn_id",
    "new_brd_lot_qty",
    "rmks",
    "rsvd1",
    "rsvd2",
    "rsvd3",
    "rsvd4",
]

# NSE Bhavcopy column names -> PostgreSQL column names.
NSE_TO_PG = {
    "TradDt": "trad_dt",
    "BizDt": "biz_dt",
    "Sgmt": "sgmt",
    "Src": "src",
    "FinInstrmTp": "fin_instrm_tp",
    "FinInstrmId": "fin_instrm_id",
    "ISIN": "isin",
    "TckrSymb": "tckr_symb",
    "SctySrs": "scty_srs",
    "XpryDt": "xpry_dt",
    "FininstrmActlXpryDt": "fin_instrm_actl_xpry_dt",
    "StrkPric": "strk_pric",
    "OptnTp": "optn_tp",
    "FinInstrmNm": "fin_instrm_nm",
    "OpnPric": "opn_pric",
    "HghPric": "hgh_pric",
    "LwPric": "lw_pric",
    "ClsPric": "cls_pric",
    "LastPric": "last_pric",
    "PrvsClsgPric": "prvs_clsg_pric",
    "UndrlygPric": "undrlyg_pric",
    "SttlmPric": "sttlm_pric",
    "OpnIntrst": "opn_intrst",
    "ChngInOpnIntrst": "chng_in_opn_intrst",
    "TtlTradgVol": "ttl_tradg_vol",
    "TtlTrfVal": "ttl_trf_val",
    "TtlNbOfTxsExctd": "ttl_nb_of_txs_exctd",
    "SsnId": "ssn_id",
    "NewBrdLotQty": "new_brd_lot_qty",
    "Rmks": "rmks",
    "Rsvd1": "rsvd1",
    "Rsvd2": "rsvd2",
    "Rsvd3": "rsvd3",
    "Rsvd4": "rsvd4",
}

DATE_COLUMNS = [
    "trad_dt",
    "biz_dt",
    "xpry_dt",
    "fin_instrm_actl_xpry_dt",
]

NUMERIC_COLUMNS = [
    "fin_instrm_id",
    "strk_pric",
    "opn_pric",
    "hgh_pric",
    "lw_pric",
    "cls_pric",
    "last_pric",
    "prvs_clsg_pric",
    "undrlyg_pric",
    "sttlm_pric",
    "opn_intrst",
    "chng_in_opn_intrst",
    "ttl_tradg_vol",
    "ttl_trf_val",
    "ttl_nb_of_txs_exctd",
    "new_brd_lot_qty",
]


# ============================================================
# 3. FILE DISCOVERY
# ============================================================

def discover_files(input_path: Path):
    """
    Return all CSV files.

    ZIP files are extracted into a permanent working directory
    under the MomentumLab project instead of Windows TEMP.
    """

    if not input_path.exists():
        raise FileNotFoundError(
            f"Input path does not exist: {input_path}"
        )

    # ------------------------------------------------------------
    # Direct CSV
    # ------------------------------------------------------------
    if input_path.is_file() and input_path.suffix.lower() == ".csv":
        return [input_path], None

    # ------------------------------------------------------------
    # Working directory for extracted ZIP files
    # ------------------------------------------------------------
    extract_root = (
        PROJECT_ROOT
        / "data"
        / "bhavcopy_work"
    )

    extract_root.mkdir(
        parents=True,
        exist_ok=True
    )

    # ------------------------------------------------------------
    # Single ZIP
    # ------------------------------------------------------------
    if input_path.is_file() and input_path.suffix.lower() == ".zip":

        zip_dest = (
            extract_root
            / input_path.stem
        )

        zip_dest.mkdir(
            parents=True,
            exist_ok=True
        )

        with zipfile.ZipFile(input_path, "r") as z:
            z.extractall(zip_dest)

        csv_files = sorted(
            zip_dest.rglob("*.csv")
        )

        return csv_files, None

    # ------------------------------------------------------------
    # Directory containing CSV and/or ZIP files
    # ------------------------------------------------------------
    if input_path.is_dir():

        # Existing CSV files
        csv_files = sorted(
            input_path.rglob("*.csv")
        )

        # ZIP files
        zip_files = sorted(
            input_path.rglob("*.zip")
        )

        print(f"Found {len(zip_files)} ZIP file(s).")

        # Extract each ZIP
        for zfile in zip_files:

            zip_dest = (
                extract_root
                / zfile.stem
            )

            zip_dest.mkdir(
                parents=True,
                exist_ok=True
            )

            print(
                f"Extracting: {zfile.name}"
            )

            with zipfile.ZipFile(
                zfile,
                "r"
            ) as z:
                z.extractall(zip_dest)

            extracted_csvs = sorted(
                zip_dest.rglob("*.csv")
            )

            print(
                f"  Extracted CSVs: "
                f"{len(extracted_csvs)}"
            )

            csv_files.extend(
                extracted_csvs
            )

        # Remove duplicate paths
        csv_files = sorted(
            set(csv_files)
        )

        return csv_files, None

    raise ValueError(
        "Input must be a CSV, ZIP, or directory containing CSV/ZIP files."
    )


# ============================================================
# 4. SANITIZATION
# ============================================================

def normalize_column_lookup(columns):
    """
    Make matching tolerant of BOM and whitespace.
    Example:
        '\\ufeffTradDt' -> 'TradDt'
    """
    return {
        str(c).replace("\ufeff", "").strip(): c
        for c in columns
    }


def sanitize_dataframe(df: pd.DataFrame, source_name: str) -> pd.DataFrame:
    """Convert one NSE CSV into the exact PostgreSQL structure."""

    # Clean column names.
    df.columns = [
        str(c).replace("\ufeff", "").strip()
        for c in df.columns
    ]

    lookup = normalize_column_lookup(df.columns)

    missing_nse = [
        nse_col
        for nse_col in NSE_TO_PG
        if nse_col not in lookup
    ]

    if missing_nse:
        raise ValueError(
            f"{source_name}: missing NSE columns: {missing_nse}"
        )

    # Rename NSE columns.
    rename_actual = {
        lookup[nse_col]: pg_col
        for nse_col, pg_col in NSE_TO_PG.items()
    }

    df = df.rename(columns=rename_actual)

    # Keep exactly the target structure.
    missing_target = [
        c for c in TARGET_COLUMNS
        if c not in df.columns
    ]

    if missing_target:
        raise ValueError(
            f"{source_name}: missing target columns: {missing_target}"
        )

    df = df[TARGET_COLUMNS].copy()

    # --------------------------------------------------------
    # Dates
    # --------------------------------------------------------
    for col in DATE_COLUMNS:
        df[col] = pd.to_datetime(
            df[col],
            errors="coerce",
            dayfirst=False
        ).dt.strftime("%Y-%m-%d")

        # Empty / NaT -> PostgreSQL NULL.
        df[col] = df[col].replace(
            {"NaT": None, "nan": None, "": None}
        )

    # --------------------------------------------------------
    # Numeric fields
    # --------------------------------------------------------
    for col in NUMERIC_COLUMNS:
        df[col] = pd.to_numeric(
            df[col]
            .astype("string")
            .str.strip()
            .str.replace(",", "", regex=False),
            errors="coerce",
        )

    # --------------------------------------------------------
    # Text fields
    # --------------------------------------------------------
    text_columns = [
        c for c in TARGET_COLUMNS
        if c not in DATE_COLUMNS
        and c not in NUMERIC_COLUMNS
    ]

    for col in text_columns:
        df[col] = (
            df[col]
            .astype("string")
            .str.strip()
        )

    # Pandas <NA>/NaN -> None for CSV COPY.
    df = df.where(pd.notna(df), None)

    # --------------------------------------------------------
    # Mandatory-field validation
    # --------------------------------------------------------
    if df["trad_dt"].isna().any():
        bad = int(df["trad_dt"].isna().sum())
        raise ValueError(
            f"{source_name}: {bad} rows have invalid trad_dt."
        )

    if df["fin_instrm_id"].isna().any():
        bad = int(df["fin_instrm_id"].isna().sum())
        raise ValueError(
            f"{source_name}: {bad} rows have NULL/invalid "
            f"fin_instrm_id."
        )

    if df["biz_dt"].isna().any():
        bad = int(df["biz_dt"].isna().sum())
        raise ValueError(
            f"{source_name}: {bad} rows have NULL/invalid biz_dt."
        )

    # --------------------------------------------------------
    # Remove exact duplicates inside the incoming file.
    # DO NOT remove BL/EQ/etc. records merely because ticker/ISIN
    # are the same. fin_instrm_id distinguishes instruments.
    # --------------------------------------------------------
    before = len(df)
    df = df.drop_duplicates().reset_index(drop=True)
    removed = before - len(df)

    if removed:
        print(
            f"  {source_name}: removed {removed} exact duplicates."
        )

    return df


# ============================================================
# 5. READ + MERGE ALL FILES
# ============================================================

def build_sanitized_dataframe(csv_files):
    """Read and sanitize all discovered CSV files."""

    if not csv_files:
        raise ValueError("No CSV files found.")

    all_frames = []

    print(f"\nFound {len(csv_files)} CSV file(s).")

    for file in csv_files:
        print(f"Reading: {file.name}")

        # UTF-8-sig handles NSE files containing a BOM.
        df = pd.read_csv(
            file,
            dtype=str,
            encoding="utf-8-sig",
            keep_default_na=False,
        )

        print(f"  Source rows: {len(df):,}")

        clean = sanitize_dataframe(df, file.name)

        print(f"  Sanitized rows: {len(clean):,}")

        all_frames.append(clean)

    merged = pd.concat(
        all_frames,
        ignore_index=True
    )

    before = len(merged)

    # Exact duplicate removal across all files.
    merged = merged.drop_duplicates().reset_index(drop=True)

    exact_duplicates = before - len(merged)

    # Sort for deterministic processing.
    merged = merged.sort_values(
        ["trad_dt", "fin_instrm_id"],
        kind="stable"
    ).reset_index(drop=True)

    print("\nMERGED DATA")
    print("-----------")
    print(f"Rows: {len(merged):,}")
    print(f"Exact duplicates removed: {exact_duplicates:,}")
    print(
        f"Date range: {merged['trad_dt'].min()} "
        f"to {merged['trad_dt'].max()}"
    )

    print("\nRows by trading date:")
    print(
        merged.groupby("trad_dt")
        .size()
        .to_string()
    )

    return merged


# ============================================================
# 6. LOAD INTO POSTGRESQL
# ============================================================

def dataframe_to_csv_buffer(df):
    """Create an in-memory CSV suitable for PostgreSQL COPY."""

    buffer = io.StringIO()

    df.to_csv(
        buffer,
        index=False,
        header=True,
        na_rep="\\N",
        lineterminator="\n",
    )

    buffer.seek(0)
    return buffer


def import_to_postgres(df):
    """
    Stage the data and insert only new records.

    Natural key:
        (trad_dt, fin_instrm_id)

    This makes the program safe to run repeatedly.
    """

    conn = psycopg2.connect(**DB_CONFIG)

    try:
        conn.autocommit = False

        with conn.cursor() as cur:

            # ------------------------------------------------
            # Confirm target table exists.
            # ------------------------------------------------
            cur.execute(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = %s
                      AND table_name = %s
                );
                """,
                (TARGET_SCHEMA, TARGET_TABLE),
            )

            if not cur.fetchone()[0]:
                raise RuntimeError(
                    f"Target table {TARGET_SCHEMA}.{TARGET_TABLE} "
                    f"does not exist."
                )

            # ------------------------------------------------
            # Create a temporary staging table using the
            # actual PostgreSQL column data types.
            # ------------------------------------------------
            cur.execute(
                """
                DROP TABLE IF EXISTS tmp_nse_bhavcopy;
                """
            )

            column_sql = ", ".join(
                f'"{c}"' for c in TARGET_COLUMNS
            )

            cur.execute(
                f"""
                CREATE TEMP TABLE tmp_nse_bhavcopy AS
                SELECT {column_sql}
                FROM {TARGET_SCHEMA}.{TARGET_TABLE}
                WITH NO DATA;
                """
            )

            # ------------------------------------------------
            # COPY CSV -> staging table.
            # ------------------------------------------------
            csv_buffer = dataframe_to_csv_buffer(df)

            copy_sql = f"""
                COPY tmp_nse_bhavcopy ({column_sql})
                FROM STDIN
                WITH (
                    FORMAT CSV,
                    HEADER TRUE,
                    NULL '\\N'
                )
            """

            cur.copy_expert(
                copy_sql,
                csv_buffer
            )

            # ------------------------------------------------
            # Count staged rows.
            # ------------------------------------------------
            cur.execute(
                "SELECT COUNT(*) FROM tmp_nse_bhavcopy;"
            )

            staged_rows = cur.fetchone()[0]

            # ------------------------------------------------
            # Count records that already exist.
            # ------------------------------------------------
            cur.execute(
                f"""
                SELECT COUNT(*)
                FROM tmp_nse_bhavcopy s
                INNER JOIN {TARGET_SCHEMA}.{TARGET_TABLE} t
                    ON t.trad_dt = s.trad_dt
                   AND t.fin_instrm_id = s.fin_instrm_id;
                """
            )

            already_exists = cur.fetchone()[0]

            # ------------------------------------------------
            # Insert only new records.
            #
            # This deliberately uses NOT EXISTS instead of
            # requiring a UNIQUE constraint on the target table.
            # ------------------------------------------------
            cur.execute(
                f"""
                INSERT INTO {TARGET_SCHEMA}.{TARGET_TABLE}
                ({column_sql})
                SELECT {column_sql}
                FROM tmp_nse_bhavcopy s
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM {TARGET_SCHEMA}.{TARGET_TABLE} t
                    WHERE t.trad_dt = s.trad_dt
                      AND t.fin_instrm_id = s.fin_instrm_id
                );
                """
            )

            inserted_rows = cur.rowcount

            conn.commit()

            # ------------------------------------------------
            # Final verification for the imported date range.
            # ------------------------------------------------
            cur.execute(
                """
                SELECT
                    MIN(trad_dt),
                    MAX(trad_dt),
                    COUNT(*)
                FROM tmp_nse_bhavcopy;
                """
            )

            stage_min, stage_max, stage_count = cur.fetchone()

            cur.execute(
                f"""
                SELECT COUNT(*)
                FROM {TARGET_SCHEMA}.{TARGET_TABLE}
                WHERE trad_dt BETWEEN %s AND %s;
                """,
                (stage_min, stage_max),
            )

            target_range_rows = cur.fetchone()[0]

            print("\nPOSTGRESQL IMPORT")
            print("=================")
            print(f"Rows staged:        {staged_rows:,}")
            print(f"Already in table:   {already_exists:,}")
            print(f"Rows inserted:      {inserted_rows:,}")
            print(f"Date range:         {stage_min} -> {stage_max}")
            print(
                f"Target rows in range: "
                f"{target_range_rows:,}"
            )

            if inserted_rows + already_exists != staged_rows:
                raise RuntimeError(
                    "Import accounting mismatch. "
                    "Transaction will be rolled back."
                )

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()


# ============================================================
# 7. MAIN
# ============================================================

def main():

    parser = argparse.ArgumentParser(
        description="Sanitize and import NSE Bhavcopy into PostgreSQL."
    )

    parser.add_argument(
        "--input",
        required=True,
        help="CSV, ZIP, or directory containing NSE Bhavcopy files."
    )

    parser.add_argument(
        "--save-sanitized",
        action="store_true",
        help="Also save the merged sanitized CSV beside the input."
    )

    args = parser.parse_args()

    input_path = Path(args.input)

    print("====================================================")
    print(" MOMENTUM LAB - NSE BHAVCOPY IMPORT")
    print("====================================================")
    print(f"Input: {input_path}")
    print(
        f"Target: {TARGET_SCHEMA}.{TARGET_TABLE}"
    )

    csv_files, temp_dir = discover_files(input_path)

    try:
        df = build_sanitized_dataframe(csv_files)

        if args.save_sanitized:
            if input_path.is_dir():
                output_dir = input_path
            else:
                output_dir = input_path.parent

            output_file = (
                output_dir
                / "BhavCopy_Sanitized_Merged.csv"
            )

            df.to_csv(
                output_file,
                index=False,
                encoding="utf-8"
            )

            print(
                f"\nSanitized file saved to:\n"
                f"{output_file}"
            )

        import_to_postgres(df)

        print("\n====================================================")
        print(" IMPORT COMPLETED SUCCESSFULLY")
        print("====================================================")

    except Exception as exc:
        print("\nERROR")
        print("-----")
        print(str(exc))
        sys.exit(1)

    finally:
        if temp_dir is not None:
            temp_dir.cleanup()


if __name__ == "__main__":
    main()