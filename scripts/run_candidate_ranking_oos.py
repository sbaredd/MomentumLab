# ============================================================================
# MomentumLab
# File        : run_candidate_ranking_oos.py
# Version     : 1.0
# Purpose     : Capture Candidate Ranking V1 OOS observations for one date
# ============================================================================

from pathlib import Path
from datetime import datetime, date
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
    "database/features/candidate_ranking/"
    "001_capture_candidate_ranking_oos_observation.sql"
)


OOS_START_DATE = date(2026, 9, 14)


# ============================================================================
# ARGUMENTS
# ============================================================================

def parse_arguments():

    parser = argparse.ArgumentParser(
        description=(
            "Capture MomentumLab Candidate Ranking V1 OOS observations "
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

        evaluation_date = datetime.strptime(
            value,
            "%Y-%m-%d"
        ).date()

    except ValueError as exc:

        raise ValueError(
            "evaluation_date must be in YYYY-MM-DD format"
        ) from exc

    if evaluation_date < OOS_START_DATE:

        raise ValueError(
            "Candidate Ranking V1 OOS capture is not permitted before "
            f"{OOS_START_DATE}."
        )

    return evaluation_date
# ============================================================================
# DATABASE
# ============================================================================

def get_connection():

    return psycopg2.connect(
        **DB_CONFIG
    )


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

    readiness_sql = """
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
            readiness_sql,
            (
                evaluation_date,
            )
        )

        readiness_rows, pivot_rows = cursor.fetchone()

    if readiness_rows == 0:

        raise RuntimeError(
            "Candidate Ranking OOS source validation failed: "
            f"no Setup Readiness rows exist for {evaluation_date}."
        )


    coverage_sql = """
        SELECT COUNT(*)
        FROM trn.stock_setup_readiness_daily r

        WHERE r.trade_date = %s
          AND r.pivot_date IS NOT NULL
          AND r.pivot_price IS NOT NULL

          AND EXISTS
          (
              SELECT 1

              FROM trn.stock_setup_episode e

              WHERE e.security_id = r.security_id
                AND e.pivot_date = r.pivot_date
                AND e.pivot_price = r.pivot_price
                AND e.episode_start_date <= r.trade_date

                AND
                (
                    e.episode_status = 'ACTIVE'
                    OR e.episode_end_date = r.trade_date
                )
          );
    """

    with connection.cursor() as cursor:

        cursor.execute(
            coverage_sql,
            (
                evaluation_date,
            )
        )

        covered_pivot_rows = cursor.fetchone()[0]

    if covered_pivot_rows != pivot_rows:

        raise RuntimeError(
            "Candidate Ranking OOS source validation failed: "
            f"{covered_pivot_rows} pivot-bearing readiness rows map to "
            f"a current SR09 episode, but {pivot_rows} pivot-bearing rows "
            f"exist for {evaluation_date}."
        )

    return (
        readiness_rows,
        pivot_rows,
        covered_pivot_rows,
    )

# ============================================================================
# EXECUTION
# ============================================================================

def execute_capture(
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
):

    sql = """
        WITH eligible_observations AS
        (
            SELECT
                r.security_id,
                r.pivot_date,
                r.pivot_price,
                e.episode_start_date,
                r.trade_date AS observation_date,

                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        r.security_id,
                        r.pivot_date,
                        r.pivot_price,
                        e.episode_start_date
                    ORDER BY
                        r.trade_date
                ) AS eligible_seq

            FROM trn.stock_setup_readiness_daily r

            JOIN trn.stock_setup_episode e
              ON e.security_id = r.security_id
             AND e.pivot_date = r.pivot_date
             AND e.pivot_price = r.pivot_price
             AND r.trade_date >= e.episode_start_date
             AND
                (
                    e.episode_end_date IS NULL
                    OR r.trade_date <= e.episode_end_date
                )

            WHERE r.breakout_state = 'BELOW_PIVOT'
              AND r.pivot_proximity_pct >= -4
              AND r.pivot_proximity_pct < 0
        ),

        expected_first_entries AS
        (
            SELECT
                security_id,
                pivot_date,
                pivot_price,
                episode_start_date,
                observation_date
            FROM eligible_observations
            WHERE eligible_seq = 1
        )

        SELECT

            (
                SELECT COUNT(*)
                FROM trn.candidate_ranking_oos_observation
                WHERE observation_date = %s
            ) AS stored_rows,

            (
                SELECT COUNT(*)
                FROM expected_first_entries
                WHERE observation_date = %s
                  AND observation_date >= DATE '2026-09-14'
            ) AS expected_rows,


            (
                SELECT COUNT(*)
                FROM trn.candidate_ranking_oos_observation o
                WHERE o.observation_date = %s
                    AND NOT EXISTS
                (
                    SELECT 1
                    FROM expected_first_entries x
                    WHERE x.security_id = o.security_id
                        AND x.pivot_date = o.pivot_date
                        AND x.pivot_price = o.pivot_price
                        AND x.episode_start_date = o.episode_start_date
                        AND x.observation_date = o.observation_date
                )
            ) AS unexpected_rows,   


            (
                SELECT COUNT(*)
                FROM trn.candidate_ranking_oos_observation
                WHERE observation_date < DATE '2026-09-14'
            ) AS pre_oos_rows,

            (
                SELECT COUNT(*)
                FROM
                (
                    SELECT
                        security_id,
                        pivot_date,
                        pivot_price,
                        episode_start_date
                    FROM trn.candidate_ranking_oos_observation
                    GROUP BY
                        security_id,
                        pivot_date,
                        pivot_price,
                        episode_start_date
                    HAVING COUNT(*) > 1
                ) d
            ) AS duplicate_rows;
    """

    with connection.cursor() as cursor:

        cursor.execute(
            sql,
            (
                evaluation_date,
                evaluation_date,
                evaluation_date,
            )
        )

        (
            stored_rows,
            expected_rows,
            unexpected_rows,
            pre_oos_rows,
            duplicate_rows,
        ) = cursor.fetchone()

    if stored_rows != expected_rows:

        raise RuntimeError(
            "Candidate Ranking OOS validation failed: "
            f"{stored_rows} stored row(s) exist for {evaluation_date}, "
            f"but {expected_rows} first-entry observation(s) are expected."
        )

    if unexpected_rows != 0:

        raise RuntimeError(
            "Candidate Ranking OOS validation failed: "
            f"{unexpected_rows} stored observation(s) for "
            f"{evaluation_date} do not match the expected "
            "first-ever V1 eligible episode observation."
        )

    if pre_oos_rows != 0:

        raise RuntimeError(
            "Candidate Ranking OOS validation failed: "
            f"{pre_oos_rows} observation(s) exist before 2026-09-14."
        )

    if duplicate_rows != 0:

        raise RuntimeError(
            "Candidate Ranking OOS validation failed: "
            f"{duplicate_rows} duplicate structural episode identity row(s) exist."
        )

    return (
        stored_rows,
        expected_rows,
        unexpected_rows,
        pre_oos_rows,
        duplicate_rows,
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
    print("MOMENTUMLAB - CANDIDATE RANKING V1 OOS CAPTURE")
    print("=" * 70)

    print(
        f"Evaluation date        : {evaluation_date}"
    )

    connection = None

    try:

        connection = get_connection()

        print(
            "Database               : Connected"
        )

        (
            readiness_rows,
            pivot_rows,
            covered_pivot_rows,
        ) = validate_source(
            connection,
            evaluation_date,
        )

        print(
            f"Readiness rows         : {readiness_rows}"
        )

        print(
            f"Pivot-bearing rows     : {pivot_rows}"
        )

        print(
            f"SR09-covered rows      : {covered_pivot_rows}"
        )

        execute_capture(
            connection,
            evaluation_date,
        )

        (
            stored_rows,
            expected_rows,
            unexpected_rows,
            pre_oos_rows,
            duplicate_rows,
        ) = validate_result(
            connection,
            evaluation_date,
        )

        print()
        print("=" * 70)
        print("CANDIDATE RANKING V1 OOS VALIDATION")
        print("=" * 70)

        print(
            f"Stored rows            : {stored_rows}"
        )

        print(
            f"Expected rows          : {expected_rows}"
        )

        print(
            f"Unexpected rows        : {unexpected_rows}"
        )

        print(
            f"Pre-OOS rows           : {pre_oos_rows}"
        )

        print(
            f"Duplicate rows         : {duplicate_rows}"
        )

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
    print("CANDIDATE RANKING V1 OOS CAPTURE COMPLETE")
    print("=" * 70)

# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()
