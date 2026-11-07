# Image of the daily Mongo backup job (issue E0.4). Lives outside apps/backend on purpose.
# Only needs mongodump plus curl: the upload uses the Cloud Storage JSON API with the job's
# own token, so the service account only needs roles/storage.objectCreator on the bucket.
FROM debian:12.8-slim

ARG TOOLS_VERSION=100.10.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq \
 && curl -fsSL "https://fastdl.mongodb.org/tools/db/mongodb-database-tools-debian12-x86_64-${TOOLS_VERSION}.tgz" \
      | tar -xz --strip-components=2 -C /usr/local/bin --wildcards '*/bin/mongodump' \
 && apt-get purge -y --auto-remove \
 && rm -rf /var/lib/apt/lists/* \
 && mongodump --version

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh
ENTRYPOINT ["/usr/local/bin/backup.sh"]
