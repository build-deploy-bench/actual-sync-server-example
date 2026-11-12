# Build-deploy benchmark fixture: docker-medium (Actual Budget sync server)

## Source

- Upstream: https://github.com/actualbudget/actual at tag `v26.11.0` = `1766241e3f4b3c578e424c4fa15f1eb83c0da17d`. MIT license, kept in `LICENSE.txt`. The fixture is the sync server (`packages/sync-server`, Node + Express + SQLite) with the web client that it serves (`packages/desktop-client`, built with Vite).
- This repo: https://github.com/build-deploy-bench/actual-sync-server-example (private, independent copy). The first commit `e9ccf2f` has the same tree as the upstream tag (`9f4d044…`), without history.
- Tier: docker-medium (image under 1 GB). Image size: see [Image size](#image-size).

## Patches

1. Upstream GitHub Actions workflows removed, so no scheduled or release job runs in this copy.
2. Translations vendored. Upstream `bin/package-browser` clones `actualbudget/translations` at HEAD on every build, so two builds of one commit can differ. `packages/desktop-client/locale` now holds that repo at `21771afd37ac7684b31c43ed1e87814a94666eae` (2026-11-12) after upstream's `remove-untranslated-languages` (17 files, 2.4 MB). The build runs `yarn build:browser --skip-translations`. Both `.gitignore` entries for `locale` are removed.
3. `GET /version` returns `{"commit","run","deployment","touch"}` (`packages/sync-server/src/app.ts`). `commit` is read from `build/bench-commit`, which `bench/build.sh` writes from `BENCH_COMMIT`, `RENDER_GIT_COMMIT`, `RAILWAY_GIT_COMMIT_SHA` or `VERCEL_GIT_COMMIT_SHA`, else `unknown`. There is no `git rev-parse` fallback, because the image build creates a throwaway git repo (see below). `run` is `BENCH_RUN_ID`, `deployment` is `RAILWAY_DEPLOYMENT_ID`, `touch` is the touch file's value. The server prints `::bench::listening <ms>` in its listen callback.
4. Touch file `packages/sync-server/src/bench-touch.ts`, imported by `src/app.ts`. The harness overwrites the whole file.
5. Root `Dockerfile` replaced. Upstream's root `Dockerfile` is the dev container for `docker-compose.yml`; it moves to `dev.Dockerfile`, and `docker-compose.yml` points there. The new root `Dockerfile` is upstream `sync-server.Dockerfile` (kept unchanged) with these differences:
   - The install (`yarn install`) and build (`yarn build:server` steps, `yarn workspaces focus --production`, copy of the web build) run as `RUN sh ./bench/build.sh install` and `RUN sh ./bench/build.sh build` in one build stage. Upstream's `deps` and `builder` stages become one stage.
   - `ELECTRON_SKIP_BINARY_DOWNLOAD=1`, so the `electron` postinstall (desktop app only) downloads no binary.
   - Base images pinned by digest (same tags as upstream: `node:24.22.1-bookworm` and `node:24.22.1-bookworm-slim`).
   - `ARG` for the four commit variables after the install step.
   - `ENV PORT=80` (the server reads `PORT`; upstream default 5006). Upstream creates the `actual` user but runs as root, so port 80 needs no capability.
   - Start command `sh ./bench/start.sh`, which prints `::bench::start <ms>` and then `exec node build/app.js` under upstream's `tini` entrypoint.
6. Added `bench/build.sh`, `bench/start.sh`, `fly.toml`, `vercel.json` and this file. `fly.toml` was in upstream `.gitignore`; that entry is removed.

The upstream 8 GB Node heap limit (`NODE_OPTIONS=--max_old_space_size=8192`) is kept. It is only a limit: the builds used far less, and no builder ran out of memory (Render and Vercel builders have 8 GB, Railway more, Fly's remote builder 8 GB). `lage` needs a git repo, so the build step does upstream's `git init` + `git add -A` + `git commit` of the build context (including `node_modules`) when the context has no `.git`. That takes 10 to 40 s and is part of the build span on every provider.

The server needs no secrets. SQLite and the server files live in `/data` inside the container (upstream default); data is lost on each deploy.

## Commands

| Step | Command | Markers |
|---|---|---|
| Install | `sh ./bench/build.sh install` = `yarn install` (Yarn 4.17.1, `node-modules` linker) | `::bench::install_start` / `::bench::install_done` |
| Build | `sh ./bench/build.sh build` = throwaway git repo, `yarn build:browser --skip-translations`, `yarn workspace @actual-app/sync-server build`, write `build/bench-commit`, `yarn workspaces focus @actual-app/sync-server --production`, copy the web build into `node_modules/@actual-app/web` | `::bench::build_start` / `::bench::build_done` |
| Start | `sh ./bench/start.sh` = `node build/app.js` (runs the migrations, then listens) | `::bench::start` / `::bench::listening` |
| Health | `GET /health` returns 200 `{"status":"UP"}` | |

Every marker ends with the wall-clock time in epoch milliseconds (GNU `date` in the Debian build image).

## Image size

| Image | Compressed | Uncompressed |
|---|---|---|
| Published `actualbudget/actual-server:26.11.0` (research thread) | 121 MB | 395 MB |
| This Dockerfile, local `linux/arm64` build | 119 MB | 570 MB (`docker image inspect` size) |
| This Dockerfile, `linux/amd64` from Fly's registry (`f6a759a`) | 121 MB (sum of the 12 layer blobs) | 434 MB (`docker history`); flyctl prints `image size: 371 MB` |

`/app/node_modules` is 173 MB and `/app/build` under 1 MB. The rest is the `node:24.22.1-bookworm-slim` base and `tini`.

## Providers

All four build the root `Dockerfile`. Auto-deploy is off everywhere. The setup deploys are not results.

### Render

- Workspace `tea-dbmbhbg8v5cc73e4m0jg` (Pro). Service `srv-dbqug68ae00c73df5ap0` `bdb-actual-sync-server`, https://bdb-actual-sync-server.onrender.com
- Runtime `docker`, `./Dockerfile`, context `.`. Region `virginia`. Instance plan `starter`, build plan `starter` (2 CPU / 8 GB). Health check `/health`. Auto-deploy `no`. Render sets `PORT=10000`.
- Setup deploy `dep-dbqug6oae00c73df5bi0` of `ded5fef` (the creation deploy): live, `/version` returned the right SHA through `RENDER_GIT_COMMIT`. Install 48 s, build 78 s, `exporting cache to registry` 72 s.

### Railway

- Workspace `d535606c-49a7-4a6c-9e29-ce73b5f01428`. Project `bdb-actual-sync-server` `473d1cd4-4820-4c24-b7f9-5cf7991d0faf`, environment `production` `5cdf82ca-aa8a-4c6f-8d5d-326c6002900b`, service `c76db5bc-8710-4278-a416-3708c90f3a1b`, https://bdb-actual-sync-server-production.up.railway.app
- Source `build-deploy-bench/actual-sync-server-example` branch `main`. Railway picks the Dockerfile builder because the root `Dockerfile` exists (the service setting still says `RAILPACK`). One replica, default region. Health check `/health`. No variables. Auto-deploy disabled after `railway add` and confirmed with `serviceInstanceAutoDeployStatus`.
- Deploys: `b1eba4eb-…` (the connect deploy of `ded5fef`) and `2ce8d22f-…` (`railway redeploy --commit`); both succeeded, and `/version` returned the right SHA and deployment ID.

### Vercel

- Team `build-deploy-bench`. Project `bdb-actual-sync-server` `prj_Hz5tBCElE3LcDDs7xCUF9wF5SMKI`, https://bdb-actual-sync-server.vercel.app. No Git link; deploys upload a clean context with `vercel deploy --prod`.
- Container Runtime (`framework: container`). Function region `iad1`. Build machine `standard`, selection `fixed` (4 vCPU / 8 GB), like every fixture project.
- Setup deploy `dpl_5MsskZUx1CFtrq3zHLECev3GLAvT` of `ded5fef`: READY, `/version` returned the run ID. `commit` is `unknown`: a project env var `BENCH_COMMIT` (tried once, then removed) did not reach the Dockerfile either.

### Fly.io

- Org `personal`. App `bdb-actual-sync-server`, https://bdb-actual-sync-server.fly.dev, `iad`, shared-cpu-1x with 1 GB (the `fly launch` default; the app uses about 250 MB idle), one always-on Machine. Health check `/health`, `internal_port = 80`.
- Deploy: `flyctl deploy --config fly.toml -a bdb-actual-sync-server --remote-only --depot=false --ha=false --strategy bluegreen --build-arg BENCH_COMMIT=<sha>` from a `git archive` of the commit.
- Deploys of `ded5fef` (2026-11-12): the first one ran while other fixtures built on the same remote builder (install 13 min) and was stopped. Setup deploy of `f6a759a` with the Fly build lock: `/version` returned the right SHA and run ID.
- Fly's remote builder is much slower for this build than the other builders: the build step took 434 s cold and 377 s warm with the builder to itself, against 78 to 118 s elsewhere. Most of the gap is in disk-heavy steps (the `git add -A` of `node_modules` and the Vite build).

## Matrix check (2026-11-12)

`matrix/run.py --runs cold,warm` on each provider, matrix `2026-11-12-docker-medium`. All eight runs succeeded and served the new `/version`. End to end (s):

| Provider | Cold | Warm | Notes |
|---|---|---|---|
| Render | 255 | 179 | `exporting cache to registry` 65 s cold, 50 s warm |
| Railway | 196 | 195 | the cold run is `partial`: layers from the setup deploys were still cached |
| Vercel | 338 | 267 | Buildah store cache restore 33 s warm |
| Fly | 818 | 500 | slow remote builder, see above |

Warm runs skipped the install step on all four providers.
