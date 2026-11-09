#!/bin/sh
# NetBird（netstack）を起動して、同じピアとして復帰する。検証した ttyd の start.sh と同じ方式。
# 失敗しても、OpenBao 本体は止めない（entrypoint.sh が、これを背景で起動する）。
#
#   NB_HOSTNAME     必須。固定の名前（例: openbao）
#   NB_CONFIG_B64   登録済みのピア設定（base64）。あれば、登録せずに、同じピア・同じIPで復帰する
#   NB_SETUP_KEY    初回の登録だけ（使用回数1回、Ephemeral オフ）。復元できたら、環境変数から消す
#   NB_PRINT_CONFIG 1 のとき、ピア設定を base64 でログに1行出す（初回だけ。秘密鍵入り）
export NB_USE_NETSTACK_MODE=true
export NB_ENABLE_NETSTACK_LOCAL_FORWARDING=true   # NetBird IP宛て → localhost へ転送
export NB_CONFIG=/tmp/nb/config.json

mkdir -p /tmp/nb
chmod 700 /tmp/nb

RESTORED=0
if [ -n "${NB_CONFIG_B64:-}" ]; then
  if ( umask 077; printf '%s' "$NB_CONFIG_B64" | base64 -d > "$NB_CONFIG" ) 2>/dev/null && [ -s "$NB_CONFIG" ]; then
    RESTORED=1
    echo "NB: ピア設定を復元しました"
  else
    echo "NB: NB_CONFIG_B64 を読めません"
  fi
fi

netbird service run &

# 常駐プロセスの起動待ち（最大30秒）
i=0
while [ "$i" -lt 30 ]; do
  netbird status >/dev/null 2>&1 && break
  i=$((i + 1))
  sleep 1
done

if [ "$RESTORED" = 1 ]; then
  netbird up --hostname "$NB_HOSTNAME" || echo "NB: netbird up（復元）に失敗しました"
elif [ -n "${NB_SETUP_KEY:-}" ]; then
  netbird up --setup-key "$NB_SETUP_KEY" --hostname "$NB_HOSTNAME" || echo "NB: netbird up（初回登録）に失敗しました"
else
  echo "NB: NB_CONFIG_B64 も NB_SETUP_KEY も無いため、NetBird には参加しません"
  exit 0
fi

# 接続待ち（最大30秒。出力の文言が変わっても、先へ進む）
i=0
while [ "$i" -lt 30 ]; do
  netbird status 2>/dev/null | grep -qi "Management: Connected" && break
  i=$((i + 1))
  sleep 1
done

echo "NB_IP=$(netbird status --ipv4 2>/dev/null || echo unknown) NB_HOSTNAME=${NB_HOSTNAME}"

if [ "${NB_PRINT_CONFIG:-0}" = "1" ]; then
  if [ -s "$NB_CONFIG" ]; then
    echo "NB_CONFIG_B64=$(base64 "$NB_CONFIG" | tr -d '\n')"
  else
    echo "NB: NB_PRINT_CONFIG=1 ですが、$NB_CONFIG がありません"
  fi
fi
