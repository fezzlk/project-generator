#!/usr/bin/env bash
set -euo pipefail

# GCPプロジェクト初期設定（冪等・ステップ指定可能）
# Usage: setup-gcp-project.sh <PROJECT_ID> <REPO_NAME> <SERVICE_NAME> <REGION> <USE_FIRESTORE> [--from STEP] [--only STEP] [--list]

# --- ヘルパー ---
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# --- ステップ定義 ---
STEPS=(
  "set-project"
  "enable-apis"
  "create-artifact-registry"
  "create-service-account"
  "bind-sa-iam"
  "bind-cloudbuild-iam"
)

STEP_DESCRIPTIONS=(
  "GCPプロジェクトの設定 (gcloud config set project)"
  "必要なAPIの有効化"
  "Artifact Registryリポジトリの作成"
  "Cloud Run用サービスアカウントの作成"
  "サービスアカウントへのIAMロール付与"
  "Cloud BuildサービスアカウントへのIAMロール付与"
)

show_steps() {
  echo ""
  echo "利用可能なステップ:"
  for i in "${!STEPS[@]}"; do
    echo "  $((i + 1)). ${STEPS[$i]}  - ${STEP_DESCRIPTIONS[$i]}"
  done
  echo ""
  echo "使用例:"
  echo "  全ステップ実行:          $0 <PROJECT_ID> <REPO_NAME> <SERVICE_NAME>"
  echo "  ステップ3から再開:       $0 <PROJECT_ID> <REPO_NAME> <SERVICE_NAME> <REGION> <USE_FIRESTORE> --from 3"
  echo "  ステップ2のみ実行:       $0 <PROJECT_ID> <REPO_NAME> <SERVICE_NAME> <REGION> <USE_FIRESTORE> --only 2"
  echo "  ステップ名でも指定可能:  $0 ... --from enable-apis"
  echo ""
}

# --- 引数パース ---
POSITIONAL_ARGS=()
FROM_STEP=""
ONLY_STEP=""

for arg in "$@"; do
  case "${arg}" in
    --list)
      show_steps
      exit 0
      ;;
  esac
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM_STEP="$2"
      shift 2
      ;;
    --only)
      ONLY_STEP="$2"
      shift 2
      ;;
    --list)
      shift
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

PROJECT_ID="${1:?PROJECT_ID is required}"
REPO_NAME="${2:?REPO_NAME is required}"
SERVICE_NAME="${3:?SERVICE_NAME is required}"
REGION="${4:-asia-northeast1}"
USE_FIRESTORE="${5:-n}"

SA_NAME="${SERVICE_NAME}-run"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# --- ステップ番号の解決 ---
resolve_step_number() {
  local input="$1"
  # 数値ならそのまま
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"
    return
  fi
  # ステップ名で検索
  for i in "${!STEPS[@]}"; do
    if [[ "${STEPS[$i]}" == "$input" ]]; then
      echo "$((i + 1))"
      return
    fi
  done
  error "不明なステップ: ${input}"
  show_steps
  exit 1
}

# 実行範囲の決定
START_STEP=1
END_STEP=${#STEPS[@]}

if [[ -n "$ONLY_STEP" ]]; then
  RESOLVED=$(resolve_step_number "$ONLY_STEP")
  START_STEP=$RESOLVED
  END_STEP=$RESOLVED
elif [[ -n "$FROM_STEP" ]]; then
  START_STEP=$(resolve_step_number "$FROM_STEP")
fi

should_run() {
  local step_num=$1
  [[ $step_num -ge $START_STEP && $step_num -le $END_STEP ]]
}

# --- ステップ実装 ---

step_set_project() {
  info "[1/6] GCPプロジェクトを設定中: ${PROJECT_ID}"
  gcloud config set project "${PROJECT_ID}"
  success "プロジェクト設定完了"
}

step_enable_apis() {
  info "[2/6] 必要なAPIを有効化中..."
  local APIS=(
    run.googleapis.com
    artifactregistry.googleapis.com
    cloudbuild.googleapis.com
    secretmanager.googleapis.com
  )
  if [[ "${USE_FIRESTORE}" == "y" ]]; then
    APIS+=(firestore.googleapis.com)
  fi

  for api in "${APIS[@]}"; do
    info "  ${api}"
    gcloud services enable "${api}" --quiet 2>/dev/null || true
  done
  success "API有効化完了"
}

step_create_artifact_registry() {
  info "[3/6] Artifact Registryリポジトリを作成中..."
  if gcloud artifacts repositories describe "${REPO_NAME}" \
      --location="${REGION}" --format="value(name)" 2>/dev/null; then
    warn "リポジトリ ${REPO_NAME} は既に存在します（スキップ）"
  else
    gcloud artifacts repositories create "${REPO_NAME}" \
      --repository-format=docker \
      --location="${REGION}" \
      --description="Docker repository for ${SERVICE_NAME}"
    success "リポジトリ ${REPO_NAME} を作成しました"
  fi
}

step_create_service_account() {
  info "[4/6] サービスアカウントを作成中..."
  if gcloud iam service-accounts describe "${SA_EMAIL}" 2>/dev/null; then
    warn "サービスアカウント ${SA_NAME} は既に存在します（スキップ）"
  else
    gcloud iam service-accounts create "${SA_NAME}" \
      --display-name="Cloud Run service account for ${SERVICE_NAME}"
    success "サービスアカウント ${SA_NAME} を作成しました"
  fi
}

step_bind_sa_iam() {
  info "[5/6] サービスアカウントにIAMロールを付与中..."
  local ROLES=(
    roles/datastore.user
    roles/secretmanager.secretAccessor
    roles/storage.objectViewer
  )

  for role in "${ROLES[@]}"; do
    info "  ${role}"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="${role}" \
      --condition=None \
      --quiet 2>/dev/null || true
  done
  success "IAMロール付与完了"
}

step_bind_cloudbuild_iam() {
  info "[6/6] Cloud Buildサービスアカウントに権限を付与中..."
  local PROJECT_NUMBER
  PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
  local CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

  local CB_ROLES=(
    roles/run.admin
    roles/iam.serviceAccountUser
    roles/artifactregistry.writer
  )

  for role in "${CB_ROLES[@]}"; do
    info "  ${role} → ${CB_SA}"
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${CB_SA}" \
      --role="${role}" \
      --condition=None \
      --quiet 2>/dev/null || true
  done
  success "Cloud Build権限付与完了"
}

# --- 実行 ---
info "GCPプロジェクト: ${PROJECT_ID}"
if [[ -n "$ONLY_STEP" ]]; then
  info "ステップ ${START_STEP} のみ実行: ${STEPS[$((START_STEP - 1))]}"
elif [[ $START_STEP -gt 1 ]]; then
  info "ステップ ${START_STEP} から再開: ${STEPS[$((START_STEP - 1))]}"
fi
echo ""

should_run 1 && step_set_project
should_run 2 && step_enable_apis
should_run 3 && step_create_artifact_registry
should_run 4 && step_create_service_account
should_run 5 && step_bind_sa_iam
should_run 6 && step_bind_cloudbuild_iam

echo ""
success "GCPプロジェクトの初期設定が完了しました（ステップ ${START_STEP}-${END_STEP}）"
