FROM openbao/openbao:2.7.0

ARG NETBIRD_VERSION=0.81.5
# 任意（空でも動く。入れるほうが安全）: リリースページの netbird_${NETBIRD_VERSION}_checksums.txt にある、
# netbird_${NETBIRD_VERSION}_linux_amd64.tar.gz の SHA256。違っていれば、ビルドが失敗する。
ARG NETBIRD_SHA256=""

USER root

# NetBird クライアント。最後の `netbird version` は、Alpine（musl）で動くかの、ビルド時の確認。
# 動かなければ、ビルドが失敗する（その場合は、公式の netbirdio/netbird イメージから、バイナリをコピーする形に変える）。
RUN apk add --no-cache curl && \
    curl -fsSL -o /tmp/netbird.tar.gz \
      "https://github.com/netbirdio/netbird/releases/download/v${NETBIRD_VERSION}/netbird_${NETBIRD_VERSION}_linux_amd64.tar.gz" && \
    if [ -n "${NETBIRD_SHA256}" ]; then echo "${NETBIRD_SHA256}  /tmp/netbird.tar.gz" | sha256sum -c -; fi && \
    tar -xzf /tmp/netbird.tar.gz -C /usr/local/bin netbird && \
    rm -f /tmp/netbird.tar.gz && \
    /usr/local/bin/netbird version

COPY openbao.hcl /openbao/config/openbao.hcl
COPY netbird.hcl /openbao/config/netbird.hcl
COPY entrypoint.sh /entrypoint.sh
COPY netbird-start.sh /netbird-start.sh
RUN sed -i 's/\r$//' /entrypoint.sh /netbird-start.sh && chmod +x /entrypoint.sh /netbird-start.sh

EXPOSE 8200
ENTRYPOINT ["/entrypoint.sh"]
