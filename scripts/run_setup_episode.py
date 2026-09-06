# ============================================================================
# MomentumLab
# File        : run_setup_episode.py
# Version     : 1.0
# Purpose     : Execute SR09 Setup Episode engine for one evaluation date
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


SQL_FILE = (
    "database/features/setup_episode/"
    "056_populate_stock_setup_episode.sql"
)


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
            "Run MomentumLab SR09 Setup Episode engine "
            "for one evaluation date."
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
    into psycopg2 named parameter syntax.

    Named syntax is intentional because SR09 uses the
    evaluation date more than once in the same SQL file.

    Literal percentage signs are escaped for psycopg2
    parameter processing.
    """

    sql = sql.replace(
        "%",
        "%%"
    )

    sql = sql.replace(
        ":evaluation_date",
        "%(evaluation_date)s"
    )

    return sql


# ============================================================================
# SOURCE VALIDATION
# ============================================================================

def validate_source(
    connection,
    evaluation_date,
):

    sql = """
        SELECT
            COUNT(*) AS total_rows,

            COUNT(*) FILTER
            (
                WHERE pivot_date IS NOT NULL
                  AND pivot_price IS NOT NULL
            ) AS pivot_rows

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

        total_rows, pivot_rows = cursor.fetchone()

    if total_rows == 0:

        raise RuntimeError(
            "SR09 source validation failed: "
            f"no Setup Readiness rows exist for {evaluation_date}."
        )

    return (
        total_rows,
        pivot_rows,
    )


# ============================================================================
# EXECUTION
# ============================================================================

def execute_sr09(
    connection,
    evaluation_date,
):

    sql = load_sql(
        SQL_FILE
    )

    sql = prepare_sql(
        sql
    )

    print(
        f"Executing              : {SQL_FILE}"
    )

    with connection.cursor() as cursor:

        cursor.execute(
            sql,
            {
                "evaluation_date": evaluation_date
            }
        )

        affected_rows = cursor.rowcount

    print(
        f"Rows affected          : {affected_rows}"
    )

    return affected_rows


# ============================================================================
# RESULT VALIDATION
# ============================================================================

def validate_result(
    connection,
    evaluation_date,
    expected_active_rows,
):

    sql = """
        SELECT
            COUNT(*) AS total_episodes,

            COUNT(*) FILTER
            (
                WHERE episode_status = 'ACTIVE'
            ) AS active_episodes,

            COUNT(*) FILTER
            (
                WHERE episode_status = 'RESOLVED_BREAKOUT'
            ) AS resolved_breakouts,

            COUNT(*) FILTER
            (
                WHERE episode_status = 'SUPERSEDED'
            ) AS superseded_episodes,

            COUNT(*) FILTER
            (
                WHERE episode_status = 'EXPIRED'
            ) AS expired_episodes,

            COUNT(*) FILTER
            (
                WHERE
                (
                    episode_status = 'ACTIVE'
                    AND episode_end_date IS NOT NULL
                )
                OR
                (
                    episode_status <> 'ACTIVE'
                    AND episode_end_date IS NULL
                )
            ) AS invalid_end_dates,

            COUNT(*) FILTER
            (
                WHERE episode_status = 'RESOLVED_BREAKOUT'
                  AND
                  (
                      breakout_date IS NULL
                      OR terminal_breakout_state
                            <> 'CROSSED_AND_CLOSED_ABOVE'
                      OR breakout_date <> episode_end_date
                  )
            ) AS invalid_breakouts,

            COUNT(*) FILTER
            (
                WHERE episode_status <> 'RESOLVED_BREAKOUT'
                  AND breakout_date IS NOT NULL
            ) AS unexpected_breakout_dates,

            COUNT(*) FILTER
            (
                WHERE episode_start_date > %s
            ) AS future_episode_rows

        FROM trn.stock_setup_episode;
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
        total_episodes,
        active_episodes,
        resolved_breakouts,
        superseded_episodes,
        expired_episodes,
        invalid_end_dates,
        invalid_breakouts,
        unexpected_breakout_dates,
        future_episode_rows,
    ) = result


    # ------------------------------------------------------------------------
    # Active episode uniqueness
    # ------------------------------------------------------------------------

    duplicate_active_sql = """
        SELECT COUNT(*)
        FROM
        (
            SELECT
                security_id
            FROM trn.stock_setup_episode
            WHERE episode_status = 'ACTIVE'
            GROUP BY security_id
            HAVING COUNT(*) > 1
        ) x;
    """

    with connection.cursor() as cursor:

        cursor.execute(
            duplicate_active_sql
        )

        duplicate_active_securities = cursor.fetchone()[0]


    # ------------------------------------------------------------------------
    # Fail-fast validations
    # ------------------------------------------------------------------------

    if total_episodes == 0:

        raise RuntimeError(
            "SR09 validation failed: "
            "no setup episodes exist after population."
        )

    if active_episodes != expected_active_rows:

        raise RuntimeError(
            "SR09 validation failed: "
            f"ACTIVE episodes = {active_episodes}, "
            f"but pivot-bearing readiness rows for "
            f"{evaluation_date} = {expected_active_rows}."
        )

    if invalid_end_dates != 0:

        raise RuntimeError(
            "SR09 validation failed: "
            f"{invalid_end_dates} episode(s) have invalid "
            "ACTIVE/terminal end-date lifecycle state."
        )

    if invalid_breakouts != 0:

        raise RuntimeError(
            "SR09 validation failed: "
            f"{invalid_breakouts} RESOLVED_BREAKOUT episode(s) "
            "have invalid breakout lifecycle data."
        )

    if unexpected_breakout_dates != 0:

        raise RuntimeError(
            "SR09 validation failed: "
            f"{unexpected_breakout_dates} non-breakout episode(s) "
            "contain breakout_date."
        )

    if future_episode_rows != 0:

        raise RuntimeError(
            "SR09 validation failed: "
            f"{future_episode_rows} episode(s) start after "
            f"evaluation date {evaluation_date}. "
            "Back-dated SR09 execution against a later persisted "
            "episode state is not permitted."
        )

    if duplicate_active_securities != 0:

        raise RuntimeError(
            "SR09 validation failed: "
            f"{duplicate_active_securities} security/security(s) "
            "have more than one ACTIVE episode."
        )

    return (
        total_episodes,
        active_episodes,
        resolved_breakouts,
        superseded_episodes,
        expired_episodes,
    )


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
    print("MOMENTUM LAB - SETUP EPISODE")
    print("SR09 SINGLE-DATE ORCHESTRATOR")
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
        # Validate source readiness population.
        # --------------------------------------------------------------------

        (
            readiness_rows,
            pivot_rows,
        ) = validate_source(
            connection,
            evaluation_date
        )

        print(
            f"Readiness rows         : {readiness_rows}"
        )

        print(
            f"Pivot-bearing rows     : {pivot_rows}"
        )


        # --------------------------------------------------------------------
        # Execute SR09.
        # No commit occurs until all validations pass.
        # --------------------------------------------------------------------

        execute_sr09(
            connection,
            evaluation_date
        )


        # --------------------------------------------------------------------
        # Validate reconstructed episode state.
        # --------------------------------------------------------------------

        (
            total_episodes,
            active_episodes,
            resolved_breakouts,
            superseded_episodes,
            expired_episodes,
        ) = validate_result(
            connection,
            evaluation_date,
            pivot_rows
        )


        print()
        print("=" * 70)
        print("SR09 SETUP EPISODE VALIDATION")
        print("=" * 70)

        print(
            f"Total episodes         : {total_episodes}"
        )

        print(
            f"ACTIVE                 : {active_episodes}"
        )

        print(
            f"RESOLVED_BREAKOUT      : {resolved_breakouts}"
        )

        print(
            f"SUPERSEDED             : {superseded_episodes}"
        )

        print(
            f"EXPIRED                : {expired_episodes}"
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
    print("SETUP EPISODE SR09 COMPLETE")
    print("=" * 70)


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()