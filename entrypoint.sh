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

# Casdoor（SSO）への、サーバー側の通信（OIDC ログインの、発見文書、トークン、鍵）は、NetBird 経由で、Casdoor の内部口 A に出す。
#   CASDOOR_NB_ADDR  内部口 A の、NetBird の IP:ポート（Casdoor の固定ピアの IP:8443。IPv4 のみ）。空なら、公開側のまま。
# OpenBao は、発見文書に書かれた公開の URL（https://auth.jyrac.stki.org/...）に通信するので、URL は変えずに、
#   1. nbtcp が、127.0.0.1:443 で受けて、NetBird の SOCKS5 経由で、内部口 A に、バイトをそのまま流す（TLS は終わらせない）。
#   2. 内部口に、TLS 1.3 でつながり、証明書を検証できたと確認してから、/etc/hosts で、この名前を 127.0.0.1 に向ける。
#      （届かないうちは、向けない。公開側のまま。届くまで、繰り返し確認する）
#   3. OpenBao が、Casdoor と直接 TLS で話し、名前 auth.jyrac.stki.org と、システムの信頼する証明書
#      （ルート入り。Dockerfile で追加）で、検証する。検証は、切らない。
# ブラウザが開く認可の URL は、公開のまま（利用者の通信は、内部口を通さない。/etc/hosts は、このコンテナの中だけ）。
if [ -n "$NB_PID" ] && [ -n "${CASDOOR_NB_ADDR:-}" ]; then
  CASDOOR_HOST="${CASDOOR_HOSTNAME:-auth.jyrac.stki.org}"
  nbtcp &
  (
    until NB_CHECK_SEC=20 nbtcp --check; do sleep 10; done
    if grep -q "[[:space:]]$CASDOOR_HOST\$" /etc/hosts 2>/dev/null; then
      :
    elif echo "127.0.0.1 $CASDOOR_HOST" >> /etc/hosts 2>/dev/null; then
      echo "NB: Casdoor の内部口に届くことを確認しました。OIDC の通信は、NetBird 経由の内部口を使います (CASDOOR_VIA=netbird)"
    else
      echo "NB: /etc/hosts に書けませんでした。OIDC の通信は、公開側のままです (CASDOOR_VIA=public)"
    fi
  ) &
else
  echo "NB: Casdoor へは、公開側でつなぎます (CASDOOR_VIA=public)"
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
