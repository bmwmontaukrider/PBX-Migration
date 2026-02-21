FROM php:8.2-apache-bookworm

ARG FUSIONPBX_TAG=5.5.7

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html/* \
  && git clone --depth 1 --branch "${FUSIONPBX_TAG}" https://github.com/fusionpbx/fusionpbx.git /var/www/html \
  && git config --global --add safe.directory /var/www/html \
  && echo "${FUSIONPBX_TAG}" > /opt/fusionpbx-tag \
  && git -C /var/www/html rev-parse HEAD > /opt/fusionpbx-commit \
  && chown -R www-data:www-data /var/www/html

LABEL org.opencontainers.image.title="FusionPBX" \
      org.opencontainers.image.version="${FUSIONPBX_TAG}"

EXPOSE 80
