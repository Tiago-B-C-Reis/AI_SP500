#!/usr/bin/env bash
# Apply Athena DDL files and prepared statements. Schemas are code — this script
# is the whole deployment mechanism; there are no Glue crawlers.
#
#   LAKE_BUCKET=my-bucket ./athena_apply.sh [--workgroup ai-sp500] [--maintain]
#
# DDL files (sql/athena/NN_*.sql): ';'-separated statements, ${LAKE_BUCKET}
# substituted, each statement submitted and awaited.
# Prepared statements (sql/athena/prepared/<name>.sql): update-or-create,
# statement name = filename.

set -euo pipefail

WORKGROUP="ai-sp500"
MAINTAIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workgroup) WORKGROUP="$2"; shift 2 ;;
    --maintain)  MAINTAIN=1;     shift   ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

: "${LAKE_BUCKET:?Set LAKE_BUCKET (the S3 lake bucket name)}"
SQL_DIR="$(cd "$(dirname "$0")/../../sql/athena" && pwd)"

run_statement() { # $1 = SQL text
  local qid state
  qid=$(aws athena start-query-execution \
          --work-group "$WORKGROUP" \
          --query-string "$1" \
          --query QueryExecutionId --output text)
  while :; do
    state=$(aws athena get-query-execution --query-execution-id "$qid" \
              --query QueryExecution.Status.State --output text)
    case "$state" in
      SUCCEEDED) return 0 ;;
      FAILED|CANCELLED)
        aws athena get-query-execution --query-execution-id "$qid" \
          --query QueryExecution.Status.StateChangeReason --output text >&2
        return 1 ;;
      *) sleep 2 ;;
    esac
  done
}

apply_ddl_file() { # $1 = path
  echo "== DDL: $(basename "$1")"
  local rendered stmt
  rendered=$(LAKE_BUCKET="$LAKE_BUCKET" envsubst '${LAKE_BUCKET}' < "$1")
  # Split on ';' — safe here because our DDL contains no string literals with ';'
  while IFS= read -r -d ';' stmt || [[ -n "$stmt" ]]; do
    # strip comments-only/blank fragments
    if grep -qvE '^\s*(--.*)?$' <<< "$stmt"; then
      run_statement "$stmt"
    fi
  done <<< "$rendered"
}

if [[ "$MAINTAIN" -eq 1 ]]; then
  apply_ddl_file "$SQL_DIR/50_maintenance.sql"
  exit 0
fi

for f in "$SQL_DIR"/[0-9]*_ddl.sql; do
  apply_ddl_file "$f"
done

for f in "$SQL_DIR"/prepared/*.sql; do
  name=$(basename "$f" .sql)
  echo "== prepared: $name"
  if ! aws athena update-prepared-statement --work-group "$WORKGROUP" \
        --statement-name "$name" --query-statement "file://$f" 2>/dev/null; then
    aws athena create-prepared-statement --work-group "$WORKGROUP" \
        --statement-name "$name" --query-statement "file://$f"
  fi
done

echo "done."
