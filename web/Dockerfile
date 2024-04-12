FROM httpd:alpine

# tools that I almost always want in the container right away
#RUN apk add --no-cache the_silver_searcher vim less
#    ^^^^^^^ as of Jan 2025, I'm getting intermittent errors like this
#   WARNING: updating and opening https://dl-cdn.alpinelinux.org/alpine/v3.21/main:
#   temporary error (try again later)
# possibly see https://github.com/alpinelinux/docker-alpine/issues/98

# probably the default, but…
WORKDIR /usr/local/apache2

# something like this might be required if directory didn't exist before,
# because Docker bind mounts will be created[1] if they don't exist, and the owner
# would be root:root
#
# I checked `deploy.local` into Git, though, so this shouldn't be a problem for
# the time being
#
# [1]: https://docs.docker.com/get-started/docker-concepts/running-containers/sharing-local-files/#sharing-files-between-a-host-and-container
#ARG LOCALUID
#ENV LOCALUID=$LOCALUID
#RUN chown -R $LOCALUID htdocs

# didn't seem to fix the encoding for the mod_autoindex outputs, but can't
# hurt either; source: https://stackoverflow.com/a/10926894
RUN echo $'\n\
AddDefaultCharset utf-8\n\
IndexOptions +Charset=UTF-8\n\
\n\
<Directory "/usr/local/apache2/htdocs">\n\
    Options +FollowSymLinks\n\
    AllowOverride All\n\
</Directory>' >> conf/httpd.conf

# has to be enabled for `IndexOptions FancyIndexing HTMLTable` and so on
RUN sed -i \
  's~#\(Include conf/extra/httpd-autoindex.conf\)~\1~' \
  conf/httpd.conf
