FROM docker:stable

RUN apk add --update bash curl netcat-openbsd

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

