#!/bin/sh
set -e

sed -i "s|STORAGE_PG_CONNECTION_URL_PLACEHOLDER|${STORAGE_PG_CONNECTION_URL}|g" /openbao/config/openbao.hcl

exec bao server -config=/openbao/config/openbao.hcl