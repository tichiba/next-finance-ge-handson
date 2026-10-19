#!/usr/bin/env bash
# ==============================================================================
# ネクストファイナンス（架空） Gemini Enterprise ハンズオン自動構築スクリプト
# (全4ユースケース：財務与信 / コールセンターVOC / 人事タレント / 営業マーケROI 対応)
# ==============================================================================
set -uo pipefail
export PATH="${HOME}/google-cloud-sdk/bin:/google/google-cloud-sdk/bin:${PATH}"

PROJECT_ID="${1:-$(gcloud config get-value project)}"
REGION="${2:-us-central1}"
ZONE="${3:-us-central1-a}"
PRIMARY_USER="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$(cd "${SCRIPT_DIR}/../data" && pwd)"
BUCKET_NAME="${PROJECT_ID}-next-finance-handson"

echo "[INFO] Starting automated provisioning for Project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# ------------------------------------------------------------------------------
# 1. Enable Required Google Cloud APIs
# ------------------------------------------------------------------------------
echo "[STEP 1] Enabling required Google Cloud APIs..."
gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com \
  discoveryengine.googleapis.com \
  geminidataanalytics.googleapis.com \
  cloudaicompanion.googleapis.com \
  dataplex.googleapis.com \
  aiplatform.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com --project="${PROJECT_ID}"

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
echo "[INFO] Project Number: ${PROJECT_NUMBER}"

# ------------------------------------------------------------------------------
# 2. Create GCS Bucket & Upload Scenario Assets & Helper Scripts
# ------------------------------------------------------------------------------
echo "[STEP 2] Creating GCS Bucket gs://${BUCKET_NAME} and uploading assets..."
gsutil mb -p "${PROJECT_ID}" -l US "gs://${BUCKET_NAME}" 2>/dev/null || true

gsutil -m cp "${DATA_DIR}/scenario1/"*.pdf "gs://${BUCKET_NAME}/scenario1/"
gsutil -m cp "${DATA_DIR}/scenario2/"*.pdf "gs://${BUCKET_NAME}/scenario2/"
gsutil -m cp "${DATA_DIR}/scenario3/"* "gs://${BUCKET_NAME}/scenario3/"
gsutil -m cp "${DATA_DIR}/scenario4_callcenter/"* "gs://${BUCKET_NAME}/scenario4_callcenter/"
gsutil -m cp "${DATA_DIR}/scenario5_hr/"* "gs://${BUCKET_NAME}/scenario5_hr/"
gsutil -m cp "${DATA_DIR}/scenario6_sales_mktg/"* "gs://${BUCKET_NAME}/scenario6_sales_mktg/"
gsutil cp "${SCRIPT_DIR}/finish_setup.sh" "gs://${BUCKET_NAME}/scripts/finish_setup.sh"
if [ -f "${SCRIPT_DIR}/cleanup.sh" ]; then
  gsutil cp "${SCRIPT_DIR}/cleanup.sh" "gs://${BUCKET_NAME}/scripts/cleanup.sh"
fi

# Allow students in the project to download Scenario 1 PDFs easily
gsutil iam ch allAuthenticatedUsers:objectViewer "gs://${BUCKET_NAME}" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Create 4 BigQuery Datasets & Load 12 Tables (with Japanese Column Descriptions)
# ------------------------------------------------------------------------------
echo "[STEP 3-1] Creating BigQuery dataset next_finance_handson (請求・入金・与信)..."
bq --location=US mk -d \
  --description="ネクストファイナンス（ハンズオン用①）：請求・入金・顧客与信3DB（2026年4月〜9月）" \
  "${PROJECT_ID}:next_finance_handson" 2>/dev/null || true

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_handson.customer_credit" \
  "${DATA_DIR}/scenario3/bq_customer_credit.csv" \
  "${DATA_DIR}/scenario3/schema_customer_credit.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_handson.invoices" \
  "${DATA_DIR}/scenario3/bq_invoices.csv" \
  "${DATA_DIR}/scenario3/schema_invoices.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_handson.payments" \
  "${DATA_DIR}/scenario3/bq_payments.csv" \
  "${DATA_DIR}/scenario3/schema_payments.json"

echo "[STEP 3-2] Creating BigQuery dataset next_finance_callcenter (コールセンター・VOC分析)..."
bq --location=US mk -d \
  --description="ネクストファイナンス（ハンズオン用②）：コールセンター入電ログ・オペレーター・CSATアンケート3DB" \
  "${PROJECT_ID}:next_finance_callcenter" 2>/dev/null || true

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_callcenter.operators" \
  "${DATA_DIR}/scenario4_callcenter/bq_operators.csv" \
  "${DATA_DIR}/scenario4_callcenter/schema_operators.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_callcenter.call_logs" \
  "${DATA_DIR}/scenario4_callcenter/bq_call_logs.csv" \
  "${DATA_DIR}/scenario4_callcenter/schema_call_logs.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_callcenter.csat_surveys" \
  "${DATA_DIR}/scenario4_callcenter/bq_csat_surveys.csv" \
  "${DATA_DIR}/scenario4_callcenter/schema_csat_surveys.json"

echo "[STEP 3-3] Creating BigQuery dataset next_finance_hr (人事・働き方＆タレント分析)..."
bq --location=US mk -d \
  --description="ネクストファイナンス（ハンズオン用③）：社員マスタ・月次勤怠・エンゲージメントサーベイ3DB" \
  "${PROJECT_ID}:next_finance_hr" 2>/dev/null || true

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_hr.employees" \
  "${DATA_DIR}/scenario5_hr/bq_employees.csv" \
  "${DATA_DIR}/scenario5_hr/schema_employees.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_hr.attendance_monthly" \
  "${DATA_DIR}/scenario5_hr/bq_attendance_monthly.csv" \
  "${DATA_DIR}/scenario5_hr/schema_attendance_monthly.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_hr.engagement_surveys" \
  "${DATA_DIR}/scenario5_hr/bq_engagement_surveys.csv" \
  "${DATA_DIR}/scenario5_hr/schema_engagement_surveys.json"

echo "[STEP 3-4] Creating BigQuery dataset next_finance_sales_mktg (営業パイプライン・マーケROI分析)..."
bq --location=US mk -d \
  --description="ネクストファイナンス（ハンズオン用④）：マーケティング施策・見込み客リード・商談パイプライン3DB" \
  "${PROJECT_ID}:next_finance_sales_mktg" 2>/dev/null || true

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_sales_mktg.marketing_campaigns" \
  "${DATA_DIR}/scenario6_sales_mktg/bq_marketing_campaigns.csv" \
  "${DATA_DIR}/scenario6_sales_mktg/schema_marketing_campaigns.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_sales_mktg.leads_activities" \
  "${DATA_DIR}/scenario6_sales_mktg/bq_leads_activities.csv" \
  "${DATA_DIR}/scenario6_sales_mktg/schema_leads_activities.json"

bq load --replace --source_format=CSV --skip_leading_rows=1 \
  "${PROJECT_ID}:next_finance_sales_mktg.sales_opportunities" \
  "${DATA_DIR}/scenario6_sales_mktg/bq_sales_opportunities.csv" \
  "${DATA_DIR}/scenario6_sales_mktg/schema_sales_opportunities.json"

# ------------------------------------------------------------------------------
# 4. Run Discovery Engine / Gemini Enterprise / 4 BigQuery Data Agents Setup
# ------------------------------------------------------------------------------
echo "[STEP 4] Running Gemini Enterprise (gemini-3.8-flash) & 4 Custom A2A Agents setup..."
bash "${SCRIPT_DIR}/finish_setup.sh" "${PROJECT_ID}" "${BUCKET_NAME}" || true

echo "[INFO] Startup provisioning script finished for ${PROJECT_ID}."
