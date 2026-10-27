# The course specifies Alpine 3.11. Kept here to reproduce that exercise.
# It is an old release; choose a supported, pinned release for a new application.
FROM alpine:3.11

RUN apk add --no-cache nginx curl \
    && mkdir -p /run/nginx /usr/share/nginx/html

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
