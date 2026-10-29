#!/usr/bin/env bash
# ==============================================================================
# ネクストファイナンス（架空） Gemini Enterprise / 4種 A2A データ分析エージェント構成スクリプト
# (Qwiklabs 起動時自動実行 ＆ ファシリテーター用 Cloud Shell / Argolis 実行兼用)
# ==============================================================================
set -uo pipefail
export PATH="${HOME}/google-cloud-sdk/bin:/google/google-cloud-sdk/bin:${PATH}"

PROJECT_ID="${1:-$(gcloud config get-value project)}"
BUCKET_NAME="${2:-${PROJECT_ID}-next-finance-handson}"
ENGINE_ID="next-finance-ge-app"
DATASTORE_ID="next-finance-internal-docs"
MODEL_ID="gemini-3.8-flash"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
TOKEN=$(gcloud auth print-access-token)

echo "=============================================================================="
echo " Project ID     : ${PROJECT_ID}"
echo " Project Number : ${PROJECT_NUMBER}"
echo " GCS Bucket     : gs://${BUCKET_NAME}"
echo " Default Model  : ${MODEL_ID}"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# 1. Discovery Engine Provisioning & License Auto-Registration
# ------------------------------------------------------------------------------
echo "[1/6] Provisioning Discovery Engine & Trial LicenseConfig..."
curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}:provision" \
  -d '{
    "acceptDataUseTerms": true,
    "dataUseTermsVersion": "2022-11-23"
  }' >/dev/null || true

curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/licenseConfigs" \
  -d '{
    "subscriptionTier": "SUBSCRIPTION_TIER_SEARCH_AND_ASSISTANT",
    "freeTrial": true,
    "licenseCount": 50
  }' >/dev/null || true

curl -s -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/userStores/default_user_store?updateMask=enableLicenseAutoRegister,enableExpiredLicenseAutoUpdate" \
  -d '{
    "enableLicenseAutoRegister": true,
    "enableExpiredLicenseAutoUpdate": true
  }' >/dev/null || true

# ID プロバイダ（aclConfig.idpConfig.idpType）を Google Identity (GSUITE) に設定する。
# Gmail / Google Chat コネクタは aclEnabled=true が必須で、IdP 未設定のまま作成すると
# FAILED_PRECONDITION "IdP must be selected before creating an ACLed Data Connector." で拒否される。
# provision は非同期 LRO のため、Customer 行が作成されるまで最大 60 秒リトライする。
ACL_URL="https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/aclConfig"
IDP_TYPE=""
for _i in $(seq 1 12); do
  IDP_TYPE=$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" "${ACL_URL}" \
    | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("idpConfig", {}).get("idpType", ""))
except Exception:
    print("")' || true)
  if [ "${IDP_TYPE}" = "GSUITE" ]; then
    break
  fi
  ACL_RESP=$(curl -s -w '\n%{http_code}' -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "${ACL_URL}" \
    -d '{"idpConfig": {"idpType": "GSUITE"}}' || true)
  ACL_CODE=$(echo "${ACL_RESP}" | tail -n1)
  if [ "${ACL_CODE}" = "200" ]; then
    IDP_TYPE="GSUITE"
    break
  fi
  echo "  [WAIT] aclConfig 更新待機中 (HTTP ${ACL_CODE}, ${_i}/12): $(echo "${ACL_RESP}" | sed '$d' | tr -d '\n' | cut -c1-200)"
  sleep 5
done
if [ "${IDP_TYPE}" = "GSUITE" ]; then
  echo "  [OK] Identity Provider = Google Identity (GSUITE)"
else
  echo "  [ERROR] Identity Provider を GSUITE に設定できませんでした（現在値: '${IDP_TYPE:-未設定}'）。"
  echo "          Gmail / Google Chat コネクタが作成できないため、Cloud Console > Gemini Enterprise > 設定 > 認証 で"
  echo "          「Google Identity」を選択後、本スクリプトを再実行してください。"
fi

# ------------------------------------------------------------------------------
# 2. Seed Gmail / Google Chat Real Messages & Import Internal Policy PDF to GCS DataStore
# ------------------------------------------------------------------------------
echo "[2/6] Seeding Gmail / Google Chat Real Data & Creating Internal Policy DataStore (${DATASTORE_ID})..."

GWS_TOKEN="${GWS_ACCESS_TOKEN:-}"
if [ -z "${GWS_TOKEN}" ]; then
  ADC_TOK=$(gcloud auth application-default print-access-token 2>/dev/null || true)
  for CANDIDATE_TOK in "${ADC_TOK}" "${TOKEN}"; do
    if [ -n "${CANDIDATE_TOK}" ]; then
      SCOPE_INFO=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=${CANDIDATE_TOK}" || true)
      if echo "${SCOPE_INFO}" | grep -q "gmail" && echo "${SCOPE_INFO}" | grep -q "chat"; then
        GWS_TOKEN="${CANDIDATE_TOK}"
        break
      fi
    fi
  done
fi

if [ -z "${GWS_TOKEN}" ] && [ -t 0 ] && [ -z "${SKIP_GWS_OAUTH:-}" ]; then
  echo "  ============================================================================"
  echo "  🔑 [Gmail / Google Chat 実データ投入用 OAuth 認可 (初回1回のみ)]"
  echo "     全受講者アカウントへ「東都ロジスティクス相談メール」と「審査部Chat議論」を"
  echo "     実データとして自動配信するため、以下の URL を開いて承認コードを入力してください。"
  echo "  ============================================================================"
  gcloud auth application-default login \
    --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/gmail.send,https://www.googleapis.com/auth/gmail.modify,https://www.googleapis.com/auth/gmail.insert,https://www.googleapis.com/auth/chat.spaces,https://www.googleapis.com/auth/chat.memberships,https://www.googleapis.com/auth/chat.messages,https://www.googleapis.com/auth/drive.file" \
    --no-launch-browser || {
    echo "  [INFO] Google Chat スコープが制限されている環境のため、Gmail スコープで再試行します..."
    gcloud auth application-default login \
      --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/gmail.send,https://www.googleapis.com/auth/gmail.modify,https://www.googleapis.com/auth/gmail.insert,https://www.googleapis.com/auth/drive.file" \
      --no-launch-browser || true
  }
  gcloud auth application-default set-quota-project "${PROJECT_ID}" --quiet >/dev/null 2>&1 || true
  GWS_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null || echo "${TOKEN}")
fi

rm -f /tmp/gws_seed_status.json
if [ -f "${SCRIPT_DIR}/seed_gws_data.py" ] && [ -n "${GWS_TOKEN}" ]; then
  python3 "${SCRIPT_DIR}/seed_gws_data.py" \
    --project-id "${PROJECT_ID}" \
    --token "${GWS_TOKEN}" \
    --json-output /tmp/gws_seed_status.json || true
fi

GMAIL_SEEDED=$(python3 -c '
import json
try:
    d = json.load(open("/tmp/gws_seed_status.json"))
    print("true" if d.get("gmail_seeded") else "false")
except Exception:
    print("false")
')
CHAT_SEEDED=$(python3 -c '
import json
try:
    d = json.load(open("/tmp/gws_seed_status.json"))
    print("true" if d.get("chat_seeded") else "false")
except Exception:
    print("false")
')

curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?dataStoreId=${DATASTORE_ID}" \
  -d '{
    "displayName": "ネクストファイナンス 社内規程（通信料金等債権管理および与信運用規程）",
    "industryVertical": "GENERIC",
    "solutionTypes": ["SOLUTION_TYPE_SEARCH"],
    "contentConfig": "CONTENT_REQUIRED",
    "documentProcessingConfig": {
      "defaultParsingConfig": {
        "digitalParsingConfig": {}
      }
    }
  }' >/dev/null || true

curl -s -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/${DATASTORE_ID}?updateMask=displayName" \
  -d '{
    "displayName": "ネクストファイナンス 社内規程（通信料金等債権管理および与信運用規程）"
  }' >/dev/null || true

sleep 2

# Qwiklabs の qwiklabs.net ユーザー間では Gmail が配送されないため（GMAIL_SEEDED=true でも受信されない）、
# 営業部からの相談メールは「メール記録 PDF」として常に社内文書データストアへ取り込む。
# Google Chat の実データがある場合はコネクタ経由で参照するため、メール＋チャットのアーカイブ PDF は取り込まない。
# （FULL 同期のため、取り込み対象に含めなかった過去のドキュメントはデータストアから削除される）
POLICY_PDF_URI="gs://${BUCKET_NAME}/scenario2/next_finance_credit_policy.pdf"
EMAIL_PDF_URI="gs://${BUCKET_NAME}/scenario2/next_finance_sales_email_toto_logistics.pdf"
ARCHIVE_PDF_URI="gs://${BUCKET_NAME}/scenario2/next_finance_email_chat_archive.pdf"
if [ "${CHAT_SEEDED}" = "true" ] || [ "${FORCE_POLICY_ONLY:-}" = "1" ]; then
  SCENARIO2_URIS="\"${POLICY_PDF_URI}\", \"${EMAIL_PDF_URI}\""
  echo "  -> Importing Credit Policy PDF + Sales Email record PDF into ${DATASTORE_ID} (Gmail seeded=${GMAIL_SEEDED}, Chat seeded=${CHAT_SEEDED})..."
else
  SCENARIO2_URIS="\"${POLICY_PDF_URI}\", \"${EMAIL_PDF_URI}\", \"${ARCHIVE_PDF_URI}\""
  echo "  -> [Fallback] Chat not seeded (${CHAT_SEEDED}); importing Credit Policy + Sales Email + Email/Chat archive PDFs into ${DATASTORE_ID}..."
fi
curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/${DATASTORE_ID}/branches/0/documents:import" \
  -d "{
    \"gcsSource\": {
      \"inputUris\": [${SCENARIO2_URIS}],
      \"dataSchema\": \"content\"
    },
    \"reconciliationMode\": \"FULL\"
  }" >/dev/null || true

# ------------------------------------------------------------------------------
# 3. Register Google Workspace Connectors & DataStores (Gmail & Google Chat)
# ------------------------------------------------------------------------------
echo "[3/6] Registering Google Workspace Federated Connectors (Gmail & Google Chat)..."

# Remove legacy Google Drive datastore if present so only Gmail, Google Chat, and Internal Policy PDF are used
curl -s -X DELETE \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/gws-google-drive-ds" >/dev/null 2>&1 || true

# Discovery Engine API を呼び、HTTP ステータスとエラー内容を表示する（失敗を握りつぶさない）。
# 使い方: de_call <ラベル> <METHOD> <URL> <JSON本文>
de_call() {
  local label="$1" method="$2" url="$3" body="$4" resp code msg
  resp=$(curl -s -w '\n%{http_code}' -X "${method}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "${url}" -d "${body}" || true)
  code=$(echo "${resp}" | tail -n1)
  msg=$(echo "${resp}" | sed '$d' | python3 -c 'import json,sys
try:
    e = json.load(sys.stdin).get("error", {})
    print(str(e.get("status", "")) + ": " + str(e.get("message", "")) if e else "")
except Exception:
    print("")' 2>/dev/null || true)
  case "${code}" in
    200) echo "  [OK] ${label}" ;;
    409) echo "  [OK] ${label}（作成済み）" ;;
    *)   echo "  [ERROR] ${label} 失敗 (HTTP ${code}) ${msg}" ;;
  esac
}

# default_collection に Gmail / Chat の DataStore が存在するか判定する（引数: GOOGLE_MAIL / GOOGLE_CHAT）
ws_ds_exists() {
  curl -s -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?pageSize=100" \
    | python3 -c 'import json,sys
t = sys.argv[1]
try:
    for d in json.load(sys.stdin).get("dataStores", []):
        i = d.get("name", "").split("/")[-1]
        if d.get("workspaceConfig", {}).get("type") == t or t.lower() in i:
            sys.exit(0)
except Exception:
    pass
sys.exit(1)' "$1"
}

# 3a. Set up V2 DataConnectors for Gmail (google_mail) and Google Chat (google_chat)
#     ※ aclEnabled=true のため、[1/6] で IdP = GSUITE が設定済みであることが前提
de_call "Gmail コネクタ作成 (setUpDataConnector: gws-gmail-connector)" POST \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global:setUpDataConnector" \
  '{
    "collectionId": "gws-gmail-connector",
    "collectionDisplayName": "Gmail (GWS 横断検索)",
    "dataConnector": {
      "dataSource": "google_mail",
      "entities": [{"entityName": "google_mail"}],
      "connectorModes": ["FEDERATED"],
      "aclEnabled": true
    }
  }'

de_call "Google Chat コネクタ作成 (setUpDataConnector: gws-gchat-connector)" POST \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global:setUpDataConnector" \
  '{
    "collectionId": "gws-gchat-connector",
    "collectionDisplayName": "Google Chat (GWS 横断検索)",
    "dataConnector": {
      "dataSource": "google_chat",
      "entities": [{"entityName": "google_chat"}],
      "connectorModes": ["FEDERATED"],
      "aclEnabled": true
    }
  }'

# setUpDataConnector は DataStore を非同期に作成するため、最大 60 秒ポーリングで待つ
# （待たずにフォールバックを作ると Gmail / Chat の DataStore が重複するため）
for _i in $(seq 1 12); do
  if ws_ds_exists GOOGLE_MAIL && ws_ds_exists GOOGLE_CHAT; then
    break
  fi
  sleep 5
done

# 3b. Ensure Workspace DataStores exist in default_collection for both GOOGLE_MAIL and GOOGLE_CHAT
NEED_FALLBACK_DS=$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?pageSize=100" \
  | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    has_mail = False
    has_chat = False
    has_conn_mail = False
    has_conn_chat = False
    for d in data.get('dataStores', []):
        ds_id = d.get('name', '').split('/')[-1]
        w_type = d.get('workspaceConfig', {}).get('type', '')
        c_type = d.get('connectorConfig', {}).get('connectorType', '')
        if w_type == 'GOOGLE_MAIL' or c_type == 'GOOGLE_MAIL' or 'google_mail' in ds_id:
            has_mail = True
            if d.get('connectorName') or 'gws-gmail-connector' in ds_id:
                has_conn_mail = True
        if w_type == 'GOOGLE_CHAT' or c_type == 'GOOGLE_CHAT' or 'google_chat' in ds_id:
            has_chat = True
            if d.get('connectorName') or 'gws-gchat-connector' in ds_id:
                has_conn_chat = True
    out = []
    if not has_mail:
        out.append('CREATE_MAIL')
    elif has_conn_mail:
        out.append('CLEAN_LEGACY_MAIL')
    if not has_chat:
        out.append('CREATE_CHAT')
    elif has_conn_chat:
        out.append('CLEAN_LEGACY_CHAT')
    print(' '.join(out))
except Exception:
    print('CREATE_MAIL CREATE_CHAT')
")

if [[ "${NEED_FALLBACK_DS}" == *"CLEAN_LEGACY_MAIL"* ]]; then
  curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/gws-gmail-ds" >/dev/null 2>&1 || true
fi

if [[ "${NEED_FALLBACK_DS}" == *"CLEAN_LEGACY_CHAT"* ]]; then
  curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/gws-gchat-ds" >/dev/null 2>&1 || true
fi

if [[ "${NEED_FALLBACK_DS}" == *"CREATE_MAIL"* ]] && ! ws_ds_exists GOOGLE_MAIL; then
  de_call "Gmail DataStore 作成 (フォールバック: gws-gmail-ds)" POST \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?dataStoreId=gws-gmail-ds" \
    '{
      "displayName": "Gmail (GWS 横断検索)",
      "industryVertical": "GENERIC",
      "solutionTypes": ["SOLUTION_TYPE_SEARCH"],
      "contentConfig": "GOOGLE_WORKSPACE",
      "aclEnabled": true,
      "workspaceConfig": {"type": "GOOGLE_MAIL"}
    }'
fi

if [[ "${NEED_FALLBACK_DS}" == *"CREATE_CHAT"* ]] && ! ws_ds_exists GOOGLE_CHAT; then
  de_call "Google Chat DataStore 作成 (フォールバック: gws-gchat-ds)" POST \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?dataStoreId=gws-gchat-ds" \
    '{
      "displayName": "Google Chat (GWS 横断検索)",
      "industryVertical": "GENERIC",
      "solutionTypes": ["SOLUTION_TYPE_SEARCH"],
      "contentConfig": "GOOGLE_WORKSPACE",
      "aclEnabled": true,
      "workspaceConfig": {"type": "GOOGLE_CHAT"}
    }'
fi

sleep 2

# Engine に紐付ける DataStore 一覧を作成（JSON は標準入力で渡し、パース失敗による誤った ID 混入を防ぐ）
DS_ARRAY=$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?pageSize=100" \
  | python3 -c 'import json,sys
base = sys.argv[1]
try:
    ids = [d["name"].split("/")[-1] for d in json.load(sys.stdin).get("dataStores", [])]
except Exception:
    ids = []
ids = [i for i in ids if i != "gws-google-drive-ds"]
if base not in ids:
    ids.insert(0, base)
print(json.dumps(ids))' "${DATASTORE_ID}")

if ws_ds_exists GOOGLE_MAIL; then echo "  [OK] Gmail DataStore: 作成済み"; else echo "  [ERROR] Gmail DataStore が存在しません（上記エラーを確認してください）"; fi
if ws_ds_exists GOOGLE_CHAT; then echo "  [OK] Google Chat DataStore: 作成済み"; else echo "  [ERROR] Google Chat DataStore が存在しません（上記エラーを確認してください）"; fi
echo "  -> Linked DataStores for Engine (${ENGINE_ID}): ${DS_ARRAY}"

# ------------------------------------------------------------------------------
# 4. Create Gemini Enterprise (Agentspace) Engine & Configure Features / Models
#    - Gemini 4 Argon (gemini-4-argon) + gemini-3.8-flash
#    - 音声入力 (speech-to-text, bi-directional-audio)
#    - キャンバス (canvas: ON, disable-canvas: OFF, canvas-workspace: ON, canvas-app-builder: ON)
#    - モデルセレクタ (model-selector: ON)
# ------------------------------------------------------------------------------
echo "[4/6] Creating/Updating Gemini Enterprise Engine (${ENGINE_ID}) with Features & Models (gemini-4-argon / speech-to-text / canvas / model-selector)..."
ENGINE_URL="https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${ENGINE_ID}"
ENG_TMP=$(mktemp -d)

# 有効化する機能・モデル（POST 作成時と PATCH 更新時で共通）
cat > "${ENG_TMP}/features.json" <<'JSONEOF'
{
  "model-selector": "FEATURE_STATE_ON",
  "speech-to-text": "FEATURE_STATE_ON",
  "bi-directional-audio": "FEATURE_STATE_ON",
  "canvas": "FEATURE_STATE_ON",
  "disable-canvas": "FEATURE_STATE_OFF",
  "canvas-workspace": "FEATURE_STATE_ON",
  "canvas-app-builder": "FEATURE_STATE_ON",
  "agent-gallery": "FEATURE_STATE_ON",
  "prompt-gallery": "FEATURE_STATE_ON",
  "notebook-lm": "FEATURE_STATE_ON",
  "image-generation": "FEATURE_STATE_ON",
  "video-generation": "FEATURE_STATE_ON",
  "talk-to-content": "FEATURE_STATE_ON",
  "google-drive-upload": "FEATURE_STATE_ON",
  "agent-sharing": "FEATURE_STATE_ON"
}
JSONEOF
cat > "${ENG_TMP}/models.json" <<'JSONEOF'
{
  "gemini-4-argon": "MODEL_ENABLED",
  "gemini-3.8-flash": "MODEL_ENABLED",
  "gemini-3.6-flash": "MODEL_ENABLED",
  "gemini-3.5-flash": "MODEL_ENABLED",
  "gemini-3.1-pro-preview": "MODEL_ENABLED",
  "gemini-2.5-pro": "MODEL_ENABLED",
  "gemini-2.5-flash": "MODEL_ENABLED"
}
JSONEOF

# 4a. Engine 新規作成（作成時に 3 データストアを指定する）
#     ※ SOLUTION_TYPE_SEARCH の Engine は「データストア 1 つで作成」されると、後から API で
#       データストアを追加できない（FAILED_PRECONDITION）。そのため作成時に全データストアを渡す。
python3 - "${ENG_TMP}" "${DS_ARRAY}" > "${ENG_TMP}/create.json" <<'PYEOF'
import json, sys
d = sys.argv[1]
print(json.dumps({
    "displayName": "ネクストファイナンス Gemini Enterprise ハンズオン",
    "industryVertical": "GENERIC",
    "solutionType": "SOLUTION_TYPE_SEARCH",
    "appType": "APP_TYPE_INTRANET",
    "dataStoreIds": json.loads(sys.argv[2]),
    "searchEngineConfig": {"searchTier": "SEARCH_TIER_ENTERPRISE", "searchAddOns": ["SEARCH_ADD_ON_LLM"]},
    "commonConfig": {"companyName": "ネクストファイナンス株式会社"},
    "features": json.load(open(f"{d}/features.json")),
    "modelConfigs": json.load(open(f"{d}/models.json")),
}, ensure_ascii=False))
PYEOF
de_call "Engine 作成 (${ENGINE_ID})" POST \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines?engineId=${ENGINE_ID}" \
  "$(cat "${ENG_TMP}/create.json")"

# Engine 作成は非同期 (LRO) のため、取得できるまで最大 60 秒待つ
for _i in $(seq 1 12); do
  if curl -s -f -o "${ENG_TMP}/engine.json" -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" "${ENGINE_URL}"; then
    break
  fi
  sleep 5
done

# 4b. 機能・モデルの有効化（dataStoreIds とは別の PATCH にし、片方の失敗に巻き込まれないようにする）
python3 - "${ENG_TMP}" > "${ENG_TMP}/patch_features.json" <<'PYEOF'
import json, sys
d = sys.argv[1]
try:
    eng = json.load(open(f"{d}/engine.json"))
except Exception:
    eng = {}
features = eng.get("features", {}) or {}
features.update(json.load(open(f"{d}/features.json")))
models = eng.get("modelConfigs", {}) or {}
models.update(json.load(open(f"{d}/models.json")))
print(json.dumps({"features": features, "modelConfigs": models}, ensure_ascii=False))
PYEOF
curl -s -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "${ENGINE_URL}?updateMask=features,modelConfigs" \
  -d @"${ENG_TMP}/patch_features.json" > "${ENG_TMP}/patch_features_resp.json" || true
python3 - "${ENG_TMP}/patch_features_resp.json" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
if "error" in d or "features" not in d:
    e = d.get("error", {})
    print(f"  [ERROR] Engine 機能・モデル更新 失敗 (HTTP {e.get('code', '-')}) {e.get('status', '')}: {e.get('message', 'Engine が取得できません（上記の Engine 作成エラーを確認してください）')}")
else:
    f = d.get("features", {})
    m = d.get("modelConfigs", {})
    print(f"  [OK] Engine features enabled : model-selector={f.get('model-selector')}, speech-to-text={f.get('speech-to-text')}, canvas={f.get('canvas')} (disable-canvas={f.get('disable-canvas')})")
    print(f"  [OK] Engine models enabled   : gemini-4-argon={m.get('gemini-4-argon')}, gemini-3.8-flash={m.get('gemini-3.8-flash')}")
PYEOF

# 4c. 既存 Engine にデータストアが不足している場合のみ追加（削除はしない）
curl -s -o "${ENG_TMP}/engine.json" -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" "${ENGINE_URL}" || true
DS_MERGED=$(python3 - "${ENG_TMP}/engine.json" "${DS_ARRAY}" <<'PYEOF'
import json, sys
try:
    cur = json.load(open(sys.argv[1])).get("dataStoreIds", []) or []
except Exception:
    cur = []
want = json.loads(sys.argv[2])
missing = [i for i in want if i not in cur]
print(json.dumps(cur + missing) if missing else "")
PYEOF
)
if [ -n "${DS_MERGED}" ]; then
  de_call "Engine へのデータストア追加 (${DS_MERGED})" PATCH \
    "${ENGINE_URL}?updateMask=dataStoreIds" \
    "{\"dataStoreIds\": ${DS_MERGED}}"
  curl -s -o "${ENG_TMP}/engine.json" -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" "${ENGINE_URL}" || true
fi

# 4d. Engine に実際に接続されているデータストアを検証
LINKED_DS=$(python3 -c 'import json,sys
try:
    print(json.dumps(json.load(open(sys.argv[1])).get("dataStoreIds", [])))
except Exception:
    print("[]")' "${ENG_TMP}/engine.json")
echo "  -> Engine (${ENGINE_ID}) に実際に接続されているデータストア: ${LINKED_DS}"
LINK_CHECK=$(python3 -c 'import json,sys
ids = json.loads(sys.argv[1])
miss = []
if not any("google_mail" in i or i == "gws-gmail-ds" for i in ids): miss.append("Gmail")
if not any("google_chat" in i or i == "gws-gchat-ds" for i in ids): miss.append("Google Chat")
print(" / ".join(miss))' "${LINKED_DS}")
if [ -z "${LINK_CHECK}" ]; then
  echo "  [OK] Gmail / Google Chat データストアが Engine に接続されています"
else
  echo "  [ERROR] ${LINK_CHECK} のデータストアが Engine に接続されていません。"
  echo "          Console 管理画面 > ［接続されたデータストア］>［新しいデータストアを追加］から手動で追加してください:"
  echo "          https://console.cloud.google.com/ai/agentspace/locations/global/engines/${ENGINE_ID}/overview?project=${PROJECT_ID}"
fi
rm -rf "${ENG_TMP}"

# Explicitly set generativeAnswerConfig.modelVersion on the Engine WidgetConfig
curl -s -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${ENGINE_ID}/widgetConfigs/default_search_widget_config?updateMask=uiSettings.generativeAnswerConfig.modelVersion" \
  -d "{
    \"uiSettings\": {
      \"generativeAnswerConfig\": {
        \"modelVersion\": \"${MODEL_ID}\"
      }
    }
  }" >/dev/null || true

# Enable Web Grounding (Google Search) on default_assistant so Canvas slides can use web images
de_call "Assistant Web Grounding 有効化 (${ENGINE_ID}/assistants/default_assistant)" PATCH \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${ENGINE_ID}/assistants/default_assistant?updateMask=webGroundingType,defaultWebGroundingToggleOff" \
  '{
    "webGroundingType": "WEB_GROUNDING_TYPE_GOOGLE_SEARCH",
    "defaultWebGroundingToggleOff": false
  }'

# ------------------------------------------------------------------------------
# 5. Create & Publish 4 BigQuery Conversational Analytics Data Agents
#    (with Concise 9-10 char DisplayNames, Japanese Column Descriptions & Golden SQL)
# ------------------------------------------------------------------------------
echo "[5/6] Creating & Publishing 4 BigQuery Conversational Analytics Data Agents..."

STUDENT_MEMBERS=$(gcloud projects get-iam-policy "${PROJECT_ID}" --format=json | python3 -c "
import json, sys
policy = json.load(sys.stdin)
members = set()
for b in policy.get('bindings', []):
    for m in b.get('members', []):
        if m.startswith('user:'):
            members.add(m)
members.add('serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-discoveryengine.iam.gserviceaccount.com')
print(json.dumps(sorted(list(members))))
")

# Ensure all 11 lab accounts (user00 [User 1] + user01..user10 [User 2..User 11]) have required IAM roles
USER_PRINCIPALS=$(gcloud projects get-iam-policy "${PROJECT_ID}" --format=json | python3 -c "
import json, sys
policy = json.load(sys.stdin)
users = sorted({m for b in policy.get('bindings', []) for m in b.get('members', []) if m.startswith('user:')})
print(' '.join(users))
")
for U_MEMBER in ${USER_PRINCIPALS}; do
  for ROLE in \
    "roles/bigquery.admin" \
    "roles/discoveryengine.admin" \
    "roles/geminidataanalytics.dataAgentOwner" \
    "roles/geminidataanalytics.dataAgentUser" \
    "roles/storage.admin"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="${U_MEMBER}" \
      --role="${ROLE}" \
      --quiet >/dev/null 2>&1 || true
  done
done

python3 - "${PROJECT_ID}" "${MODEL_ID}" "${TOKEN}" <<'PYEOF'
import json, sys, urllib.request

project_id = sys.argv[1]
model_id = sys.argv[2]
token = sys.argv[3]

# Complete Japanese schema definitions (table description + column descriptions with short Japanese labels)
TABLE_SCHEMAS = {
    "customer_credit": {
        "description": "顧客与信マスタ：法人150社・個人850件の契約回線数、社内与信ランク(A/B/C1/C2)、与信限度額、直近6ヶ月遅延回数、延滞管理ステータスを管理",
        "fields": [
            {"name": "customer_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：契約者ID】主キー（CUST-xxxxは法人多回線一括請求契約者、INDV-xxxxxは個人回線契約者）"},
            {"name": "customer_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：契約者名】取引先企業名または個人契約者名（例：東都ロジスティクス株式会社）"},
            {"name": "subscriber_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：契約区分】'個人_回線契約者'（850件）または '法人_多回線一括請求'（150社）"},
            {"name": "industry_or_segment", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：業種セグメント】法人の業種または個人の利用セグメント"},
            {"name": "contracted_lines_count", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：契約回線数】光回線・モバイル・車載IoT回線等の合計契約回線数（回線）"},
            {"name": "credit_rank", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：与信ランク】社内与信ランク（A:優良、B:標準、C1:要注意_遅延履歴あり、C2:警戒_督促・制限対象）"},
            {"name": "credit_limit_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：与信限度額_円】月間与信限度額・電話料金合算利用上限額（円）"},
            {"name": "overdue_status_flag", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：延滞ステータス】延滞管理ステータス（正常、要注意_遅延履歴あり、支払猶予相談中、督促中_合算枠制限対象 等）"},
            {"name": "delayed_count_last_6m", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：直近6ヶ月遅延回数】直近6ヶ月以内の口座振替不能・入金遅延発生回数（2回以上は要注意先対象）"},
            {"name": "assigned_department", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：管轄部署】管轄営業部・料金センター名"},
        ],
    },
    "invoices": {
        "description": "月次請求データ：2026年4月〜9月の6ヶ月分の月次請求金額、サービス種別、決済方式、支払期日を管理",
        "fields": [
            {"name": "invoice_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：請求ID】主キー（payments.invoice_idと結合）"},
            {"name": "customer_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：契約者ID】外部キー（customer_credit.customer_idと結合）"},
            {"name": "billing_month", "type": "DATE", "mode": "NULLABLE", "description": "【日本語名：請求月】請求対象年月（2026-04-01〜2026-09-01）"},
            {"name": "subscriber_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：契約区分】'個人_回線契約者' または '法人_多回線一括請求'"},
            {"name": "service_type", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：サービス種別】法人多回線一括請求(ビリングONE・光/IoT)、個人通信料＋電話料金合算 等"},
            {"name": "billing_method", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：決済方式】口座振替、クレジットカード、払込票・請求書払い 等"},
            {"name": "billed_amount_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：請求金額_円】月間請求金額（円）"},
            {"name": "due_date", "type": "DATE", "mode": "NULLABLE", "description": "【日本語名：支払期日】請求の支払期日"},
            {"name": "payment_terms_days", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：支払サイト日数】標準支払サイト日数（原則30日）"},
        ],
    },
    "payments": {
        "description": "入金・未収消込データ：請求に対する入金済金額、期日超過の未収残高、入金経路、消込ステータス、遅延日数を管理",
        "fields": [
            {"name": "payment_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：入金ID】主キー"},
            {"name": "invoice_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：請求ID】外部キー（invoices.invoice_idと結合）"},
            {"name": "customer_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：契約者ID】外部キー（customer_credit.customer_idと結合）"},
            {"name": "payment_date", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：実入金日】実際の入金日（未収の場合は空文字）"},
            {"name": "paid_amount_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：入金済金額_円】入金済金額（円）"},
            {"name": "unpaid_amount_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：未収残高_円】現在の期日超過・未収残高（円）"},
            {"name": "payment_channel", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：入金経路】口座自動引落、クレカ決済、コンビニ払込票・銀行振込、未入金 等"},
            {"name": "reconciliation_status", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：消込ステータス】'期日内入金'、'遅延入金(督促後)'、'未収(期日超過)'"},
            {"name": "delay_days", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：遅延日数】支払期日からの遅延日数（日）"},
        ],
    },
    "operators": {
        "description": "オペレーターマスタ：全50名の所属チーム、スキルランク、在籍月数、平均処理時間(AHT)、一次解決率(FCR)、平均顧客満足度(CSAT)、月間応対件数を管理",
        "fields": [
            {"name": "operator_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：オペレーターID】主キー（OP-001〜OP-050）"},
            {"name": "operator_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：オペレーター氏名】担当者氏名"},
            {"name": "team_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：所属チーム】所属受電チーム名"},
            {"name": "skill_rank", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：スキルランク】S_エキスパート、A_シニア、B_スタンダード、C_ジュニア"},
            {"name": "tenure_months", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：在籍月数】在籍月数（ヶ月）"},
            {"name": "avg_handle_time_sec", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：平均処理時間_秒】平均処理時間 AHT（秒：通話＋後処理時間の平均）"},
            {"name": "first_call_resolution_rate", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：一次解決率_pct】一次解決率 FCR（%：初回入電で解決した割合）"},
            {"name": "avg_csat_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：平均満足度スコア】平均顧客満足度 CSAT（5段階評価：1.00〜5.00）"},
            {"name": "monthly_calls_handled", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：月間応対件数】月間平均応対件数（件）"},
        ],
    },
    "call_logs": {
        "description": "入電ログ：1,500件の入電日時、曜日、時間帯、問合せ大分類・詳細理由、待ち時間、処理時間、放棄呼フラグ、一次解決フラグを管理",
        "fields": [
            {"name": "call_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：入電ID】主キー（CALL-10001〜CALL-11500）"},
            {"name": "call_date", "type": "DATE", "mode": "NULLABLE", "description": "【日本語名：入電日】入電日付（2026-04-01〜2026-09-30）"},
            {"name": "year_month", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：入電年月】入電年月（2026-04〜2026-09）"},
            {"name": "day_of_week", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：曜日】曜日（1_月曜〜7_日曜）"},
            {"name": "hour_slot", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：時間帯】入電時間帯（09時台〜18時台）"},
            {"name": "inquiry_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：問合せ大分類】請求・引落確認、支払期日・分割相談、WEB明細・ログイン操作、契約内容変更・解約、法人リース審査・増枠"},
            {"name": "inquiry_sub_reason", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：問合せ詳細理由】問い合わせ詳細理由（ツリーマップ第2階層用）"},
            {"name": "operator_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：オペレーターID】担当オペレーターID（operators.operator_idと結合、放棄呼はUNASSIGNED）"},
            {"name": "wait_time_sec", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：待ち時間_秒】応答までの待ち時間（秒）"},
            {"name": "handle_time_sec", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：処理時間_秒】通話および後処理時間（秒）"},
            {"name": "is_abandoned", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：放棄呼フラグ】1:放棄呼（あふれ呼）、0:正常応答"},
            {"name": "is_fcr", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：一次解決フラグ】1:初回解決、0:再入電またはエスカレーション発生"},
        ],
    },
    "csat_surveys": {
        "description": "顧客満足度・VOCアンケート：応対後のCSATスコア(1〜5)、NPS区分、AI感情スコア、VOC主要トピックを管理",
        "fields": [
            {"name": "survey_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：アンケートID】主キー"},
            {"name": "call_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：入電ID】外部キー（call_logs.call_idと結合）"},
            {"name": "operator_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：オペレーターID】外部キー（operators.operator_idと結合）"},
            {"name": "csat_score", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：満足度スコア】顧客満足度スコア（1〜5の5段階評価）"},
            {"name": "nps_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：NPS区分】Promoter_推奨者、Passive_中立者、Detractor_批判者"},
            {"name": "sentiment_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：感情スコア】AI感情分析スコア（-1.00〜+1.00）"},
            {"name": "voc_tag", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：VOCトピック】顧客の声（VOC）主要トピック分類"},
        ],
    },
    "employees": {
        "description": "社員マスタ：全300名の所属本部・部署、職種、等級、理論年収、直近6ヶ月平均残業時間、エンゲージメントスコア、AI離職リスクを管理",
        "fields": [
            {"name": "employee_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：社員ID】主キー（EMP-1001〜EMP-1300）"},
            {"name": "employee_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：社員氏名】従業員氏名"},
            {"name": "division_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：所属本部】所属本部名（5本部）"},
            {"name": "department_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：所属部署】所属部署名"},
            {"name": "job_role", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：職種】データ・AIエンジニア、クラウドアーキテクト、法人アカウント営業、債権・与信スペシャリスト 等"},
            {"name": "grade", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：職能等級】G1_スタッフ〜G5_部長クラス"},
            {"name": "annual_salary_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：理論年収_円】理論年収（円）"},
            {"name": "avg_overtime_hours_6m", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：平均残業時間_月】直近6ヶ月平均残業時間（時間/月）"},
            {"name": "engagement_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：エンゲージメントスコア】エンゲージメント総合スコア（0〜100点）"},
            {"name": "turnover_risk_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：離職リスクスコア】AI離職リスクスコア（0〜100点：高スコアほど離職懸念大）"},
            {"name": "turnover_risk_level", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：離職リスク区分】High_要ケア、Medium_注意、Low_安定"},
        ],
    },
    "attendance_monthly": {
        "description": "月次勤怠データ：2026年4月〜9月の社員別残業時間、有給取得日数、リモートワーク日数、深夜労働時間、入社・退職フラグを管理",
        "fields": [
            {"name": "record_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：勤怠レコードID】主キー"},
            {"name": "year_month", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：対象年月】対象年月（2026-04〜2026-09）"},
            {"name": "employee_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：社員ID】外部キー（employees.employee_idと結合）"},
            {"name": "division_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：所属本部】所属本部名"},
            {"name": "overtime_hours", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：月間残業時間】当月残業時間（時間）"},
            {"name": "paid_leave_days", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：有給取得日数】当月有給休暇取得日数（日）"},
            {"name": "remote_work_days", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：リモート勤務日数】当月リモートワーク実施日数（日）"},
            {"name": "late_night_hours", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：深夜労働時間】当月深夜労働時間（22時以降：時間）"},
            {"name": "is_new_hire", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：当月入社フラグ】1:当月入社、0:既存在籍"},
            {"name": "is_retired", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：当月退職フラグ】1:当月退職発生、0:継続在籍"},
        ],
    },
    "engagement_surveys": {
        "description": "エンゲージメントサーベイ：2026年Q1/Q3の総合スコア、業務量満足度、上司支援スコア、キャリア成長実感、人事評価ランクを管理",
        "fields": [
            {"name": "survey_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：サーベイID】主キー"},
            {"name": "survey_period", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：実施期】サーベイ実施期（2026_Q1, 2026_Q3）"},
            {"name": "employee_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：社員ID】外部キー（employees.employee_idと結合）"},
            {"name": "overall_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：総合スコア】エンゲージメント総合スコア（0〜100点）"},
            {"name": "workload_satisfaction_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：業務量満足度】業務量・ワークライフバランス満足度スコア（0〜100点）"},
            {"name": "manager_support_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：上司支援スコア】上司の支援・1on1満足度スコア（0〜100点）"},
            {"name": "career_growth_score", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：成長実感スコア】キャリア成長実感スコア（0〜100点）"},
            {"name": "performance_rating", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：人事評価ランク】直近人事評価ランク（S, A, B, C）"},
        ],
    },
    "marketing_campaigns": {
        "description": "マーケティング施策マスタ：全40施策のチャネル種別、実施月、投下広告費、獲得リード数、創出商談額、受注額、ROI(%)、受注率を管理",
        "fields": [
            {"name": "campaign_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：施策ID】主キー（CMP-001〜CMP-040）"},
            {"name": "campaign_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：キャンペーン名】マーケティング施策・キャンペーン名"},
            {"name": "channel_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：チャネル種別】マーケティングチャネル種別（5分類）"},
            {"name": "launch_month", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：実施月】キャンペーン実施年月（2026-04〜2026-09）"},
            {"name": "spend_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：投下費用_円】マーケティング投下費用（円）"},
            {"name": "leads_generated", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：獲得リード数】獲得リード件数（件）"},
            {"name": "pipeline_generated_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：創出商談額_円】創出商談パイプライン総額（円）"},
            {"name": "won_revenue_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：獲得受注額_円】獲得受注金額（円）"},
            {"name": "roi_percentage", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：ROI_pct】投資対効果 ROI（%：(獲得受注金額-投下費用)/投下費用×100）"},
            {"name": "win_rate_pct", "type": "FLOAT", "mode": "NULLABLE", "description": "【日本語名：受注率_pct】商談受注率（%）"},
        ],
    },
    "leads_activities": {
        "description": "見込み客リード活動履歴：1,200件の獲得チャネル、獲得日、顧客規模セグメント、関心プロダクト、接点回数、有効商談化(SQL)フラグを管理",
        "fields": [
            {"name": "lead_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：リードID】主キー（LEAD-30001〜LEAD-31200）"},
            {"name": "campaign_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：施策ID】獲得元キャンペーンID（marketing_campaigns.campaign_idと結合）"},
            {"name": "channel_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：チャネル種別】獲得チャネル種別（5分類）"},
            {"name": "acquired_date", "type": "DATE", "mode": "NULLABLE", "description": "【日本語名：獲得日】リード獲得日（2026-04-01〜2026-09-30）"},
            {"name": "year_month", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：獲得年月】リード獲得年月（2026-04〜2026-09）"},
            {"name": "company_segment", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：企業規模区分】顧客企業規模セグメント"},
            {"name": "target_product", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：関心プロダクト】関心プロダクト・ソリューション名"},
            {"name": "touchpoint_count", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：接点回数】インサイドセールス・Web接点回数（回）"},
            {"name": "is_sql_qualified", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：有効商談化フラグ】1:営業商談化済み(SQL)、0:ナーチャリング中"},
        ],
    },
    "sales_opportunities": {
        "description": "商談パイプライン：600件の担当営業部署、商談フェーズ(5段階)、創出月、完了予定日、商談金額、受注確度、期待金額、商談リードタイムを管理",
        "fields": [
            {"name": "opportunity_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：商談ID】主キー（OPP-50001〜OPP-50600）"},
            {"name": "lead_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：リードID】元リードID（leads_activities.lead_idと結合）"},
            {"name": "campaign_id", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：施策ID】起因キャンペーンID（marketing_campaigns.campaign_idと結合）"},
            {"name": "channel_category", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：チャネル種別】獲得チャネル種別（5分類）"},
            {"name": "sales_department", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：担当営業部】担当営業部署名"},
            {"name": "stage_name", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：商談フェーズ】商談フェーズ（5段階）"},
            {"name": "created_month", "type": "STRING", "mode": "NULLABLE", "description": "【日本語名：商談創出月】商談創出年月（2026-04〜2026-09）"},
            {"name": "close_date", "type": "DATE", "mode": "NULLABLE", "description": "【日本語名：完了予定日】想定受注日・完了日"},
            {"name": "deal_amount_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：商談金額_円】商談金額（円）"},
            {"name": "probability_pct", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：受注確度_pct】受注確度（%：20, 40, 60, 80, 100）"},
            {"name": "weighted_amount_jpy", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：期待商談額_円】確度加味期待商談金額（円）"},
            {"name": "sales_cycle_days", "type": "INTEGER", "mode": "NULLABLE", "description": "【日本語名：リードタイム日数】商談リードタイム日数（日）"},
        ],
    },
}

COMMON_FORMATTING_INSTRUCTION = (
    "\n\n【テーブル出力・日本語カラム名に関する絶対ルール】\n"
    "1. SQL生成時のカラム別名（エイリアス）の日本語化（1指標＝1カラム厳守）：\n"
    "   - SQLの `SELECT` 句では、物理カラム名（`customer_id` 等）をそのまま出力せず、必ず各カラム説明の【日本語名：〇〇】に基づく**短い日本語の別名（バッククォート囲み）**を付与すること（例：``c.customer_id AS `契約者ID` ``, ``c.customer_name AS `契約者名` ``, ``SUM(p.unpaid_amount_jpy) AS `未収残高合計_円` ``）。\n"
    "   - 【厳守】同じ指標について `FORMAT(...)` によるカンマ表示列と数値列の2つを重複して `SELECT` することは絶対に禁止する。必ず**数値型の1カラムのみ（例：``SUM(deal_amount_jpy) AS `商談金額合計_円` ``）**を出力すること。\n"
    "   - 【重要】BigQueryのカラム名制約により、`AS` のバッククォート内には全角・半角カッコ `（）()` や記号 `/` `%` を含めず、日本語・英数字・アンダースコア `_` のみを使用すること（例：``AS `未収残高_円` ``、``AS `回収率_pct` ``、``AS `平均処理時間_秒` ``）。\n"
    "2. 回答テキスト（文章解説）での金額表記：\n"
    "   - 回答の文章中で金額や件数に言及する際は、読みやすいよう3桁カンマ区切り（例：`¥198,400,000`）および「（約1,984万円）」「（約1.98億円）」などの単位換算を併記すること。"
)

agents_spec = [
    {
        "id": "next_finance_3db_agent",
        "displayName": "請求・入金・与信分析",
        "description": f"請求・入金・顧客与信の3DBから、月次回収率推移（折れ線・複合チャート）、要注意取引先ランキング（棒グラフ）、債権保全シミュレーションを実行します（モデル：{model_id}）。",
        "dataset": "next_finance_handson",
        "tables": ["customer_credit", "invoices", "payments"],
        "systemInstruction": (
            f"あなたはネクストファイナンス株式会社の経営企画部・ビリング事業本部を支援するデータ分析エージェント「請求・入金・与信分析」（基盤モデル：{model_id}）です。\n"
            f"BigQueryデータセット `{project_id}.next_finance_handson` 内の3テーブル（`customer_credit`, `invoices`, `payments`）を `customer_id` および `invoice_id` で結合し、正確なSQLを実行して日本語で回答してください。\n\n"
            "【重要ルール・チャート描画ガイドライン】\n"
            "1. 回答文中の金額解説では「万円」「億円」単位を併記すること。\n"
            "2. 月次回収率推移は `ROUND(SAFE_DIVIDE(SUM(p.paid_amount_jpy), SUM(i.billed_amount_jpy)) * 100, 2)` で算出し、時系列折れ線チャートや複合チャート（棒＝請求総額、折れ線＝回収率）を積極的に描画すること。\n"
            "3. 債権保全シミュレーションでは、社内規程（第11条・第14条・第18条）に基づき、ランクC1/C2の要注意先に対して「与信限度額(`credit_limit_jpy`)の20%圧縮（×0.80）」および「未収残高(`unpaid_amount_jpy`)の60%保全カバー（×0.60）」を試算すること。"
            + COMMON_FORMATTING_INSTRUCTION
        ),
        "exampleQueries": [
            {
                "naturalLanguageQuestion": "直近6ヶ月の月別の請求総額・入金済総額・未収残高総額と回収率の推移を教えてください",
                "sqlQuery": (
                    f"SELECT "
                    f"FORMAT_DATE('%Y-%m', i.billing_month) AS `請求月`, "
                    f"COUNT(DISTINCT i.invoice_id) AS `請求件数`, "
                    f"SUM(i.billed_amount_jpy) AS `請求総額_円`, "
                    f"SUM(p.paid_amount_jpy) AS `入金済総額_円`, "
                    f"SUM(p.unpaid_amount_jpy) AS `未収残高総額_円`, "
                    f"ROUND(SAFE_DIVIDE(SUM(p.paid_amount_jpy), SUM(i.billed_amount_jpy)) * 100, 2) AS `回収率_pct` "
                    f"FROM `{project_id}.next_finance_handson.invoices` AS i "
                    f"JOIN `{project_id}.next_finance_handson.payments` AS p ON i.invoice_id = p.invoice_id "
                    f"GROUP BY `請求月` ORDER BY `請求月`"
                ),
            },
            {
                "naturalLanguageQuestion": "直近6ヶ月で入金遅延が2回以上発生している法人顧客の未収残高ランキングと与信限度額圧縮・60%保全シミュレーションを出してください",
                "sqlQuery": (
                    f"SELECT "
                    f"c.customer_id AS `契約者ID`, "
                    f"c.customer_name AS `契約者名`, "
                    f"c.industry_or_segment AS `業種セグメント`, "
                    f"c.credit_rank AS `与信ランク`, "
                    f"c.delayed_count_last_6m AS `直近6ヶ月遅延回数`, "
                    f"c.credit_limit_jpy AS `現行与信限度額_円`, "
                    f"CAST(ROUND(c.credit_limit_jpy * 0.80) AS INT64) AS `圧縮後与信限度額_円`, "
                    f"SUM(p.unpaid_amount_jpy) AS `未収残高合計_円`, "
                    f"CAST(ROUND(SUM(p.unpaid_amount_jpy) * 0.60) AS INT64) AS `保全カバー額_円` "
                    f"FROM `{project_id}.next_finance_handson.customer_credit` AS c "
                    f"JOIN `{project_id}.next_finance_handson.payments` AS p ON c.customer_id = p.customer_id "
                    f"WHERE c.delayed_count_last_6m >= 2 AND p.unpaid_amount_jpy > 0 "
                    f"GROUP BY 1, 2, 3, 4, 5, 6, 7 "
                    f"ORDER BY `未収残高合計_円` DESC"
                ),
            },
        ],
    },
    {
        "id": "next_finance_callcenter_agent",
        "displayName": "コールセンター分析",
        "description": f"入電ログ・応対者・CSATの3DBから、曜日×時間帯の放棄呼傾向（ヒートマップ／積み上げ棒）、AHT×解決率×CSAT相関（散布図）、VOC内訳（ドーナツ／ツリーマップ）を可視化します（モデル：{model_id}）。",
        "dataset": "next_finance_callcenter",
        "tables": ["operators", "call_logs", "csat_surveys"],
        "systemInstruction": (
            f"あなたはネクストファイナンス株式会社のカスタマーオペレーション本部を支援するデータ分析エージェント「コールセンター分析」（基盤モデル：{model_id}）です。\n"
            f"BigQueryデータセット `{project_id}.next_finance_callcenter` 内の3テーブル（`operators`, `call_logs`, `csat_surveys`）を `operator_id` および `call_id` で結合し、正確なSQLを実行して日本語で回答・チャート描画してください。\n\n"
            "【重要ルール・チャート描画ガイドライン】\n"
            "1. オペレーター別のパフォーマンス比較（平均処理時間 `avg_handle_time_sec` × 一次解決率 `first_call_resolution_rate` × 平均CSAT `avg_csat_score`）を求められた際は、必ず散布図（Scatter Chart）を生成し、早切り・低解決率の要注意オペレーター（OP-048〜OP-050等）を特定すること。\n"
            "2. 問い合わせ大分類（`inquiry_category`：5分類）の構成比には円グラフ／ドーナツチャート（Pie Chart）、大分類×詳細理由（`inquiry_sub_reason`）の階層構成比にはツリーマップ（Treemap）または積み上げ棒グラフを描画すること。\n"
            "3. 曜日（`day_of_week`）× 時間帯（`hour_slot`）の入電数・放棄呼率（`is_abandoned`）分析では、ヒートマップまたは積み上げ棒グラフを用いてピーク時間（月曜・金曜の09-10時台、12時台、17時台）を可視化すること。"
            + COMMON_FORMATTING_INSTRUCTION
        ),
        "exampleQueries": [
            {
                "naturalLanguageQuestion": "オペレーター別の平均処理時間、一次解決率、平均CSATスコアを比較して要注意オペレーターを特定してください",
                "sqlQuery": (
                    f"SELECT "
                    f"operator_id AS `オペレーターID`, "
                    f"operator_name AS `オペレーター氏名`, "
                    f"team_name AS `所属チーム`, "
                    f"skill_rank AS `スキルランク`, "
                    f"avg_handle_time_sec AS `平均処理時間_秒`, "
                    f"first_call_resolution_rate AS `一次解決率_pct`, "
                    f"avg_csat_score AS `平均満足度スコア`, "
                    f"monthly_calls_handled AS `月間応対件数` "
                    f"FROM `{project_id}.next_finance_callcenter.operators` "
                    f"ORDER BY `一次解決率_pct` ASC"
                ),
            },
            {
                "naturalLanguageQuestion": "問い合わせ大分類と詳細理由ごとの入電件数と平均処理時間を集計してください",
                "sqlQuery": (
                    f"SELECT "
                    f"inquiry_category AS `問合せ大分類`, "
                    f"inquiry_sub_reason AS `問合せ詳細理由`, "
                    f"COUNT(*) AS `入電件数`, "
                    f"ROUND(AVG(handle_time_sec), 1) AS `平均処理時間_秒`, "
                    f"ROUND(AVG(is_abandoned) * 100, 2) AS `放棄呼率_pct` "
                    f"FROM `{project_id}.next_finance_callcenter.call_logs` "
                    f"GROUP BY 1, 2 ORDER BY `入電件数` DESC"
                ),
            },
        ],
    },
    {
        "id": "next_finance_hr_agent",
        "displayName": "人事・タレント分析",
        "description": f"社員・月次勤怠・サーベイの3DBから、残業×エンゲージメント×離職リスク相関（散布図）、採用・退職数と離職率推移（複合チャート）、本部×職種別人員・人件費（ツリーマップ）を可視化します（モデル：{model_id}）。",
        "dataset": "next_finance_hr",
        "tables": ["employees", "attendance_monthly", "engagement_surveys"],
        "systemInstruction": (
            f"あなたはネクストファイナンス株式会社のコーポレート管理本部・人事部を支援するデータ分析エージェント「人事・タレント分析」（基盤モデル：{model_id}）です。\n"
            f"BigQueryデータセット `{project_id}.next_finance_hr` 内の3テーブル（`employees`, `attendance_monthly`, `engagement_surveys`）を `employee_id` で結合し、正確なSQLを実行して日本語で回答・チャート描画してください。\n\n"
            "【重要ルール・チャート描画ガイドライン】\n"
            "1. 残業時間（`avg_overtime_hours_6m`）とエンゲージメントスコア（`engagement_score`）や離職リスクスコア（`turnover_risk_score`）の関係を問われた際は、必ず散布図（Scatter Chart）を描画し、残業45時間超でエンゲージメントが急落している傾向を解説すること。\n"
            "2. 月次（`year_month`）の採用人数・退職人数と、離職率または平均残業時間の推移比較を求められた際は、棒グラフと折れ線グラフを組み合わせた複合チャート（Combo Chart）を描画すること。\n"
            "3. 本部（`division_name`）× 職種（`job_role`）別の人員数や人件費総額（`SUM(annual_salary_jpy)`）の構成比を求められた際は、ツリーマップ（Treemap）または円グラフ／棒グラフを描画すること。"
            + COMMON_FORMATTING_INSTRUCTION
        ),
        "exampleQueries": [
            {
                "naturalLanguageQuestion": "所属本部と職種ごとの社員数、人件費総額（年収合計）、平均残業時間、平均エンゲージメントスコアを集計してください",
                "sqlQuery": (
                    f"SELECT "
                    f"division_name AS `所属本部`, "
                    f"job_role AS `職種`, "
                    f"COUNT(*) AS `社員数`, "
                    f"SUM(annual_salary_jpy) AS `人件費総額_円`, "
                    f"CAST(ROUND(AVG(annual_salary_jpy)) AS INT64) AS `平均年収_円`, "
                    f"ROUND(AVG(avg_overtime_hours_6m), 1) AS `平均残業時間_月`, "
                    f"ROUND(AVG(engagement_score), 1) AS `平均エンゲージメントスコア` "
                    f"FROM `{project_id}.next_finance_hr.employees` "
                    f"GROUP BY 1, 2 ORDER BY `人件費総額_円` DESC"
                ),
            },
            {
                "naturalLanguageQuestion": "社員ごとの平均残業時間とエンゲージメントスコア、離職リスクスコア、理論年収の一覧を出してください",
                "sqlQuery": (
                    f"SELECT "
                    f"employee_id AS `社員ID`, "
                    f"employee_name AS `社員氏名`, "
                    f"division_name AS `所属本部`, "
                    f"job_role AS `職種`, "
                    f"avg_overtime_hours_6m AS `平均残業時間_月`, "
                    f"engagement_score AS `エンゲージメントスコア`, "
                    f"turnover_risk_score AS `離職リスクスコア`, "
                    f"turnover_risk_level AS `離職リスク区分`, "
                    f"annual_salary_jpy AS `理論年収_円` "
                    f"FROM `{project_id}.next_finance_hr.employees` "
                    f"ORDER BY `離職リスクスコア` DESC"
                ),
            },
        ],
    },
    {
        "id": "next_finance_sales_agent",
        "displayName": "営業・マーケROI分析",
        "description": f"広告施策・リード・商談の3DBから、広告費×獲得商談額ROI相関（散布図）、商談フェーズ構成比（円グラフ／ドーナツ）、チャネル別月次商談推移（積み上げ面グラフ）を可視化します（モデル：{model_id}）。",
        "dataset": "next_finance_sales_mktg",
        "tables": ["marketing_campaigns", "leads_activities", "sales_opportunities"],
        "systemInstruction": (
            f"あなたはネクストファイナンス株式会社の法人営業本部・マーケティング部を支援するデータ分析エージェント「営業・マーケROI分析」（基盤モデル：{model_id}）です。\n"
            f"BigQueryデータセット `{project_id}.next_finance_sales_mktg` 内の3テーブル（`marketing_campaigns`, `leads_activities`, `sales_opportunities`）を `campaign_id` および `lead_id` で結合し、正確なSQLを実行して日本語で回答・チャート描画してください。\n\n"
            "【重要ルール・チャート描画ガイドライン】\n"
            "1. キャンペーン別の投下費用（`spend_jpy`）と創出商談額（`pipeline_generated_jpy`）または受注額（`won_revenue_jpy`）・ROI（`roi_percentage`）の比較では、必ず散布図（Scatter Chart）を描画すること。\n"
            "2. 商談フェーズ（`stage_name`：5段階）別の商談金額（`deal_amount_jpy`）や件数の構成比を求められた際は、円グラフ／ドーナツチャート（Pie Chart）を描画すること。\n"
            "3. 商談発生月（`created_month`）× チャネル種別（`channel_category`）別の商談金額推移を求められた際は、積み上げ面グラフ（Stacked Area Chart）または積み上げ棒グラフを描画し、ウェビナーやパートナー共催セミナーの成長トレンドを解説すること。"
            + COMMON_FORMATTING_INSTRUCTION
        ),
        "exampleQueries": [
            {
                "naturalLanguageQuestion": "キャンペーン別の投下費用、獲得リード数、創出商談額、獲得受注額、ROIを比較してください",
                "sqlQuery": (
                    f"SELECT "
                    f"campaign_id AS `施策ID`, "
                    f"campaign_name AS `キャンペーン名`, "
                    f"channel_category AS `チャネル種別`, "
                    f"spend_jpy AS `投下費用_円`, "
                    f"leads_generated AS `獲得リード数`, "
                    f"pipeline_generated_jpy AS `創出商談額_円`, "
                    f"won_revenue_jpy AS `獲得受注額_円`, "
                    f"roi_percentage AS `ROI_pct` "
                    f"FROM `{project_id}.next_finance_sales_mktg.marketing_campaigns` "
                    f"ORDER BY `ROI_pct` DESC"
                ),
            },
            {
                "naturalLanguageQuestion": "商談創出月とチャネル種別ごとの商談金額合計と商談件数の推移を教えてください",
                "sqlQuery": (
                    f"SELECT "
                    f"created_month AS `商談創出月`, "
                    f"channel_category AS `チャネル種別`, "
                    f"SUM(deal_amount_jpy) AS `商談金額合計_円`, "
                    f"COUNT(*) AS `商談件数` "
                    f"FROM `{project_id}.next_finance_sales_mktg.sales_opportunities` "
                    f"GROUP BY 1, 2 ORDER BY 1, 2"
                ),
            },
            {
                "naturalLanguageQuestion": "商談フェーズ別の商談件数と商談金額合計、期待商談金額合計を教えてください",
                "sqlQuery": (
                    f"SELECT "
                    f"stage_name AS `商談フェーズ`, "
                    f"COUNT(*) AS `商談件数`, "
                    f"SUM(deal_amount_jpy) AS `商談金額合計_円`, "
                    f"SUM(weighted_amount_jpy) AS `期待商談額合計_円` "
                    f"FROM `{project_id}.next_finance_sales_mktg.sales_opportunities` "
                    f"GROUP BY 1 ORDER BY `商談フェーズ`"
                ),
            },
        ],
    },
]

# Also patch the BigQuery table metadata directly so BigQuery Console shows the exact Japanese labels
for spec in agents_spec:
    ds = spec["dataset"]
    for tbl in spec["tables"]:
        t_schema = TABLE_SCHEMAS[tbl]
        bq_url = f"https://bigquery.googleapis.com/bigquery/v2/projects/{project_id}/datasets/{ds}/tables/{tbl}"
        body = json.dumps({
            "description": t_schema["description"],
            "schema": {"fields": t_schema["fields"]}
        }).encode("utf-8")
        req = urllib.request.Request(
            bq_url,
            data=body,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        try:
            urllib.request.urlopen(req, timeout=10)
        except Exception as e:
            print(f"  [WARN] Could not patch BQ table metadata for {ds}.{tbl}: {e}")

for spec in agents_spec:
    spec["tableSchemas"] = {t: TABLE_SCHEMAS[t] for t in spec["tables"]}

with open("/tmp/agents_spec.json", "w", encoding="utf-8") as f:
    json.dump(agents_spec, f, ensure_ascii=False, indent=2)
PYEOF

for DA_ID in $(python3 -c 'import json; print(" ".join(a["id"] for a in json.load(open("/tmp/agents_spec.json"))))'); do
  python3 -c "
import json
specs = json.load(open('/tmp/agents_spec.json'))
a = [x for x in specs if x['id'] == '${DA_ID}'][0]
ctx = {
    'datasourceReferences': {
        'bq': {
            'tableReferences': [
                {
                    'projectId': '${PROJECT_ID}',
                    'datasetId': a['dataset'],
                    'tableId': t,
                    'schema': a['tableSchemas'][t]
                }
                for t in a['tables']
            ]
        }
    },
    'systemInstruction': a['systemInstruction'],
    'exampleQueries': a.get('exampleQueries', []),
    'options': {
        'model': 'LATEST_GA_MODEL',
        'analysis': {'python': {'enabled': True}}
    }
}
payload = {
    'displayName': a['displayName'],
    'description': a['description'],
    'dataAnalyticsAgent': {
        'stagingContext': ctx,
        'publishedContext': ctx
    }
}
with open('/tmp/da_payload_${DA_ID}.json', 'w', encoding='utf-8') as f:
    json.dump(payload, f, ensure_ascii=False)
"

  echo "  -> Creating/Updating BigQuery Data Agent: ${DA_ID}..."
  curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://geminidataanalytics.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/global/dataAgents?dataAgentId=${DA_ID}" \
    -d @/tmp/da_payload_${DA_ID}.json >/dev/null || true

  sleep 2

  curl -s -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://geminidataanalytics.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/global/dataAgents/${DA_ID}?updateMask=displayName,description,dataAnalyticsAgent.stagingContext,dataAnalyticsAgent.publishedContext" \
    -d @/tmp/da_payload_${DA_ID}.json >/dev/null || true

  curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://geminidataanalytics.googleapis.com/v1beta/projects/${PROJECT_ID}/locations/global/dataAgents/${DA_ID}:setIamPolicy" \
    -d "{
      \"policy\": {
        \"bindings\": [
          {
            \"role\": \"roles/geminidataanalytics.dataAgentUser\",
            \"members\": ${STUDENT_MEMBERS}
          }
        ]
      }
    }" >/dev/null || true
done

# ------------------------------------------------------------------------------
# 6. Register All 4 Custom A2A Agents on Gemini Enterprise Engines
# ------------------------------------------------------------------------------
echo "[6/6] Registering 4 Custom A2A Agents on Gemini Enterprise..."
curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/authorizations?authorizationId=geminidataanalytics" \
  -d '{
    "serverSideOauth2": {
      "clientId": "1019218011647-lvbhgl5ml23tuvuk2dgeidsn1bocanaa.apps.googleusercontent.com",
      "authorizationUri": "https://accounts.google.com/o/oauth2/v2/auth?response_type=none+gsession&access_type=offline&client_id=1019218011647-lvbhgl5ml23tuvuk2dgeidsn1bocanaa.apps.googleusercontent.com&redirect_uri=https://vertexaisearch.cloud.google.com/oauth-redirect&scope=https://www.googleapis.com/auth/geminidataanalytics+https://www.googleapis.com/auth/bigquery",
      "tokenUri": "https://oauth2.googleapis.com/token"
    }
  }' >/dev/null || true

# Discover all active Gemini Enterprise Engines in this project (including next-finance-ge-app and any existing engines like agentspace-gws_*)
ENGINE_LIST_JSON=$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines")

TARGET_ENGINES=$(printf '%s' "${ENGINE_LIST_JSON}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    ids = [e['name'].split('/')[-1] for e in data.get('engines', []) if e.get('solutionType') == 'SOLUTION_TYPE_SEARCH']
    if '${ENGINE_ID}' not in ids:
        ids.append('${ENGINE_ID}')
    print(' '.join(ids))
except Exception:
    print('${ENGINE_ID}')
")

for TARGET_ENG in ${TARGET_ENGINES}; do
  echo "  -> Configuring Engine: ${TARGET_ENG} (Model: ${MODEL_ID})"
  curl -s -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${TARGET_ENG}/widgetConfigs/default_search_widget_config?updateMask=uiSettings.generativeAnswerConfig.modelVersion,uiSettings.modelConfigs" \
    -d "{
      \"uiSettings\": {
        \"generativeAnswerConfig\": {
          \"modelVersion\": \"${MODEL_ID}\"
        },
        \"modelConfigs\": {
          \"${MODEL_ID}\": \"MODEL_ENABLED\"
        }
      }
    }" >/dev/null || true

  curl -s -X PATCH \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${TARGET_ENG}/assistants/default_assistant?updateMask=webGroundingType,defaultWebGroundingToggleOff" \
    -d '{
      "webGroundingType": "WEB_GROUNDING_TYPE_GOOGLE_SEARCH",
      "defaultWebGroundingToggleOff": false
    }' >/dev/null || true

  curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/collections/default_collection/engines/${TARGET_ENG}/assistants/default_assistant/agents" > /tmp/existing_ge_agents_${TARGET_ENG}.json

  for DA_ID in $(python3 -c 'import json; print(" ".join(a["id"] for a in json.load(open("/tmp/agents_spec.json"))))'); do
    curl -s \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "X-Goog-User-Project: ${PROJECT_ID}" \
      "https://geminidataanalytics.googleapis.com/v1beta/a2a/projects/${PROJECT_ID}/locations/global/dataAgents/${DA_ID}/v1/card" > /tmp/card_${DA_ID}.json

    ALREADY_REGISTERED=$(python3 -c "
import json
try:
    specs = json.load(open('/tmp/agents_spec.json'))
    spec_obj = [x for x in specs if x['id'] == '${DA_ID}'][0]
    disp = spec_obj['displayName']
    data = json.load(open('/tmp/existing_ge_agents_${TARGET_ENG}.json'))
    valid_found = []
    invalid_found = []
    for a in data.get('agents', []):
        if a.get('displayName') == disp or '${DA_ID}' in json.dumps(a):
            card_str = a.get('a2aAgentDefinition', {}).get('jsonAgentCard', '')
            if '${DA_ID}' in card_str and 'geminidataanalytics' in card_str and a.get('displayName') == disp:
                valid_found.append(a['name'])
            else:
                invalid_found.append(a['name'])
    for bad in invalid_found:
        print('DELETE:' + bad)
    if valid_found and not invalid_found:
        print('VALID:' + valid_found[0])
except Exception:
    pass
")

    for LINE in ${ALREADY_REGISTERED}; do
      if [[ "${LINE}" == DELETE:* ]]; then
        BAD_NAME="${LINE#DELETE:}"
        curl -s -X DELETE \
          -H "Authorization: Bearer ${TOKEN}" \
          -H "X-Goog-User-Project: ${PROJECT_ID}" \
          "https://discoveryengine.googleapis.com/v1alpha/${BAD_NAME}" >/dev/null || true
      fi
    done

    if [[ "${ALREADY_REGISTERED}" != *"VALID:"* ]]; then
      python3 - "${DA_ID}" "${PROJECT_NUMBER}" <<'PYEOF' > /tmp/register_a2a_${DA_ID}.json
import json, sys
da_id = sys.argv[1]
project_number = sys.argv[2]
specs = json.load(open('/tmp/agents_spec.json'))
a = [x for x in specs if x['id'] == da_id][0]
card = open(f'/tmp/card_{da_id}.json', encoding='utf-8').read()
payload = {
  "displayName": a["displayName"],
  "description": a["description"],
  "a2aAgentDefinition": {
    "jsonAgentCard": card
  },
  "authorizationConfig": {
    "agentAuthorization": f"projects/{project_number}/locations/global/authorizations/geminidataanalytics"
  },
  "sharingConfig": {
    "scope": "ALL_USERS"
  }
}
print(json.dumps(payload, ensure_ascii=False))
PYEOF

      curl -s -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -H "X-Goog-User-Project: ${PROJECT_ID}" \
        "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_NUMBER}/locations/global/collections/default_collection/engines/${TARGET_ENG}/assistants/default_assistant/agents" \
        -d @/tmp/register_a2a_${DA_ID}.json >/dev/null || true
      echo "     [OK] Registered ${DA_ID} (${disp:-}) on ${TARGET_ENG}"
    else
      echo "     [SKIP] ${DA_ID} already registered on ${TARGET_ENG}: ${ALREADY_REGISTERED}"
    fi
  done
  rm -f /tmp/existing_ge_agents_${TARGET_ENG}.json
done

rm -f /tmp/agents_spec.json /tmp/da_payload_*.json /tmp/register_a2a_*.json /tmp/card_*.json

WIDGET_CFG_JSON=$(curl -s -H "Authorization: Bearer ${TOKEN}" -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://discoveryengine.googleapis.com/v1alpha/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${ENGINE_ID}/widgetConfigs/default_search_widget_config" || true)
CID=$(printf '%s' "${WIDGET_CFG_JSON}" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('configId', ''))
except Exception:
    print('')
")

echo ""
echo "=============================================================================="
echo " ✅ セットアップ完了サマリー (Verification Summary - 11アカウント対応)"
echo "=============================================================================="
echo " 1. アカウント割当 (計11アカウント: 管理者1 + お客様・予備10) :"
echo "    - ユーザー名00                     : 講師・管理者専用 (student-xx-...@qwiklabs.net)"
echo "    - ユーザー名01〜ユーザー名10       : お客様受講者9名＋予備1名 (student-xx-...@qwiklabs.net)"
echo "    - 自動検出＆IAM付与済アカウント一覧 : ${USER_PRINCIPALS:-なし}"
echo " 2. BigQuery データセット (4種・計12テーブル / 日本語カラムDescription付) :"
echo "    - ${PROJECT_ID}:next_finance_handson       (請求・入金・与信)"
echo "    - ${PROJECT_ID}:next_finance_callcenter    (コールセンター・VOC)"
echo "    - ${PROJECT_ID}:next_finance_hr            (人事・働き方＆タレント)"
echo "    - ${PROJECT_ID}:next_finance_sales_mktg    (営業パイプライン・マーケROI)"
echo " 3. BigQuery データエージェント (4種 / 9〜10文字表示名・日本語列名設定済) :"
echo "    - next_finance_3db_agent        : 請求・入金・与信分析"
echo "    - next_finance_callcenter_agent : コールセンター分析"
echo "    - next_finance_hr_agent         : 人事・タレント分析"
echo "    - next_finance_sales_agent      : 営業・マーケROI分析"
echo " 4. シナリオ2 横断検索データソース ＆ Gmail / Google Chat 実データ投入状況 :"
echo "    - 接続済データストア一覧 : ${LINKED_DS:-${DS_ARRAY}}（Engine から取得した実際の接続状況）"
echo "    - Gmail 実メール配信     : ${GMAIL_SEEDED:-false} (東都ロジスティクス支払期日延長相談スレッド)"
echo "    - Google Chat 実スペース : ${CHAT_SEEDED:-false} (【審査部×ビリング債権管理】与信・収納モニタリング連携)"
echo "    - 社内規程 PDF データストア: ${DATASTORE_ID} (通信料金等債権管理および与信運用規程)"
echo "    - 実データ再投入コマンド : python3 handson/tf/scripts/seed_gws_data.py --project-id ${PROJECT_ID} --force"
echo " 5. シナリオ1用 高速抜粋版 IR 資料 PDF ダウンロード URL :"
echo "    - ① NTTグループ統合報告書2026(公式12P高速抜粋・1.5MB): https://tichiba.github.io/next-finance-ge-handson/files/ntt_group_integrated_report_2026_excerpt.pdf"
echo "    - ② NTTファイナンス決算資料(公式・106KB)             : https://www.ntt-finance.co.jp/ir/tanshin/pdf/r7_kessan_renketsuzaimu.pdf"
echo "    - ③ IR事業ハイライト・重点課題まとめ(2P・588KB)      : https://tichiba.github.io/next-finance-ge-handson/files/next_finance_ir_highlights_2026.pdf"
echo " 6. Gemini Enterprise Web App / 管理画面 URL (Gemini 4 Argon / 音声入力 / キャンバス / モデルセレクタ 有効化済) :"
if [ -n "${CID}" ]; then
  echo "    - Web App 直接URL : https://vertexaisearch.cloud.google.com/home/cid/${CID}"
  echo "    - Codelab (CID付) : https://tichiba.github.io/next-finance-ge-handson/?cid=${CID}"
fi
echo "    - Console 管理画面: https://console.cloud.google.com/ai/agentspace/locations/global/engines/${ENGINE_ID}/overview?project=${PROJECT_ID}"
echo "    - 機能管理直リンク: https://console.cloud.google.com/ai/agentspace/locations/global/engines/${ENGINE_ID}/configurations/feature-control?project=${PROJECT_ID}"
echo " 7. 全リソース削除（クリーンアップ）コマンド :"
echo "    bash handson/tf/scripts/cleanup.sh ${PROJECT_ID}"
echo "=============================================================================="
rm -f /tmp/gws_seed_status.json
