FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.9
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates clang curl git libc6-dev unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" CI=true FLUTTER_SUPPRESS_ANALYTICS=true
WORKDIR /src
COPY pubspec.yaml pubspec.lock l10n.yaml ./
COPY lib/l10n/ ./lib/l10n/
RUN flutter pub get --enforce-lockfile
COPY lib/ ./lib/
COPY bin/ ./bin/
COPY hook/ ./hook/
COPY native/sqlite/ ./native/sqlite/
RUN dart build cli --target bin/bottogram.dart --output /out

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o 1000 -g 1000 -m 0700 /data
COPY --from=build /out/bundle/ /opt/bottogram/
USER 1000:1000
ENTRYPOINT ["/opt/bottogram/bin/bottogram"]
