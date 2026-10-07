FROM openbao/openbao:2.7.0
COPY openbao.hcl /openbao/config/openbao.hcl
COPY entrypoint.sh /entrypoint.sh
USER root
RUN chmod +x /entrypoint.sh
EXPOSE 8200
ENTRYPOINT ["/entrypoint.sh"]