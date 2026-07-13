# Angular 21 Layout Migration Plan

## Goal

Upgrade `frontendApplications/frontend-libs-21` and
`frontendApplications/kyc-frontend-21` to follow the architecture proven in
`frontendApplications/layout`.

The target project shape is:

- Angular 21 standalone application
- TypeScript with strict compiler and strict template checks
- Zoneless change detection
- Signals for local UI state
- RxJS reserved for asynchronous streams such as HTTP
- Angular CDK for behavior primitives such as overlays and positioning
- Custom SCSS design-token system under `src/styles`
- Custom SVG icon registry under `src/app/shared/icon`
- Internationalization through `@jsverse/transloco`
- Vitest for unit tests and Playwright for end-to-end tests

## Current State

### `frontendApplications/layout`

- Already follows the Angular 21 target architecture.
- Contains the reference shell behavior:
  - header dropdowns
  - rail navigation
  - rail flyouts
  - status bar
  - theme state
  - language/direction state
  - custom SVG icon registry
  - SCSS design tokens
- Should be treated as the source reference for the new shared layout shell.

### `frontendApplications/frontend-libs-21`

- Currently a source-only copy of the old shared libraries.
- Has no root `package.json`.
- Contains these library folders:
  - `api-common`
  - `auth`
  - `layout`
  - `shared`
  - `assets-common`
- The copied `layout` library still uses the older shell model:
  - `LayoutComponent`
  - `SidebarComponent`
  - `TopbarComponent`
  - `LayoutService`
  - `SidebarMenuService`
- Old shared code still depends on Bootstrap/Font Awesome patterns.
- `api-common` currently uses Angular Material snackbar behavior.
- `auth` depends on old layout services.

### `frontendApplications/kyc-frontend-21`

- Currently incomplete as an Angular workspace.
- Has `angular.json`, source files, `node_modules`, and generated output.
- Missing expected root workspace files:
  - `package.json`
  - `package-lock.json`
  - `tsconfig.json`
  - `tsconfig.app.json`
  - `tsconfig.spec.json`
  - `proxy.conf.json`, if backend proxying is still required
- `angular.json` still follows Angular 19-era configuration:
  - `@angular-devkit/build-angular`
  - Zone.js polyfill
  - Karma test builder
  - Angular Material, Bootstrap, and Font Awesome styles/scripts
- Asset paths still point to `../frontend-libs` instead of
  `../frontend-libs-21`.

## Migration Principles

- Keep the reference `layout` app working while shared libraries are upgraded.
- Do not migrate every page and shared component at once.
- First milestone should be a successful Angular 21 build of
  `kyc-frontend-21` against `frontend-libs-21`.
- Treat `frontend-libs-21` as source libraries consumed through TypeScript path
  aliases unless a publishable Angular library package is intentionally added.
- Move reusable shell behavior into `frontend-libs-21/layout`.
- Keep business pages and app-specific API endpoint catalogs in
  `kyc-frontend-21`.
- Keep generic reusable UI, icon, i18n, and validation helpers in
  `frontend-libs-21/shared`.
- Avoid adding Angular Material, Bootstrap, or Font Awesome to the new layout
  shell.

## Phase 1: Stabilize Workspace Files

### `kyc-frontend-21`

Create or restore the missing Angular workspace files:

- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `tsconfig.app.json`
- `tsconfig.spec.json`
- `proxy.conf.json`, if still needed

Use Angular 21-compatible dependencies:

- `@angular/*` at `^21.0.0`
- `@angular/build` at `^21.0.0`
- `@angular/cli` at `^21.0.0`
- `@angular/compiler-cli` at `^21.0.0`
- `typescript` at `~5.9.0`
- `vitest` at `^4.0.8`
- `@playwright/test`
- `@jsverse/transloco`

Remove Angular 19-era test/build dependencies:

- `@angular-devkit/build-angular`
- Karma packages
- Jasmine packages

### `frontend-libs-21`

Keep it source-only initially.

Update `frontend-libs-21/tsconfig.json` so it does not point back to the old
`../frontend` app through `@app-core/*`.

## Phase 2: Rewire `kyc-frontend-21` To `frontend-libs-21`

Update `kyc-frontend-21/tsconfig.json` path aliases:

```json
{
  "paths": {
    "@nexacore/api-common": ["../frontend-libs-21/api-common/src/public-api.ts"],
    "@nexacore/api-common/*": ["../frontend-libs-21/api-common/src/lib/*"],
    "@nexacore/auth": ["../frontend-libs-21/auth/src/public-api.ts"],
    "@nexacore/auth/*": ["../frontend-libs-21/auth/src/lib/*"],
    "@nexacore/layout": ["../frontend-libs-21/layout/src/public-api.ts"],
    "@nexacore/layout/*": ["../frontend-libs-21/layout/src/lib/*"],
    "@nexacore/shared": ["../frontend-libs-21/shared/src/public-api.ts"],
    "@nexacore/shared/*": ["../frontend-libs-21/shared/src/lib/*"]
  }
}
```

Update `kyc-frontend-21/angular.json` asset paths:

- from `../frontend-libs/...`
- to `../frontend-libs-21/...`

## Phase 3: Upgrade Angular Build/Test Configuration

Update `kyc-frontend-21/angular.json`:

- Use `@angular/build:application`.
- Use `@angular/build:dev-server`.
- Use `@angular/build:unit-test`.
- Configure Vitest as the test runner.
- Remove Karma-specific test options.
- Remove Zone.js from polyfills once zoneless bootstrap is in place.
- Remove Bootstrap and Font Awesome global style/script entries from the new
  shell path.

Add Playwright config for browser-level shell checks.

## Phase 4: Port The Reference Layout Into `frontend-libs-21/layout`

Port reusable layout behavior from `frontendApplications/layout` into
`frontend-libs-21/layout`.

Reusable candidates:

- `HeaderComponent`
- `HeaderDropdownComponent`
- `RailNavComponent`
- `StatusBarComponent`
- `ThemeService`
- `RailStateService`
- `HeaderMenuService`
- `RailFlyoutService`
- `DirectionService`
- theme models
- navigation models

The shared layout library should expose a shell component that can host app
routes through `RouterOutlet`.

Suggested public exports:

```ts
export * from './lib/layout-shell/layout-shell.component';
export * from './lib/header/header.component';
export * from './lib/rail-nav/rail-nav.component';
export * from './lib/status-bar/status-bar.component';
export * from './lib/services/theme.service';
export * from './lib/services/direction.service';
```

Keep dashboard and KYC/person pages in `kyc-frontend-21`; do not move business
screens into the shared layout library.

## Phase 5: Move Shared Icons And Tokens Deliberately

Recommended split:

### `frontend-libs-21/shared`

- Generic `IconComponent`
- Icon registry
- Common validation and UI helpers
- Shared Transloco utilities, if needed

### `frontend-libs-21/layout`

- Shell-specific components
- Shell-specific services
- Navigation models
- Layout SCSS that consumes shared tokens

### `kyc-frontend-21`

- App-specific theme imports
- App-specific page styles
- App-specific route and feature configuration

Do not keep Font Awesome as a dependency for the new shell. Replace icon class
usage with registry-backed icon names as the affected components are migrated.

## Phase 6: Replace Old i18n With Transloco

Current copied code uses a custom `I18nService` and `TranslatePipe`.

Target behavior:

- App bootstrap provides Transloco.
- Shared shell components use `TranslocoModule` or `TranslocoService`.
- Translation files live under `src/assets/i18n`.
- Shared common translations may remain under
  `frontend-libs-21/shared/src/lib/i18n/translations` if both apps need them.
- `DirectionService` controls RTL/LTR behavior for Arabic and other RTL
  languages.

Migration approach:

1. Add Transloco to `kyc-frontend-21` bootstrap.
2. Port `DirectionService` from the reference layout.
3. Update layout shell text to Transloco keys.
4. Migrate old `TranslatePipe` usages gradually after the shell builds.

## Phase 7: Remove Material/Bootstrap/Font Awesome From Shared Core

Do this in small steps.

1. Replace `MatSnackBar` in `api-common` with a notification abstraction.
2. Provide the concrete notification implementation from the app.
3. Replace Font Awesome inputs in shared UI components with icon registry names.
4. Replace Bootstrap-dependent markup/styles component by component.
5. Remove global Bootstrap and Font Awesome CSS only after migrated screens no
   longer require them.

This keeps the build moving while the visual system is modernized.

## Phase 8: Update App Bootstrap And Routes

Update `kyc-frontend-21/src/main.ts` or introduce `app.config.ts`:

- `provideZonelessChangeDetection()`
- `provideRouter(routes)`
- `provideHttpClient(withInterceptors([...]))`
- `provideTransloco(...)`

Remove:

- `BrowserAnimationsModule`
- `MatSnackBarModule`
- Zone.js bootstrap assumptions
- custom i18n initializer once Transloco is active

Update routes:

- Keep public auth routes from `@nexacore/auth`.
- Keep protected app routes under the new shared layout shell.
- Preserve the default redirect to `dashboard`.
- Keep KYC/person/profile pages app-owned.

## Phase 9: Upgrade Auth And API Boundaries

`auth` currently depends on old layout services.

Required changes:

- Replace direct dependency on old `LayoutService` with a smaller auth/session
  state contract.
- Keep token storage and route guard behavior in `auth`.
- Keep API response handling and HTTP interceptors in `api-common`.
- Keep visual notifications outside `api-common` behind an interface.
- Avoid logging raw tokens, authorization headers, OTPs, passwords, or full PII.

## Phase 10: Verification Strategy

Run checks in this order:

```bash
cd frontendApplications/layout
npm run build
```

```bash
cd frontendApplications/kyc-frontend-21
npm install
npm run build
npm test
```

Add Playwright smoke checks for:

- login route renders
- protected shell route renders when authenticated state is mocked
- dashboard route loads inside the shell
- rail navigation opens
- header dropdown opens
- language selector changes direction for Arabic
- theme selector changes body theme state

Run e2e checks after the shell is wired:

```bash
npm run test:e2e
```

## Milestones

### Milestone 1: Buildable Angular 21 App

- `kyc-frontend-21` has complete workspace files.
- Dependencies resolve with Angular 21.
- TypeScript aliases point to `frontend-libs-21`.
- App builds with existing pages, even if visual migration is incomplete.

### Milestone 2: Shared Angular 21 Layout Shell

- `frontend-libs-21/layout` exports the new shell.
- Shell uses CDK overlays, signals, custom icons, and design tokens.
- `kyc-frontend-21` renders routes inside the new shell.

### Milestone 3: Transloco And Direction

- Transloco is active in the app.
- Header language selector works.
- Arabic sets RTL direction.
- Old custom `TranslatePipe` is removed from migrated shell code.

### Milestone 4: Remove Legacy UI Dependencies From Shell

- New shell no longer depends on Bootstrap, Font Awesome, or Angular Material.
- `api-common` no longer directly injects `MatSnackBar`.
- Shell build and unit tests pass.

### Milestone 5: App Page Modernization

- Dashboard, person, KYC, and profile pages are updated to match the new visual
  system.
- Shared form controls no longer require Font Awesome or Bootstrap.
- Playwright smoke coverage passes.

## Risks

- Migrating shell, auth, API interceptors, i18n, and all pages at once will make
  failures hard to isolate.
- Removing Bootstrap/Font Awesome too early can break many existing app pages.
- `api-common` currently has UI responsibility through snackbar usage; this
  should be separated before Material is removed.
- `auth` and `layout` are coupled through old layout services; this coupling must
  be reduced before the old layout can be fully replaced.
- `kyc-frontend-21` must be made into a complete workspace before reliable
  builds are possible.

## Recommended First Implementation Batch

1. Add missing workspace files to `kyc-frontend-21`.
2. Convert `kyc-frontend-21` build/test config to Angular 21.
3. Point `kyc-frontend-21` to `frontend-libs-21`.
4. Ensure `npm install` and `npm run build` can run.
5. Port only the reusable layout shell from `frontendApplications/layout` into
   `frontend-libs-21/layout`.
6. Wire the app routes into the new shell.

After this batch, continue with i18n, auth decoupling, notification abstraction,
and page-by-page visual modernization.
