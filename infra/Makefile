# AI_SP500 — lakehouse operations.
# Schemas are code: DDL and prepared statements live in sql/athena/ and are
# applied by scripts/athena_apply.sh. No Glue crawlers, ever.
#
# Requires: aws cli v2, envsubst (gettext).
#   make athena-apply LAKE_BUCKET=my-bucket

WORKGROUP   ?= ai-sp500
LAKE_BUCKET ?= $(error Set LAKE_BUCKET, e.g. `make athena-apply LAKE_BUCKET=my-bucket`)
export LAKE_BUCKET

.PHONY: athena-apply athena-maintain terraform-plan terraform-apply

athena-apply:      ## apply all DDL + prepared statements
	./scripts/athena_apply.sh --workgroup $(WORKGROUP)

athena-maintain:   ## weekly Iceberg OPTIMIZE + VACUUM (also wired to the Sunday machine)
	./scripts/athena_apply.sh --workgroup $(WORKGROUP) --maintain

terraform-plan:
	cd terraform && terraform init -upgrade && terraform plan

terraform-apply:
	cd terraform && terraform apply
