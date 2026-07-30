# Frontend Libs 21 Packaging Plan

## Goal

Turn `frontendApplications/frontend-libs-21` from a source-only folder that
`kyc-frontend-21` reaches into via raw TypeScript path aliases into real,
independently buildable, versioned Angular library packages — while keeping
the two GitHub repos (`frontend-libs-21`, `kyc-frontend-21`) separate, exactly
as they are today.

This is scoped to these two projects only. `layout-21` and
`sentinel-kyc-angular-cld` are not touched by this plan.

## Current State (the problem)

### `frontend-libs-21`

- No `package.json` anywhere in the repo — not at the root, not in any of
  the five library folders (`api-common`, `auth`, `layout`, `shared`,
  `assets-common`).
- No `ng-package.json` anywhere — none of the libraries are ever compiled
  through ng-packagr. They are raw `.ts` source that gets pulled directly
  into whatever consumes them.
- `frontend-libs-21/node_modules` is a symlink into the consumer:
  `node_modules -> ../kyc-frontend-21/node_modules`. The repo has no
  dependencies of its own — it silently rides on whatever Angular/RxJS
  version `kyc-frontend-21` happens to have installed. There is no way to
  `npm install`, type-check, lint, or test this repo on its own.
- `frontend-libs-21/AGENTS.md` states this explicitly as the verification
  process today: *"Verify shared-library changes from the consuming Angular
  21 app: `cd ../kyc-frontend-21 && npm run build`."* A broken change is only
  caught transitively, inside someone else's build, never at this repo's own
  PR boundary.
- Two separate GitHub repos (`ahmmedzakaria/frontend-libs-21`,
  `ahmmedzakaria/kyc-frontend-21`) with no coupling artifact between them —
  no submodule, no lockfile, no version pin. Nothing in `kyc-frontend-21`'s
  git history records which `frontend-libs-21` commit a given build used.

### `kyc-frontend-21`

- Consumes the libs via `tsconfig.json` path aliases pointing directly at
  source: `"@nexacore/auth": ["../frontend-libs-21/auth/src/public-api.ts"]`,
  plus a second, wider set of aliases
  (`"@nexacore/auth/*": ["../frontend-libs-21/auth/src/lib/*"]`) that let
  app code reach past `public-api.ts` straight into library internals.
- The Docker build is broken for this pattern. `kyc-frontend-21/Dockerfile`
  builds with a context scoped to `kyc-frontend-21/` (`COPY . .` inside that
  context); `../frontend-libs-21` sits outside the Docker build context
  entirely, so `RUN npm run build` cannot resolve any `@nexacore/*` path
  once it's running inside the container. This is not hypothetical: the
  legacy `frontend`/`frontend-libs` pair this was migrated from (top-level
  `kyc-project-Copy/frontend` + `kyc-project-Copy/frontend-libs`) has the
  identical setup and the identical bug today, and it's the pair actually
  wired into `docker-compose.yml` (`nexacore-frontend: build: ./frontend`).
  `kyc-frontend-21` isn't wired into `docker-compose.yml` yet — so this bug
  hasn't surfaced for it yet, but it will the moment someone does that
  cutover, unless it's fixed first.

### Code-level issues found during the architecture review

These don't block packaging but are worth fixing in the same pass since
they live in the files being touched anyway:

- `ApiService.buildHeaders()` (in `api-common`) re-attaches the
  `Authorization` header itself, duplicating `jwtInterceptor` — both read
  the same `localStorage` key, so it's harmless today but redundant.
- Backend configuration is one hardcoded `Environment` object in
  `api-common` (`backendOrigin: 'http://localhost:9100'`) — no dev/prod
  split, no Angular `fileReplacements`.
- The `service` field on entries in `kyc-frontend-21/src/app/core/api/api-endpoints.ts`
  is never read by `ApiService.resolveBasePath()` — currently vestigial.

## Why this matters

- A breaking change to a shared library can't be caught before it reaches
  an app, because the library has no independent build/lint/test of its
  own.
- There's no answer to "which version of `auth` is this app running" —
  no version field, no lockfile entry, nothing.
- This is explicitly meant to be a *shared* library workspace — the moment
  a second Angular 21 app consumes `frontend-libs-21`, that app inherits
  the same `node_modules` symlink hack and the same Docker breakage.
- The Docker/CI cutover for `kyc-frontend-21` will fail on day one unless
  this is fixed before it happens, not after.

## Target Shape

- **`frontend-libs-21` becomes its own self-contained Angular CLI
  workspace** — its own `angular.json`, its own `package.json`, its own
  `node_modules` (no more symlink). No application project in it, only
  library projects.
- Each of `api-common`, `auth`, `layout`, `shared` becomes a real
  `ng-packagr`-built Angular library with its own `package.json` and a
  semantic version, generated the standard Angular way
  (`ng generate library <name>`). `assets-common` is a single SVG file — it
  doesn't need its own Angular Package Format build; fold it into `shared`'s
  `assets/` rather than standing up a fifth package for one file (call this
  out as a judgment call the user can override).
- **`kyc-frontend-21` depends on the built packages, not the source.** Its
  `package.json` gets four new dependencies pointed at the built output —
  `"@nexacore/auth": "file:../frontend-libs-21/dist/auth"` and similarly for
  the other three. `npm install` turns these into real symlinks under
  `kyc-frontend-21/node_modules/@nexacore/*`, exactly like a normal
  dependency. No new workspace-root file is introduced at the
  `frontendApplications/` level — this keeps the change contained to only
  these two repos, matching the chosen scope.
- The wide `"@nexacore/auth/*"` aliases that currently let app code reach
  into `src/lib/*` internals go away. Only `public-api.ts`'s exports are
  reachable from `kyc-frontend-21` going forward — that boundary is the
  whole point of packaging.
- Docker/CI: publish the four packages to **GitHub Packages** (npm
  registry backed by the same `ahmmedzakaria` GitHub account both repos
  already live under). This is the cleanest fix for the Docker bug because
  it removes the cross-repo file dependency entirely — `kyc-frontend-21`'s
  Docker build does a completely normal, single-context `npm install`
  against a registry, the same as any third-party dependency. A lighter
  local-only fallback (moving the Docker build context up to
  `frontendApplications/` and adjusting the `COPY` paths) is noted in Phase
  5 for anyone who wants to defer setting up a registry.

## Migration Principles

- One package at a time, `api-common` first — `auth`, `layout`, and
  `shared` all import from it, so packaging it first means every later
  package can depend on a real, versioned `@nexacore/api-common` instead of
  another path alias.
- Keep `kyc-frontend-21` buildable after every phase. No big-bang cutover
  where the app can't build for a stretch of commits.
- This migration changes *how* the libraries are packaged, not *what* they
  export. Don't rename or restructure `public-api.ts` surfaces as part of
  this — that's a separate, later change if it's needed at all.
- Fix the Docker build context in the same pass that makes the libraries
  installable — one is the direct cause of the other being fixable.

## Phase 1: Turn `frontend-libs-21` into its own Angular CLI workspace

- Run `ng new frontend-libs-21-workspace --no-create-application` (or
  equivalent) to get a bare Angular 21 workspace shell, then move its
  generated `angular.json`, `package.json`, `tsconfig.json`, and config
  files into the existing `frontend-libs-21/` repo root, merging with what's
  already there (the existing `tsconfig.json` compiler options should carry
  over, not be replaced).
- Delete the `node_modules` symlink; run a real `npm install` in
  `frontend-libs-21/`.
- Do not move or touch any of the five existing library folders in this
  phase — this step only stands up the workspace shell around them.

## Phase 2: Package `api-common`

- Run `ng generate library api-common` inside the new workspace. This
  scaffolds `projects/api-common/` with `ng-package.json`,
  `package.json`, `tsconfig.lib.json`, and a `src/public-api.ts`.
- Move the existing `api-common/src/lib/*` and `api-common/src/public-api.ts`
  content into the generated project structure (paths will shift from
  `frontend-libs-21/api-common/src/...` to
  `frontend-libs-21/projects/api-common/src/...`, or reconfigure
  `angular.json`'s `root`/`sourceRoot` for the `api-common` project to point
  at the existing `frontend-libs-21/api-common/src` location instead of
  moving files — either is fine, pick whichever keeps the git history
  cleaner).
- Set an initial version in the generated `package.json` (`0.1.0`).
- `ng build api-common` should produce `dist/api-common/` in Angular
  Package Format.

## Phase 3: Package `auth`, `layout`, `shared`

- Same steps as Phase 2, repeated for each. `auth` and `layout` currently
  import from `api-common` — once Phase 2 is done, update those imports to
  come from the built `@nexacore/api-common` package (resolvable inside the
  workspace via a local `file:` or npm workspace link at this stage — the
  cross-repo consumption model only matters once `kyc-frontend-21` is
  involved, in Phase 4).
- Fold `assets-common`'s single SVG into `shared/assets/` (see Target
  Shape) unless the user wants it kept as a fifth package.

## Phase 4: Rewire `kyc-frontend-21` to consume the built packages

- Add `"@nexacore/api-common": "file:../frontend-libs-21/dist/api-common"`
  (and the same for `auth`, `layout`, `shared`) to
  `kyc-frontend-21/package.json`'s `dependencies`.
- Remove the `@nexacore/*` entries from `kyc-frontend-21/tsconfig.json`'s
  `paths` — once they're real `node_modules` packages, TypeScript resolves
  them normally and the path aliases are no longer needed (this is also
  what removes app code's ability to reach into library internals via the
  old `"@nexacore/auth/*"` wildcard alias).
- Remove the `frontend-libs-21` → `kyc-frontend-21/node_modules` symlink
  reference (already gone once Phase 1 gives `frontend-libs-21` its own
  `node_modules`).
- `npm install && npm run build` in `kyc-frontend-21/` to confirm the app
  still builds against the packaged libraries.

## Phase 5: Fix the Docker build

**Implemented: the local-only fallback.** `kyc-frontend-21/Dockerfile` is now
a 3-stage build — stage 1 builds all four `frontend-libs-21` packages
(`ng build api-common && ng build shared && ng build layout && ng build
auth`), stage 2 copies that `dist/` output into the app's build stage
(`COPY --from=libs /workspace/frontend-libs-21/dist ../frontend-libs-21/dist`,
positioned as a sibling exactly like on disk) before `npm install`/`npm run
build`, stage 3 is the unchanged nginx serve step. Build it with the context
moved up a level, from `frontendApplications/`:

```bash
docker build -f kyc-frontend-21/Dockerfile -t nexacore-frontend .
```

Added `.dockerignore` at `frontendApplications/` (the new context root —
Docker only reads `.dockerignore` from the exact context root, so the
per-project ones are inert for this build; kept them anyway for anyone who
containerizes a single project standalone) excluding `node_modules`, `dist`,
`.angular`, `coverage` across every project folder.

**Not verified end-to-end**: this sandbox's Docker daemon requires either
`docker` group membership or `sudo`, and passwordless `sudo` isn't
configured, so `docker build` itself couldn't be run here. The individual
commands the Dockerfile runs (`npm install`, `ng build` × 4, `npm install`,
`npm run build`) are the exact sequence already verified directly and
repeatedly in this repo's local shell — but running the actual `docker
build` command above is a needed follow-up check.

**GitHub Packages (documented, not wired up)** — the path for when this
needs to stop depending on both repos being checked out as siblings on the
same machine/build agent:

1. Add to each `projects/<lib>/package.json`:
   ```json
   "publishConfig": { "registry": "https://npm.pkg.github.com" }
   ```
2. `frontend-libs-21` publishes on release via GitHub Actions, using the
   workflow's own built-in `GITHUB_TOKEN` (needs `permissions: packages:
   write` in the workflow) — no separate PAT needed for same-account
   publish/consume.
3. `kyc-frontend-21`'s `package.json` dependencies switch from
   `file:../frontend-libs-21/dist/<lib>` to a real version range (e.g.
   `"^0.1.0"`), and its Dockerfile goes back to a single stage with an
   `.npmrc` (`@nexacore:registry=https://npm.pkg.github.com`) plus an
   authenticated `NODE_AUTH_TOKEN` build secret before `npm install`.

Deliberately not implemented as an actual workflow file in this pass —
standing up real automated publishing (registry choice, token/secrets setup,
what triggers a release) is an infrastructure decision for the user to opt
into explicitly, not something to wire up as a side effect of a Docker fix.

## Phase 6: Versioning and change tracking

- Add a `CHANGELOG.md` per package (or a single root changelog covering all
  four, given how small they are today).
- Consider [Changesets](https://github.com/changesets/changesets) once
  there's more than one consuming app — it automates version bumps and
  changelog entries per PR. Not necessary for a single consumer; flagging
  it here so it's not rediscovered later as a surprise.

## Phase 7: Address the code-level issues

- Collapse the duplicate JWT attachment — keep it in `jwtInterceptor` only,
  remove the `Authorization` branch from `ApiService.buildHeaders()`.
- Split `Environment` into dev/prod via Angular `fileReplacements`, or at
  minimum make `backendOrigin` overridable at build time instead of
  hardcoded.
- Either wire up the `service` field on `ApiEndpoint` in
  `ApiService.resolveBasePath()`, or remove it from the endpoint definitions
  if it's not going to be used.

## Verification Strategy

- After Phase 1–3: `ng build <lib>` and `ng test <lib>` succeed
  independently inside `frontend-libs-21/`, with no reference to
  `kyc-frontend-21` at all.
- After Phase 4: `npm run build` and `npm test` succeed inside
  `kyc-frontend-21/` against the packaged (not source) libraries.
- After Phase 5: `docker build` for `kyc-frontend-21` succeeds standalone,
  without `frontend-libs-21` present on disk alongside it (proves the
  cross-repo file dependency is actually gone).
- Full regression: run `kyc-frontend-21`'s existing Vitest suite and
  Playwright smoke tests after each phase, not just at the end.

## Risks

- Angular 21 is very new; `ng-packagr` compatibility should be confirmed
  against the exact Angular 21 version pinned in `kyc-frontend-21/package.json`
  before starting Phase 2 — if there's a mismatch, this plan's timeline
  slips until that's resolved upstream.
- Moving files into `ng generate library`'s scaffolded structure will churn
  git history in `frontend-libs-21` if done as a move rather than an
  `angular.json` root/sourceRoot override — pick the override approach if
  preserving blame history matters.
- GitHub Packages requires every consumer (local dev machines, CI runners)
  to have a valid registry token configured — this is a real setup cost,
  not just a config line. The local `file:` fallback exists specifically so
  Phase 4 doesn't block on Phase 5's registry setup being finished first.

## Recommended First Step

Phase 1 + Phase 2 (`api-common` only): stand up the workspace shell and
package the one library everything else depends on. That alone proves the
whole approach — `ng build api-common` producing real dist output, then
`kyc-frontend-21` consuming it via a `file:` dependency instead of a path
alias — before committing to repeating the same steps three more times.
