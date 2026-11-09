#!/bin/sh
set -eu

# 保存先（Postgres）の接続URLを差し込む（従来どおり）
sed -i "s|STORAGE_PG_CONNECTION_URL_PLACEHOLDER|${STORAGE_PG_CONNECTION_URL}|g" /openbao/config/openbao.hcl

# NetBird（任意。NETBIRD_ENABLED=1 のときだけ）。
# 戻したいときは、NETBIRD_ENABLED を消して、再デプロイするだけで、従来の動きに戻る。
EXTRA_CONFIG=""
if [ "${NETBIRD_ENABLED:-0}" = "1" ]; then
  : "${NB_HOSTNAME:?NB_HOSTNAME が必要です}"

  mkdir -p /openbao/tls
  chmod 700 /openbao/tls
  # 証明書と鍵を、環境変数から書き出す。読めなければ、OpenBao 本体は止めずに、NetBird 側だけを無効にする。
  if ( umask 077
       printf '%s' "${NB_TLS_CERT_B64:-}" | base64 -d > /openbao/tls/server.crt &&
       printf '%s' "${NB_TLS_KEY_B64:-}" | base64 -d > /openbao/tls/server.key ) 2>/dev/null &&
     [ -s /openbao/tls/server.crt ] && [ -s /openbao/tls/server.key ]; then
    EXTRA_CONFIG="-config=/openbao/config/netbird.hcl"
    # NetBird は、背景で起動する（NetBird の不調で、OpenBao 本体を止めないため）
    /netbird-start.sh &
  else
    echo "NB: NB_TLS_CERT_B64 / NB_TLS_KEY_B64 を読めないため、NetBird 向けの待ち受けを無効にします"
    rm -f /openbao/tls/server.crt /openbao/tls/server.key
  fi
fi

# EXTRA_CONFIG は、空のときに何も渡さないよう、あえて引用符で囲まない
exec bao server -config=/openbao/config/openbao.hcl $EXTRA_CONFIG
