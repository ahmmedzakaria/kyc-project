# Public Catalog Phase 1 Frontend Foundation

## Status

- Status: implemented for review
- Implemented: 2026-11-23
- Application: `frontendApplications/catalog-frontend-21`
- Shared contracts: `frontendApplications/frontend-libs-21/projects/catalog`
- Backend dependency: none

## Delivered experience

- Angular server-rendered public application with trusted-host SSR protection
  and 22 prerendered static locale routes; parameterized routes render on the
  server.
- English root routes and Bengali `/bn` routes.
- Skip link, utility bar, sticky header, accessible desktop/mobile navigation,
  locale switcher, breadcrumbs, footer, and reduced-motion behavior.
- Home, about, product index/category/detail, services/detail, clients, partners,
  gallery, news/article, contact, privacy, terms, and not-found routes.
- Product text filtering, category filtering, pagination, specifications,
  document empty state, related products, and quote-request routing.
- Fixture-only contact validation that transmits and persists no data.
- Loading, empty, no-result, not-found, local success, and degraded-image
  presentation.
- Responsive layouts for desktop and mobile breakpoints.
- Page titles, descriptions, canonical links, Open Graph fields, robots policy,
  JSON-LD structured data, sitemap path generation, and robots-text generation.
- Synthetic content and a local SVG fallback; no reference-site content or
  assets are included.

## Adapter boundary

Pages consume `CatalogFacade`, which depends on the abstract
`CatalogContentSource`. Phase 1 provides `FixtureCatalogContentSource`. A future
HTTP source can replace it through dependency injection without changing page
components.

The fixture tenant context accepts only `catalog.localhost` with the expected
site key. Production hostname resolution remains Phase 2 backend work.

## Verification evidence

```text
npx ng build catalog                         passed
npx ng test catalog --watch=false            6 tests passed
npm run build                                passed (browser/server bundles and 22 prerendered routes)
npm test                                     2 tests passed
npm run test:angular                         2 tests passed
npm run test:e2e                             desktop/mobile journeys passed
```

The built SSR server was fetched using the trusted fixture hostname. Initial
HTTP HTML contained:

- the route-specific `<title>`;
- a canonical link;
- JSON-LD structured data;
- the primary `h1`; and
- fixture sections such as Product categories.

## Deferred by plan

- Backend API and HTTP content-source adapter
- Trusted hostname-to-tenant persistence and resolution
- Database and Flyway work
- MinIO media delivery and Redis caching
- Administrative catalog screens
- Production enquiry/newsletter submission
- CAPTCHA and analytics providers
- Compose/Nginx production deployment service
