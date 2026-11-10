#!/bin/sh
set -eu

# 保存先（Postgres）の接続URLを差し込む（従来どおり）
sed -i "s|STORAGE_PG_CONNECTION_URL_PLACEHOLDER|${STORAGE_PG_CONNECTION_URL}|g" /openbao/config/openbao.hcl

# プロセスが、生きているか（終了済みで、まだ回収されていないもの = ゾンビ は、生きていないとみなす）
alive() {
  [ -r "/proc/$1/status" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status"
}

# NetBird（任意。NETBIRD_ENABLED=1 のときだけ）。
# 戻したいときは、NETBIRD_ENABLED を消して、再デプロイするだけで、従来の動きに戻る。
EXTRA_CONFIG=""
NB_PID=""
if [ "${NETBIRD_ENABLED:-0}" = "1" ]; then
  : "${NB_HOSTNAME:?NB_HOSTNAME が必要です}"

  mkdir -p /openbao/tls
  chmod 700 /openbao/tls
  # 証明書と鍵を、環境変数から書き出す。読めなければ、OpenBao 本体は止めずに、NetBird 側だけを無効にする。
  if ( umask 077
       printf '%s' "${NB_TLS_CERT_B64:-}" | base64 -d > /openbao/tls/server.crt &&
       printf '%s' "${NB_TLS_KEY_B64:-}" | base64 -d > /openbao/tls/server.key ) 2>/dev/null &&
     [ -s /openbao/tls/server.crt ] && [ -s /openbao/tls/server.key ]; then
    EXTRA_CONFIG="/openbao/config/netbird.hcl"
    # NetBird は、背景で起動する（NetBird の不調で、OpenBao 本体を止めないため）
    /netbird-start.sh &
    NB_PID=$!
  else
    echo "NB: NB_TLS_CERT_B64 / NB_TLS_KEY_B64 を読めないため、NetBird 向けの待ち受けを無効にします"
    rm -f /openbao/tls/server.crt /openbao/tls/server.key
  fi
fi

BAO_PID=""
start_bao() {
  bao server -config=/openbao/config/openbao.hcl "$@" &
  BAO_PID=$!
}

# 停止の合図は、OpenBao に渡す
trap 'kill -TERM "$BAO_PID" 2>/dev/null || true' TERM INT

if [ -n "$EXTRA_CONFIG" ]; then
  start_bao "-config=$EXTRA_CONFIG"
  # 起動の直後に終了したら（証明書が不正で、待ち受けを作れない、など）、
  # NetBird 向けの待ち受けなしで、起動し直す（OpenBao 本体を、アドオンのために止めない）。
  i=0
  while [ "$i" -lt 8 ]; do
    sleep 1
    alive "$BAO_PID" || break
    i=$((i + 1))
  done
  if ! alive "$BAO_PID"; then
    echo "NB: NetBird 向けの待ち受けを付けた起動に失敗したため、付けずに起動し直します（証明書を確認してください）"
    if [ -n "$NB_PID" ]; then
      kill "$NB_PID" 2>/dev/null || true
    fi
    start_bao
  fi
else
  start_bao
fi

# OpenBao が終わるまで待つ。終了コードは、そのまま返す。
STATUS=0
wait "$BAO_PID" || STATUS=$?
# 停止の合図（trap）で wait が中断されたときは、OpenBao が終わるまで待ち直す
while alive "$BAO_PID"; do
  wait "$BAO_PID" || STATUS=$?
done
exit "$STATUS"
