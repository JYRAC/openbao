# Casdoor（SSO）への、NetBird 経由の TCP 中継をビルド（標準ライブラリのみ）
FROM golang:1.27-alpine AS nbtcp-build
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0
WORKDIR /src
COPY nbtcp.go ./
RUN go mod init nbtcp && \
    go build -trimpath -ldflags="-s -w" -o /out/nbtcp .

# OpenBao が、Casdoor の内部口の証明書を検証するための、ルート証明書だけを取り出す。
#   ca.crt は、複数枚のバンドルでもよい。CA（CA:TRUE）のものだけを使う（旧い自己署名の証明書は、入れない）。
#   ルートは、名前制約つき（netbird.cloud と jyrac.stki.org のみ）なので、他の名前には使えない。
FROM alpine:3.24 AS trust-root
RUN apk add --no-cache openssl
COPY ca.crt /tmp/ca.crt
RUN mkdir -p /out /tmp/split && cd /tmp/split && \
    tr -d '\r' < /tmp/ca.crt | awk '/BEGIN CERTIFICATE/{n++} {print > ("c" n ".pem")}' && \
    for f in c*.pem; do \
      if openssl x509 -in "$f" -noout -ext basicConstraints | grep -q 'CA:TRUE'; then cp "$f" "/out/jyrac-root-$f.crt"; fi; \
    done && \
    test -n "$(ls /out)" && ls /out

FROM openbao/openbao:2.7.0

ARG NETBIRD_VERSION=0.81.5
# 任意（空でも動く。入れるほうが安全）: リリースページの netbird_${NETBIRD_VERSION}_checksums.txt にある、
# netbird_${NETBIRD_VERSION}_linux_amd64.tar.gz の SHA256。違っていれば、ビルドが失敗する。
ARG NETBIRD_SHA256=""

USER root

# NetBird クライアント。最後の `netbird version` は、Alpine（musl）で動くかの、ビルド時の確認。
# 動かなければ、ビルドが失敗する（その場合は、公式の netbirdio/netbird イメージから、バイナリをコピーする形に変える）。
RUN apk add --no-cache curl ca-certificates && \
    curl -fsSL -o /tmp/netbird.tar.gz \
      "https://github.com/netbirdio/netbird/releases/download/v${NETBIRD_VERSION}/netbird_${NETBIRD_VERSION}_linux_amd64.tar.gz" && \
    if [ -n "${NETBIRD_SHA256}" ]; then echo "${NETBIRD_SHA256}  /tmp/netbird.tar.gz" | sha256sum -c -; fi && \
    tar -xzf /tmp/netbird.tar.gz -C /usr/local/bin netbird && \
    rm -f /tmp/netbird.tar.gz && \
    /usr/local/bin/netbird version

# ルート証明書を、システムの信頼する証明書に入れる（OpenBao の OIDC ログインが、Casdoor の証明書を検証できるように）。
# OIDC の設定（oidc_discovery_ca_pem など）は、変えなくてよい。公開側の証明書も、これまでどおり検証できる。
COPY --from=trust-root /out/ /usr/local/share/ca-certificates/
RUN update-ca-certificates
COPY --from=nbtcp-build /out/nbtcp /usr/local/bin/nbtcp
RUN chmod +x /usr/local/bin/nbtcp

COPY openbao.hcl /openbao/config/openbao.hcl
COPY netbird.hcl /openbao/config/netbird.hcl
COPY entrypoint.sh /entrypoint.sh
COPY netbird-start.sh /netbird-start.sh
RUN sed -i 's/\r$//' /entrypoint.sh /netbird-start.sh && chmod +x /entrypoint.sh /netbird-start.sh

EXPOSE 8200
ENTRYPOINT ["/entrypoint.sh"]
