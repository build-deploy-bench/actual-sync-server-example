#!/bin/sh
# Install and build steps of the build-deploy benchmark. The root Dockerfile runs `install` and `build` as
# separate RUN steps, so a warm layer cache can skip the install. Every provider builds that Dockerfile.
set -eu
cd "$(dirname "$0")/.."

# Each marker carries the wall-clock time in epoch milliseconds, so a parser does not depend on the time at which
# the provider received the log line. A `date` without %N (BusyBox) falls back to whole seconds.
mark() {
  now="$(date +%s%3N)"
  case "$now" in *[!0-9]*) now="$(date +%s)000" ;; esac
  printf '::bench::%s %s\n' "$1" "$now"
}

install() {
  mark install_start
  node --version
  yarn --version
  yarn install
  mark install_done
}

# Upstream `yarn build:server` plus the production steps of sync-server.Dockerfile, in one step.
build() {
  mark build_start
  # lage's task hasher runs `git ls-tree HEAD`, and .dockerignore omits the real .git, so upstream seeds a
  # throwaway repo. Skipped when the source is already a git checkout (a local build).
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    git -c init.defaultBranch=master init -q
    git -c user.email=build@docker -c user.name=docker-build add -A
    git -c user.email=build@docker -c user.name=docker-build commit -qm build
  fi
  # The translations are vendored at a pinned commit (see BENCH.md), so skip the clone of their HEAD.
  yarn build:browser --skip-translations
  yarn workspace @actual-app/sync-server build
  write_commit
  # Production node_modules with the built web client in place of the workspace link.
  yarn workspaces focus @actual-app/sync-server --production
  rm -rf node_modules/@actual-app/web node_modules/@actual-app/sync-server
  mkdir -p node_modules/@actual-app/web
  cp packages/desktop-client/package.json node_modules/@actual-app/web/package.json
  cp -r packages/desktop-client/build node_modules/@actual-app/web/build
  mark build_done
}

# The deployed commit comes from the build environment, so an old deployment keeps reporting its own commit.
# BENCH_COMMIT is the harness override (Fly passes it as a build arg); the others are provider variables.
# There is no `git rev-parse` fallback: in the image it would return the throwaway commit above.
write_commit() {
  commit="${BENCH_COMMIT:-${RENDER_GIT_COMMIT:-${RAILWAY_GIT_COMMIT_SHA:-${VERCEL_GIT_COMMIT_SHA:-unknown}}}}"
  printf 'commit: %s\n' "$commit"
  printf '%s\n' "$commit" > packages/sync-server/build/bench-commit
}

case "${1:-all}" in
  install) install ;;
  build) build ;;
  all) install; build ;;
  *) printf 'Usage: %s {install|build|all}\n' "$0" >&2; exit 2 ;;
esac
