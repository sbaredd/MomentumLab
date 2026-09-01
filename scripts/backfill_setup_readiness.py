# ============================================================================
# MomentumLab
# File        : backfill_setup_readiness.py
# Version     : 1.0
# Purpose     : Historical backfill of Setup Readiness SR01-SR08
#
# Usage:
#
#   python scripts\backfill_setup_readiness.py 2026-08-10 2026-08-13
#
# Design:
#
#   - Determines actual trading dates from NSE bhavdata.
#   - Executes the validated single-date Setup Readiness pipeline.
#   - Commits each trading date independently.
#   - Rolls back the current date if that date fails.
#   - Stops immediately on failure.
# ============================================================================

from datetime import datetime
import argparse

from run_setup_readiness import (
    get_connection,
    run_setup_readiness,
    validate_result,
)


# ============================================================================
# ARGUMENTS
# ============================================================================

def parse_arguments():

    parser = argparse.ArgumentParser(
        description=(
            "Backfill MomentumLab Setup Readiness "
            "SR01-SR08 for a historical date range."
        )
    )

    parser.add_argument(
        "start_date",
        help="Start date in YYYY-MM-DD format"
    )

    parser.add_argument(
        "end_date",
        help="End date in YYYY-MM-DD format"
    )

    return parser.parse_args()


def parse_date(value, argument_name):

    try:

        return datetime.strptime(
            value,
            "%Y-%m-%d"
        ).date()

    except ValueError as exc:

        raise ValueError(
            f"{argument_name} must be in YYYY-MM-DD format"
        ) from exc


# ============================================================================
# TRADING DATES
# ============================================================================

def get_trading_dates(
    connection,
    start_date,
    end_date
):

    """
    Use actual NSE EQ bhavdata dates rather than calendar days.

    This automatically excludes weekends and exchange holidays
    for which no EQ trading data exists.
    """

    sql = """
        SELECT DISTINCT
            traded_date
        FROM trn.nse_sec_bhavdata
        WHERE traded_date BETWEEN %s AND %s
          AND series = 'EQ'
        ORDER BY traded_date;
    """

    with connection.cursor() as cursor:

        cursor.execute(
            sql,
            (
                start_date,
                end_date,
            )
        )

        rows = cursor.fetchall()

    return [
        row[0]
        for row in rows
    ]


# ============================================================================
# VALIDATION
# ============================================================================

def print_validation(
    evaluation_date,
    result
):

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
    print(
        f"Validation             : {evaluation_date}"
    )

    print(
        f"  Total rows           : {total_rows}"
    )

    print(
        f"  SR01 breakout state  : {sr01_rows}"
    )

    print(
        f"  SR02 pivot proximity : {sr02_rows}"
    )

    print(
        f"  SR03 relative volume : {sr03_rows}"
    )

    print(
        f"  SR04 ATR             : {sr04_rows}"
    )

    print(
        f"  SR05 tightness       : {sr05_rows}"
    )

    print(
        f"  SR06 volume dry-up   : {sr06_rows}"
    )

    print(
        f"  SR07 progression     : {sr07_rows}"
    )

    print(
        f"  SR08 structural risk : {sr08_rows}"
    )

    return total_rows


# ============================================================================
# BACKFILL
# ============================================================================

def backfill(
    connection,
    trading_dates
):

    total_dates = len(
        trading_dates
    )

    successful_dates = 0

    for sequence, evaluation_date in enumerate(
        trading_dates,
        start=1
    ):

        print()
        print("=" * 70)

        print(
            f"PROCESSING {sequence}/{total_dates}"
        )

        print(
            f"Evaluation date        : {evaluation_date}"
        )

        print("=" * 70)

        try:

            # --------------------------------------------------------------
            # Execute the already validated single-date dependency chain:
            #
            # 030 Base Episode
            # 045 Structural Pivot
            # 045a Readiness Initialization
            # 046-054 SR01-SR08
            # --------------------------------------------------------------

            run_setup_readiness(
                connection,
                evaluation_date
            )

            # --------------------------------------------------------------
            # Validate before committing this date.
            # --------------------------------------------------------------

            result = validate_result(
                connection,
                evaluation_date
            )

            total_rows = print_validation(
                evaluation_date,
                result
            )

            # --------------------------------------------------------------
            # A trading date with zero Setup Readiness rows is considered
            # a failed historical calculation.
            # --------------------------------------------------------------

            if total_rows == 0:

                raise RuntimeError(
                    "No Setup Readiness rows produced "
                    f"for {evaluation_date}"
                )

            # --------------------------------------------------------------
            # Commit one date at a time.
            #
            # This gives us a restartable historical backfill:
            # successful earlier dates remain committed if a later date fails.
            # --------------------------------------------------------------

            connection.commit()

            successful_dates += 1

            print(
                f"Transaction            : COMMITTED ({evaluation_date})"
            )

        except Exception:

            connection.rollback()

            print(
                f"Transaction            : ROLLED BACK ({evaluation_date})"
            )

            raise

    return successful_dates


# ============================================================================
# MAIN
# ============================================================================

def main():

    args = parse_arguments()

    start_date = parse_date(
        args.start_date,
        "start_date"
    )

    end_date = parse_date(
        args.end_date,
        "end_date"
    )

    if start_date > end_date:

        raise ValueError(
            "start_date cannot be later than end_date"
        )

    print()
    print("=" * 70)
    print("MOMENTUM LAB - SETUP READINESS HISTORICAL BACKFILL")
    print("=" * 70)

    print(
        f"Start date             : {start_date}"
    )

    print(
        f"End date               : {end_date}"
    )

    connection = None

    try:

        connection = get_connection()

        print(
            "Database               : Connected"
        )

        # ------------------------------------------------------------------
        # Resolve actual NSE trading sessions.
        # ------------------------------------------------------------------

        trading_dates = get_trading_dates(
            connection,
            start_date,
            end_date
        )

        print(
            f"Trading dates found    : {len(trading_dates)}"
        )

        if not trading_dates:

            raise RuntimeError(
                "No NSE EQ trading dates found "
                f"between {start_date} and {end_date}"
            )

        print()
        print("Trading sessions:")

        for trade_date in trading_dates:

            print(
                f"  {trade_date}"
            )

        # ------------------------------------------------------------------
        # Historical calculation.
        # ------------------------------------------------------------------

        successful_dates = backfill(
            connection,
            trading_dates
        )

        print()
        print("=" * 70)
        print("BACKFILL COMPLETE")
        print("=" * 70)

        print(
            f"Trading dates requested : {len(trading_dates)}"
        )

        print(
            f"Trading dates completed : {successful_dates}"
        )

        print(
            f"Start date              : {trading_dates[0]}"
        )

        print(
            f"End date                : {trading_dates[-1]}"
        )

    except Exception as exc:

        if connection is not None:

            connection.rollback()

        print()
        print("=" * 70)
        print("BACKFILL FAILED")
        print("=" * 70)

        print(
            f"Error                   : {exc}"
        )

        raise

    finally:

        if connection is not None:

            connection.close()

            print()
            print(
                "Database               : Connection closed"
            )


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":

    main()