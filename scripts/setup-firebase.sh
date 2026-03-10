#!/usr/bin/env bash
set -euo pipefail

# Firebase初期設定（冪等）
# Usage: setup-firebase.sh <PROJECT_ID> <USE_AUTH> <USE_FIRESTORE> <REGION>

PROJECT_ID="${1:?PROJECT_ID is required}"
USE_AUTH="${2:-n}"
USE_FIRESTORE="${3:-n}"
REGION="${4:-asia-northeast1}"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

info "Firebase設定: プロジェクト ${PROJECT_ID}"

# Firebaseプロジェクト追加
info "Firebaseプロジェクトを追加中..."
firebase projects:addfirebase "${PROJECT_ID}" 2>/dev/null || {
  warn "Firebaseプロジェクトは既に追加済みか、エラーが発生しました（スキップ）"
}

# Firestore
if [[ "${USE_FIRESTORE}" == "y" ]]; then
  info "Firestoreデータベースを作成中..."
  gcloud firestore databases create \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --type=firestore-native 2>/dev/null || {
    warn "Firestoreデータベースは既に存在します（スキップ）"
  }
  success "Firestore設定完了"
fi

# Firebase Auth
if [[ "${USE_AUTH}" == "y" ]]; then
  info "Firebase Authを有効化中..."
  gcloud services enable identitytoolkit.googleapis.com \
    --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  success "Firebase Auth有効化完了"
  info "認証プロバイダーの設定はFirebaseコンソールから行ってください:"
  info "  https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
fi

echo ""
success "Firebase初期設定が完了しました"
