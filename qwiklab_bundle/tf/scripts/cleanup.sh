#!/usr/bin/env bash
# ==============================================================================
# ネクストファイナンス（架空） Gemini Enterprise ハンズオン 全リソース削除スクリプト
# (setup.sh / finish_setup.sh で作成した全4データセット・4エージェント等を逆順で安全に削除)
# ==============================================================================
set -uo pipefail
export PATH="${HOME}/google-cloud-sdk/bin:/google/google-cloud-sdk/bin:${PATH}"

PROJECT_ID="${1:-$(gcloud config get-value project)}"
BUCKET_NAME="${2:-${PROJECT_ID}-next-finance-handson}"

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
TOKEN=$(gcloud auth print-access-token)

echo "=============================================================================="
echo " 🧹 Starting Cleanup of Hands-on Resources"
echo " Project ID     : ${PROJECT_ID}"
echo " Project Number : ${PROJECT_NUMBER}"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# 1. Delete Custom A2A Agents on Gemini Enterprise Engines
# ------------------------------------------------------------------------------
echo "[1/7] Deleting Custom A2A Agents on Gemini Enterprise..."
for ENG_ID in "next-finance-ge-app" "ntt-finance-ge-app" "agentspace-gws_1747225190602"; do
  curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/collections/default_collection/engines/${ENG_ID}/assistants/default_assistant/agents" > /tmp/cleanup_agents.json || true

  AGENT_NAMES=$(python3 -c '
import json
try:
    with open("/tmp/cleanup_agents.json") as f:
        data = json.load(f)
    for a in data.get("agents", []):
        dn = a.get("displayName", "")
        if a.get("name") and ("データ分析エージェント" in dn or "next_finance" in json.dumps(a)):
            print(a["name"])
except Exception:
    pass
')
  rm -f /tmp/cleanup_agents.json

  for AGENT_RESOURCE_NAME in ${AGENT_NAMES}; do
    echo "  -> Deleting A2A Agent on ${ENG_ID}: ${AGENT_RESOURCE_NAME}"
    curl -s -X DELETE \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "X-Goog-User-Project: ${PROJECT_ID}" \
      "https://discoveryengine.googleapis.com/v1alpha/${AGENT_RESOURCE_NAME}" >/dev/null || true
  done
done

# ------------------------------------------------------------------------------
# 2. Delete Discovery Engine OAuth Authorization
# ------------------------------------------------------------------------------
echo "[2/7] Deleting Discovery Engine OAuth Authorization (geminidataanalytics)..."
curl -s -X DELETE \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/authorizations/geminidataanalytics" >/dev/null || true

# ------------------------------------------------------------------------------
# 3. Delete BigQuery Conversational Analytics Data Agents
# ------------------------------------------------------------------------------
echo "[3/7] Deleting BigQuery Conversational Analytics Data Agents..."
for DA_ID in \
  "next_finance_3db_agent" \
  "next_finance_callcenter_agent" \
  "next_finance_hr_agent" \
  "next_finance_sales_agent" \
  "ntt_finance_3db_agent"; do
  echo "  -> Deleting Data Agent: ${DA_ID} (if exists)"
  curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://geminidataanalytics.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/global/dataAgents/${DA_ID}" >/dev/null || true
done

# ------------------------------------------------------------------------------
# 4. Delete Gemini Enterprise Engines (Hands-on Dedicated Apps Only)
# ------------------------------------------------------------------------------
echo "[4/7] Deleting Hands-on Gemini Enterprise Engines..."
for ENG_ID in "next-finance-ge-app" "ntt-finance-ge-app"; do
  echo "  -> Deleting Engine: ${ENG_ID} (if exists)"
  curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${ENG_ID}" >/dev/null || true
done

sleep 5

# ------------------------------------------------------------------------------
# 5. Delete Discovery Engine DataStores
# ------------------------------------------------------------------------------
echo "[5/7] Deleting Discovery Engine DataStores..."
for DS_ID in "next-finance-internal-docs" "ntt-finance-internal-docs" "gws-google-drive-ds" "gws-gmail-ds"; do
  echo "  -> Deleting DataStore: ${DS_ID} (if exists)"
  curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/${DS_ID}" >/dev/null || true
done

# ------------------------------------------------------------------------------
# 6. Delete BigQuery Datasets & Tables
# ------------------------------------------------------------------------------
echo "[6/7] Deleting BigQuery Datasets & Tables..."
for BQ_DS in \
  "next_finance_handson" \
  "next_finance_callcenter" \
  "next_finance_hr" \
  "next_finance_sales_mktg" \
  "ntt_finance_handson"; do
  echo "  -> Removing BigQuery dataset: ${PROJECT_ID}:${BQ_DS} (if exists)"
  bq rm -r -f -d "${PROJECT_ID}:${BQ_DS}" 2>/dev/null || true
done

# ------------------------------------------------------------------------------
# 7. Delete GCS Buckets & Objects
# ------------------------------------------------------------------------------
echo "[7/7] Deleting GCS Buckets & Objects..."
for BKT in "${BUCKET_NAME}" "${PROJECT_ID}-ntt-finance-handson"; do
  echo "  -> Removing GCS bucket: gs://${BKT} (if exists)"
  gsutil -m rm -r "gs://${BKT}" 2>/dev/null || true
done

rm -f /tmp/data_agent_payload*.json /tmp/register_a2a_agent*.json

echo ""
echo "=============================================================================="
echo " ✅ 全リソースの削除（クリーンアップ）が完了しました。"
echo "=============================================================================="
