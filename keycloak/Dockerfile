FROM quay.io/keycloak/keycloak:26.0

ENV KC_DB=postgres
ENV KC_DB_URL=jdbc:postgresql://host.docker.internal:5433/kyc_db?currentSchema=keycloak
ENV KC_DB_USERNAME=postgres

ENV KC_HOSTNAME=localhost
ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false

EXPOSE 9200

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start-dev", "--http-port=9200"]