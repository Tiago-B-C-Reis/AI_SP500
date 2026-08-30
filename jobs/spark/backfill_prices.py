#!/usr/bin/env python3
"""
Historical price backfill:  S3 raw/  ->  Iceberg  silver.prices_daily

WHY THIS ONE JOB IS SPARK AND THE DAILY PATH IS NOT
---------------------------------------------------
The daily increment is ~2 MB and stays in Athena SQL (sql/athena/prepared/).
This job is different in kind, not just in size:

  1. It reads the ENTIRE raw archive — tens of thousands of small, gzipped
     JSON objects. Many-small-files reads are where a distributed engine
     actually earns its keep; Athena degrades on this shape.
  2. Alpha Vantage nests its time series under a dynamic map keyed by date
     ({"2024-01-05": {"1. open": ...}}). Athena's JSON SerDe needs a static
     column per key; Spark flattens it programmatically with one explode.
  3. It runs rarely — initial load plus reprocessing after a parsing change.
     Per-run billing on EMR Serverless makes rare + heavy the cheapest shape
     there is, and zero when idle.

See docs/adr/ADR-004-spark-for-bulk-backfill.md.

RUN
---
  aws emr-serverless start-job-run \
    --application-id "$EMR_APP_ID" \
    --execution-role-arn "$EMR_ROLE_ARN" \
    --job-driver '{"sparkSubmit":{
        "entryPoint":"s3://<lake>/jobs/backfill_prices.py",
        "entryPointArguments":["--lake-bucket","<lake>","--function","TIME_SERIES_WEEKLY_ADJUSTED"],
        "sparkSubmitParameters":"--conf spark.jars.packages=org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.5.2,software.amazon.awssdk:bundle:2.25.11"
    }}'

Locally (needs ~4 GB; do NOT run this on the TrueNAS):
  spark-submit --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.5.2 \
      backfill_prices.py --lake-bucket <lake> --function TIME_SERIES_WEEKLY_ADJUSTED
"""

from __future__ import annotations

import argparse
import sys

from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import MapType, StringType, StructField, StructType

# Alpha Vantage names the time-series block differently per function, and the
# name is not derivable from the function id — so it is a lookup, not a rule.
SERIES_KEY = {
    "TIME_SERIES_DAILY_ADJUSTED": "Time Series (Daily)",
    "TIME_SERIES_WEEKLY_ADJUSTED": "Weekly Adjusted Time Series",
    "TIME_SERIES_MONTHLY_ADJUSTED": "Monthly Adjusted Time Series",
}

# Field names carry their ordinal prefix in the API payload.
FIELDS = {
    "open": "1. open",
    "high": "2. high",
    "low": "3. low",
    "close": "4. close",
    "adj_close": "5. adjusted close",
    "volume": "6. volume",
}

CATALOG = "lake"


def build_spark(warehouse: str) -> SparkSession:
    """Iceberg tables through the Glue catalog — the same metastore Athena reads,
    so Spark-written and Athena-written rows land in one table with one schema."""
    return (
        SparkSession.builder.appName("ai_sp500_backfill_prices")
        .config(
            "spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        )
        .config(f"spark.sql.catalog.{CATALOG}", "org.apache.iceberg.spark.SparkCatalog")
        .config(
            f"spark.sql.catalog.{CATALOG}.catalog-impl",
            "org.apache.iceberg.aws.glue.GlueCatalog",
        )
        .config(f"spark.sql.catalog.{CATALOG}.warehouse", warehouse)
        .config(
            f"spark.sql.catalog.{CATALOG}.io-impl", "org.apache.iceberg.aws.s3.S3FileIO"
        )
        # Small inputs, small output: keep Spark from writing hundreds of tiny
        # files into an Iceberg table we then have to compact.
        .config("spark.sql.shuffle.partitions", "16")
        .getOrCreate()
    )


def read_raw(spark: SparkSession, path: str, series_key: str):
    """One row per source file -> one row per (symbol, trade_date) bar."""
    schema = StructType(
        [
            StructField("Meta Data", MapType(StringType(), StringType())),
            StructField(
                series_key, MapType(StringType(), MapType(StringType(), StringType()))
            ),
        ]
    )

    files = spark.read.text(path, wholetext=True).select(
        F.input_file_name().alias("src_file"), F.col("value").alias("body")
    )

    parsed = files.select(
        "src_file", F.from_json("body", schema).alias("doc")
    ).where(F.col("doc").isNotNull())

    return parsed.select(
        F.col("doc")["Meta Data"]["2. Symbol"].alias("symbol"),
        F.explode(F.col("doc")[series_key]).alias("date_key", "bar"),
        # The fetch timestamp is encoded in the filename
        # (FUNCTION_SYMBOL_YYYYMMDDHHMMSS.json), so re-running is idempotent:
        # ordering reflects when the data was retrieved, not when we reprocessed it.
        F.regexp_extract(F.col("src_file"), r"(\d{14})\.json", 1).alias("fetched_raw"),
    )


def to_silver(bars):
    typed = bars.select(
        F.col("symbol"),
        F.to_date("date_key").alias("trade_date"),
        *[
            F.col("bar")[src].cast("double").alias(name)
            for name, src in FIELDS.items()
            if name != "volume"
        ],
        F.col("bar")["6. volume"].cast("long").alias("volume"),
        F.lit("alpha_vantage").alias("source"),
        F.to_timestamp("fetched_raw", "yyyyMMddHHmmss").alias("fetched_at"),
    ).where(F.col("symbol").isNotNull() & F.col("trade_date").isNotNull())

    # Raw partitions overlap by design (a week re-fetched on Tue and again on
    # Fri). Last-write-wins per business key, ordered by fetch time.
    dedupe = Window.partitionBy("symbol", "trade_date").orderBy(F.col("fetched_at").desc())
    return (
        typed.withColumn("_rn", F.row_number().over(dedupe))
        .where(F.col("_rn") == 1)
        .drop("_rn")
    )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lake-bucket", required=True)
    ap.add_argument("--function", default="TIME_SERIES_WEEKLY_ADJUSTED", choices=sorted(SERIES_KEY))
    ap.add_argument("--category", default="Core_Stock_APIs")
    ap.add_argument(
        "--dry-run", action="store_true", help="parse and count, write nothing"
    )
    args = ap.parse_args(argv)

    series_key = SERIES_KEY[args.function]
    raw_path = f"s3://{args.lake_bucket}/raw/{args.category}/{args.function}/*/*.json"
    warehouse = f"s3://{args.lake_bucket}/"

    spark = build_spark(warehouse)
    spark.sparkContext.setLogLevel("WARN")

    silver = to_silver(read_raw(spark, raw_path, series_key)).cache()
    rows = silver.count()
    print(f"parsed {rows:,} deduplicated bars from {raw_path}")

    if rows == 0:
        print("nothing to load — check the raw prefix", file=sys.stderr)
        return 1

    if args.dry_run:
        silver.orderBy(F.col("trade_date").desc()).show(10, truncate=False)
        return 0

    silver.createOrReplaceTempView("staged")

    # Same MERGE semantics as the Athena daily path, so a backfill and an
    # incremental run cannot disagree about what a row means. Re-running the
    # whole backfill is a no-op unless the source bytes changed.
    spark.sql(
        f"""
        MERGE INTO {CATALOG}.ai_sp500_silver.prices_daily t
        USING staged s
          ON t.symbol = s.symbol AND t.trade_date = s.trade_date
        WHEN MATCHED AND s.fetched_at > t.fetched_at THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
    )

    # Spark writes one file per shuffle partition; compact before handing the
    # table back to Athena.
    spark.sql(
        f"CALL {CATALOG}.system.rewrite_data_files("
        f"table => 'ai_sp500_silver.prices_daily', strategy => 'binpack')"
    )

    print(f"merged {rows:,} rows into silver.prices_daily")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
