#!/bin/bash
# ci/seal.sh <dir> <branch>
# يشفّر مخرجات الفحص (النسخة والصور والسجلات) بمفتاح عام، ويرفعها لفرع لا يُقرأ محتواه:
# لا يستطيع فتحها إلا صاحب المفتاح الخاص (لا يوجد في المستودع). أي أحد يحمّل الفرع يجد بيانات مشفّرة فقط.
set -euo pipefail
DIR="$1"; BRANCH="$2"
OSSL=openssl
if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" ]; then OSSL="$(brew --prefix openssl@3)/bin/openssl"; fi
W=$(mktemp -d)
tar czf "$W/payload.tgz" -C "$DIR" .
"$OSSL" rand -hex 32 > "$W/k.txt"
KP="$W/k.txt"
# ويندوز (Git Bash): openssl برنامج ويندوز لا يفهم مسار /tmp داخل «file:» — يُحوَّل لمسار ويندوز
if command -v cygpath >/dev/null 2>&1; then KP="$(cygpath -m "$KP")"; fi
"$OSSL" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass "file:$KP" -in "$W/payload.tgz" -out "$W/payload.enc"
"$OSSL" pkeyutl -encrypt -pubin -inkey "$GITHUB_WORKSPACE/ci/transport_pub.pem" -pkeyopt rsa_padding_mode:oaep -in "$W/k.txt" -out "$W/key.enc"
rm -f "$W/k.txt" "$W/payload.tgz"
mkdir -p "$W/pub" && cd "$W/pub"
split -b 90m "$W/payload.enc" payload.enc.part-
cp "$W/key.enc" .
git init -q -b "$BRANCH"
git add -A
git -c user.name=ci -c user.email=ci@local commit -qm "sealed ${GITHUB_RUN_NUMBER:-0}"
git push -qf "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}" "$BRANCH"
echo "sealed $(du -sh "$W/payload.enc" | cut -f1) -> $BRANCH"
