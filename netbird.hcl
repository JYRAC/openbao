# NetBird 向けの待ち受け。NETBIRD_ENABLED=1 のときだけ、entrypoint.sh が、これも読み込む。
#   - 127.0.0.1 だけで待ち受ける（外からは届かない。NetBird の転送だけが、ここに届く）
#   - TLS 1.3 のみ。証明書と鍵は、起動時に、環境変数から /openbao/tls に書き出される
#   - 既存の 0.0.0.0:8200（公開側、TLSなし）は、openbao.hcl のまま。NetBird の ACL には、8210 だけを出す
listener "tcp" {
  address         = "127.0.0.1:8210"
  tls_cert_file   = "/openbao/tls/server.crt"
  tls_key_file    = "/openbao/tls/server.key"
  tls_min_version = "tls13"
}
