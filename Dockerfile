# Build-deploy benchmark image, built by Render, Railway, Fly and Vercel from this one file.
# It is upstream sync-server.Dockerfile with the install and build steps run through bench/build.sh, so the
# ::bench:: markers wrap them on every provider. No BuildKit-only syntax (Vercel builds with Buildah) and no --platform
# (every provider builds linux/amd64 natively). Base images are pinned by tag and digest.
FROM node:24.22.1-bookworm@sha256:d862bb5d082c5ae0210ac07e8c0344cb8cf7bef6d78e9b8c50c179da923108ea AS builder

RUN apt-get update && apt-get install -y openssl

WORKDIR /app

# The postinstall of electron (desktop app only) would download its binary.
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1

# Only the files needed for the install, so a warm layer cache can skip it.
COPY .yarn ./.yarn
COPY yarn.lock package.json .yarnrc.yml tsconfig.json lage.config.js ./
COPY packages/api/package.json packages/api/package.json
COPY packages/component-library/package.json packages/component-library/package.json
COPY packages/crdt/package.json packages/crdt/package.json
COPY packages/desktop-client/package.json packages/desktop-client/package.json
COPY packages/desktop-electron/package.json packages/desktop-electron/package.json
COPY packages/eslint-plugin-actual/package.json packages/eslint-plugin-actual/package.json
COPY packages/loot-core/package.json packages/loot-core/package.json
COPY packages/sync-server/package.json packages/sync-server/package.json
COPY packages/plugins-service/package.json packages/plugins-service/package.json
COPY packages/vite-plugin-peggy/package.json packages/vite-plugin-peggy/package.json
COPY ./bin/package-browser ./bin/package-browser
COPY bench/build.sh bench/build.sh
RUN sh ./bench/build.sh install

COPY packages/ ./packages/

# Upstream sets an 8 GB heap limit for the build.
ENV NODE_OPTIONS=--max_old_space_size=8192

# The provider passes the commit as a build arg (Render: RENDER_GIT_COMMIT; Railway: RAILWAY_GIT_COMMIT_SHA;
# Vercel: VERCEL_GIT_COMMIT_SHA; Fly: the harness sets BENCH_COMMIT). Declared after the install step, so a new
# commit does not invalidate the install layer.
ARG BENCH_COMMIT=""
ARG RENDER_GIT_COMMIT=""
ARG RAILWAY_GIT_COMMIT_SHA=""
ARG VERCEL_GIT_COMMIT_SHA=""
RUN sh ./bench/build.sh build

FROM node:24.22.1-bookworm-slim@sha256:be8204d4bd327363357f532187b752ff62759c31bedf98e9e18fc08c9cbd605c AS prod

# Minimal runtime dependencies
RUN apt-get update && apt-get install -y tini && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Create a non-root user
ARG USERNAME=actual
ARG USER_UID=1001
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && mkdir /data && chown -R ${USERNAME}:${USERNAME} /data

WORKDIR /app
# The server reads PORT. 80 is Vercel's routed port; Render and Railway set their own at runtime. Upstream creates the
# actual user but runs as root, so port 80 needs no capability.
ENV NODE_ENV=production \
    PORT=80

# Pull in only the necessary artifacts (built node_modules, server files, etc.)
COPY --from=builder /app/node_modules /app/node_modules
COPY --from=builder /app/packages/sync-server/package.json ./
COPY --from=builder /app/packages/sync-server/build ./build
COPY bench/start.sh bench/start.sh

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
EXPOSE 80
CMD ["sh", "./bench/start.sh"]
