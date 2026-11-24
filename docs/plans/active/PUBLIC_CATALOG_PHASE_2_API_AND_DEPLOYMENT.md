# Public Catalog Phase 2 API and Deployment Foundation

## Contract boundary

Public endpoints return presentation DTOs only. They must not expose database
entities, numeric tenant identifiers, publication audit fields, draft content,
or administrative authorization data. Administrative endpoints live below
`/api/v1/catalog/admin/**`, return separate DTOs, and require catalog privileges.

The foundation endpoint is `GET /api/v1/public/site?lang=en`. It now returns the
complete `CatalogSiteView` contract: site identity, placeholder-safe logo,
locales, hierarchical navigation, hierarchical category navigation, contact,
social links, and default SEO. All data-backed fields are selected only from
the resolved tenant's published rows; English is the required fallback.

An abbreviated response is:

```json
{
  "siteKey": "tenant-code",
  "hostname": "catalog.example.com",
  "name": "Example Catalog",
  "logo": { "id": "site-logo", "kind": "IMAGE", "url": "/assets/catalog/placeholder.svg", "alternativeText": "Example Catalog" },
  "defaultLocale": "en",
  "supportedLocales": ["en", "bn"],
  "navigation": [],
  "categoryNavigation": [],
  "contact": { "email": "sales@example.com", "phone": "+880...", "address": "Dhaka" },
  "socialLinks": [],
  "defaultSeo": { "title": "Example Catalog", "description": "...", "canonicalPath": "/" }
}
```

`GET /api/v1/catalog/admin/context` is protected by tenant-scoped privilege
`12010100101`. Content management will use the registered create, update,
publish, delete, view, and search actions. Public routes are individually
allowlisted; `/api/v1/public/**` and `/api/v1/catalog/**` are intentionally not
wildcard allowlists.

## Tenant and media policy

The existing verified tenant-domain resolver is authoritative. The edge proxy
preserves the original `Host` header. Unknown, inactive, unverified, or
ambiguous hostname mappings fail before catalog controllers execute. Browser
headers and query parameters never select a tenant.

Catalog media uses the `catalog` object namespace and the bounded public path
`/api/v1/public/media`. Object storage credentials, internal object keys, and
unpublished assets must never be returned by public APIs. Actual delivery and
signed/public object policy are implemented with the Phase 3 media aggregate.

## Deployment

`nexacore-catalog-renderer` runs Angular SSR internally on port 4000.
`nexacore-catalog-frontend` exposes port 4400 through Nginx, sends `/api/` to
the backend, and sends all other requests to the SSR renderer. Both proxy paths
preserve the hostname required for multi-site resolution.

The browser uses `HttpCatalogContentSource`; its site read is authoritative from
the public backend API. Other content-source methods explicitly delegate to the
fixture source until their Phase 3 endpoints exist. Server prerender uses the
fixture provider for deterministic backend-independent builds and disables HTTP
transfer caching, so the hydrated browser still loads the authoritative site.

## Database bootstrap and operations

Create the development database once before backend startup:

```bash
createdb -h localhost -p 5433 -U postgres catalog_db
```

The backend then applies `db/migration/catalog` through the dedicated
`catalogFlyway` bean. Configuration uses `CATALOG_DB_JDBC_URL`,
`CATALOG_DB_USERNAME`, and `DB_CATALOG_PASSWORD`. Docker Compose supplies local
defaults for these settings. The datasource is included in Actuator health and
the encrypted platform backup set under logical target `catalog`.

Operational probes are available without tenant-host resolution at
`/actuator/health/liveness` and `/actuator/health/readiness`; other Actuator
endpoints remain authenticated. The readiness result includes Spring Boot's
composite database health contributor, including `catalogDataSource`. Compose
also checks the catalog SSR renderer at `/healthz` and the Nginx edge at
`/healthz`.

For a backend started directly on the host, the default JDBC URL is
`jdbc:postgresql://localhost:5433/catalog_db`. For Compose, set
`CATALOG_DB_JDBC_URL=jdbc:postgresql://host.docker.internal:5433/catalog_db`.
Set `DB_CATALOG_PASSWORD` through the local environment or secret manager; do
not put production credentials in Compose or application properties.

Flyway owns the schema. Do not enable Hibernate schema creation or edit V1 after
deployment; subsequent changes require the next catalog migration version.
