# ============================================================================
# MomentumLab
# File        : run_setup_readiness.py
# Version     : 1.1
# Purpose     : Execute Setup Readiness SR01-SR08 for one evaluation date
# ============================================================================

from pathlib import Path
from datetime import datetime
import argparse
import os

import psycopg2
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
# SQL EXECUTION ORDER
#
# Dependency:
#
#   Market Structure
#       -> Base Episode
#       -> Structural Pivot
#       -> Setup Readiness Initialization
#       -> SR01-SR08
#
# stock_market_structure_daily is already historical and is therefore
# not recalculated by this single-date orchestrator.
# ============================================================================

SQL_FILES = [
    "database/features/base_quality/030_populate_base_episode_daily.sql",
    "database/features/pivot/045_populate_stock_pivot_daily.sql",
    "database/features/setup_readiness/045a_initialize_setup_readiness_daily.sql",
    "database/features/setup_readiness/046_sr01_breakout_state.sql",
    "database/features/setup_readiness/047_sr02_pivot_proximity.sql",
    "database/features/setup_readiness/048_sr03_breakout_volume.sql",
    "database/features/setup_readiness/049_sr03_breakout_volume_state.sql",
    "database/features/setup_readiness/050_sr04_breakout_extension.sql",
    "database/features/setup_readiness/051_sr05_pivot_tightness.sql",
    "database/features/setup_readiness/052_sr06_pivot_volume_dryup.sql",
    "database/features/setup_readiness/053_sr07_prebreakout_price_progression.sql",
    "database/features/setup_readiness/054_sr08_structural_entry_risk.sql",
]


# ============================================================================
# DATABASE
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


# ============================================================================
# ARGUMENTS
# ============================================================================

def parse_arguments():

    parser = argparse.ArgumentParser(
        description=(
            "Run MomentumLab Setup Readiness "
            "SR01-SR08 for one evaluation date."
        )
    )

    parser.add_argument(
        "evaluation_date",
        help="Evaluation date in YYYY-MM-DD format"
    )

    return parser.parse_args()


def validate_evaluation_date(value):

    try:

        return datetime.strptime(
            value,
            "%Y-%m-%d"
        ).date()

    except ValueError as exc:

        raise ValueError(
            "evaluation_date must be in YYYY-MM-DD format"
        ) from exc


# ============================================================================
# SQL
# ============================================================================

def load_sql(sql_file):

    # SQL_FILES contains paths relative to the MomentumLab project root.
    sql_path = PROJECT_ROOT / sql_file

    if not sql_path.exists():

        raise FileNotFoundError(
            f"SQL file not found: {sql_path}"
        )

    return sql_path.read_text(
        encoding="utf-8"
    )


def prepare_sql(sql):

    """
    Convert DBeaver-style :evaluation_date parameter
    into psycopg2 positional parameter syntax.

    Literal percentage signs in SQL are escaped for
    psycopg2 parameter processing.
    """

    # Escape literal % signs first.
    sql = sql.replace(
        "%",
        "%%"
    )

    # Replace the DBeaver parameter with psycopg2 syntax.
    sql = sql.replace(
        ":evaluation_date",
        "%s"
    )

    return sql


# ============================================================================
# EXECUTION
# ============================================================================

def execute_sql_file(
    connection,
    sql_file,
    evaluation_date
):

    sql = load_sql(
        sql_file
    )

    sql = prepare_sql(
        sql
    )

    print(
        f"Executing              : {sql_file}"
    )

    with connection.cursor() as cursor:

        cursor.execute(
            sql,
            (
                evaluation_date,
            )
        )

        affected_rows = cursor.rowcount

    print(
        f"Rows affected          : {affected_rows}"
    )


def run_setup_readiness(
    connection,
    evaluation_date
):

    for sql_file in SQL_FILES:

        execute_sql_file(
            connection,
            sql_file,
            evaluation_date
        )


# ============================================================================
# VALIDATION
# ============================================================================

# ============================================================================
# VALIDATION
# ============================================================================

def validate_result(
    connection,
    evaluation_date,
):

    sql = """
        SELECT
            COUNT(*) AS total_rows,

            COUNT(*) FILTER
            (
                WHERE breakout_state IS NOT NULL
            ) AS sr01_rows,

            COUNT(*) FILTER
            (
                WHERE pivot_proximity_pct IS NOT NULL
            ) AS sr02_rows,

            COUNT(*) FILTER
            (
                WHERE relative_volume_20 IS NOT NULL
            ) AS sr03_rows,

            COUNT(*) FILTER
            (
                WHERE atr_pct IS NOT NULL
            ) AS sr04_rows,

            COUNT(*) FILTER
            (
                WHERE recent_5_range_pct IS NOT NULL
            ) AS sr05_rows,

            COUNT(*) FILTER
            (
                WHERE recent_5_volume_vs_20d_pct IS NOT NULL
            ) AS sr06_rows,

            COUNT(*) FILTER
            (
                WHERE prebreakout_5d_return_pct IS NOT NULL
            ) AS sr07_rows,

            COUNT(*) FILTER
            (
                WHERE prebreakout_5d_low IS NOT NULL
            ) AS sr08_rows

        FROM trn.stock_setup_readiness_daily

        WHERE trade_date = %s;
    """

    with connection.cursor() as cursor:

        cursor.execute(
            sql,
            (
                evaluation_date,
            )
        )

        result = cursor.fetchone()

    (
        total_rows,
        sr01_rows,
        sr02_rows,
        sr03_rows,
        sr04_rows,
        sr05_rows,
        sr06_rows,
        sr07_rows,
        sr08_rows,
    ) = result

    # ------------------------------------------------------------------------
    # Fail-fast validation
    #
    # SR02 is intentionally excluded from equality validation because
    # pivot_proximity_pct is legitimately NULL when no active pivot exists.
    # ------------------------------------------------------------------------

    if total_rows == 0:

        raise RuntimeError(
            f"No Setup Readiness rows produced for {evaluation_date}"
        )

    required_features = {
        "SR01 breakout state": sr01_rows,
        "SR03 relative volume": sr03_rows,
        "SR04 ATR": sr04_rows,
        "SR05 tightness": sr05_rows,
        "SR06 volume dry-up": sr06_rows,
        "SR07 progression": sr07_rows,
        "SR08 structural risk": sr08_rows,
    }

    for feature_name, populated_rows in required_features.items():

        if populated_rows != total_rows:

            raise RuntimeError(
                f"{feature_name} validation failed for {evaluation_date}: "
                f"{populated_rows}/{total_rows} rows populated"
            )

    return result

# ============================================================================
# MAIN
# ============================================================================

def main():

    args = parse_arguments()

    evaluation_date = validate_evaluation_date(
        args.evaluation_date
    )

    print()
    print("=" * 70)
    print("MOMENTUM LAB - SETUP READINESS")
    print("SR01-SR08 SINGLE-DATE ORCHESTRATOR")
    print("=" * 70)

    print(
        f"Evaluation date        : {evaluation_date}"
    )

    connection = None

    try:

        # --------------------------------------------------------------------
        # Connect
        # --------------------------------------------------------------------

        connection = get_connection()

        print(
            "Database               : Connected"
        )

        # --------------------------------------------------------------------
        # Execute complete dependency chain.
        #
        # 030  Base Episode
        # 045  Structural Pivot
        # 045a Setup Readiness Initialization
        # 046-054 SR01-SR08
        #
        # No commit occurs between individual SQL steps.
        # --------------------------------------------------------------------

        run_setup_readiness(
            connection,
            evaluation_date
        )

        # --------------------------------------------------------------------
        # Validate before commit.
        # --------------------------------------------------------------------

        result = validate_result(
            connection,
            evaluation_date
        )

        (
            total_rows,
            sr01_rows,
            sr02_rows,
            sr03_rows,
            sr04_rows,
            sr05_rows,
            sr06_rows,
            sr07_rows,
            sr08_rows
        ) = result

        print()
        print("=" * 70)
        print("SETUP READINESS VALIDATION")
        print("=" * 70)

        print(
            f"Total rows             : {total_rows}"
        )

        print(
            f"SR01 breakout state    : {sr01_rows}"
        )

        print(
            f"SR02 pivot proximity   : {sr02_rows}"
        )

        print(
            f"SR03 relative volume   : {sr03_rows}"
        )

        print(
            f"SR04 ATR               : {sr04_rows}"
        )

        print(
            f"SR05 tightness         : {sr05_rows}"
        )

        print(
            f"SR06 volume dry-up     : {sr06_rows}"
        )

        print(
            f"SR07 progression       : {sr07_rows}"
        )

        print(
            f"SR08 structural risk   : {sr08_rows}"
        )

        # --------------------------------------------------------------------
        # Fail if initialization produced no rows.
        #
        # This prevents a missing upstream dependency/date from appearing
        # to be a successful Setup Readiness run.
        # --------------------------------------------------------------------

        if total_rows == 0:

            raise RuntimeError(
                "Setup Readiness validation failed: "
                f"no rows were produced for {evaluation_date}."
            )

        # --------------------------------------------------------------------
        # Atomic commit.
        # --------------------------------------------------------------------

        connection.commit()

        print()
        print(
            "Transaction            : COMMITTED"
        )

    except Exception as exc:

        if connection is not None:

            connection.rollback()

            print()
            print(
                "Transaction            : ROLLED BACK"
            )

        print()
        print("ERROR")
        print(exc)

        raise

    finally:

        if connection is not None:

            connection.close()

            print(
                "Database               : Connection closed"
            )

    print()
    print("=" * 70)
    print("SETUP READINESS SR01-SR08 COMPLETE")
    print("=" * 70)


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()