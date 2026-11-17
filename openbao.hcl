storage "postgresql" {
  connection_url = "STORAGE_PG_CONNECTION_URL_PLACEHOLDER"
}

# 本体の、TLS なしの待ち受けは、コンテナの中だけ(127.0.0.1)。外に見える 0.0.0.0:8200 は、pubgate が受ける
# (既定は /healthz だけに応答。OPENBAO_PUBLIC=open のときだけ、ここに流す)。
# クラスタ用の待ち受けも、既定で address+1 になり、127.0.0.1:8206 になる。
listener "tcp" {
  address     = "127.0.0.1:8205"
  tls_disable = "true"
}

api_addr = "https://openbao.jyrac.stki.org"

ui = true

audit "file" "to-stdout" {
  description = "Audit log to stdout"
  options = {
    file_path = "stdout"
  }
}
