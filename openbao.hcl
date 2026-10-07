storage "postgresql" {
  connection_url = "STORAGE_PG_CONNECTION_URL_PLACEHOLDER"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

api_addr = "https://openbao.jyrac.stki.org"

ui = true