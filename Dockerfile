FROM certbot/certbot:v5.0.0 AS certbot
COPY tls/renew-certificates.sh /opt/tls/renew-certificates.sh
ENTRYPOINT ["/bin/sh", "/opt/tls/renew-certificates.sh"]

FROM nginx:stable-alpine AS nginx
COPY default.conf /etc/nginx/conf.d/default.conf
COPY tls/default.conf.template /opt/tls/default.conf.template
COPY tls/run-nginx.sh /opt/tls/run-nginx.sh
COPY tls/entrypoint.sh /opt/tls/entrypoint.sh
ENTRYPOINT ["/bin/sh", "/opt/tls/entrypoint.sh"]
ENV TLS_DOMAIN=event.onsite-print.dk
EXPOSE 443
CMD ["/bin/sh", "/opt/tls/run-nginx.sh"]
