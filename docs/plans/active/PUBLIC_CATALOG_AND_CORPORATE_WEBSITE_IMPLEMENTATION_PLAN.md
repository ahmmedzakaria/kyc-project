# Public Catalog and Corporate Website Implementation Plan

## Document control

- Status: proposed
- Owner: unassigned
- Created: 2026-09-15
- Review date: 2026-09-29
- Target architecture: NexaCore modular monolith, Angular 21 applications, PostgreSQL, MinIO, Redis, Keycloak
- Reference capability set: iNetworkBD-style public product, service, company, media, news, and enquiry website

## 1. Objective

Deliver a production-ready public corporate website and product catalog on the
existing NexaCore platform without weakening the identity, tenant, privilege,
or KYC domain boundaries.

The baseline release is a catalog and lead-generation system. It is not an
ecommerce implementation. Products may be published with descriptive and
technical information, downloadable documents, and a request-a-quote action,
but the baseline does not include customer accounts, inventory, carts,
checkout, payments, orders, invoices, delivery, or returns.

## 2. Outcomes

The completed implementation will provide:

1. A public, responsive, indexable Angular website.
2. Hierarchical product navigation, filtering, search, product detail pages,
   media, specifications, and downloadable documents.
3. Managed corporate pages, services, partners, clients, team profiles,
   testimonials, galleries, videos, news, contact details, and legal pages.
4. Product quote requests, general enquiries, and newsletter subscriptions.
5. An authenticated administration area governed by NexaCore privileges.
6. Role-controlled draft, publish, unpublish, and archive controls with an
   audit trail.
7. Tenant-owned multi-site operation with trusted hostname-based tenant
   resolution.
8. Observable, backed-up, deployable services consistent with the existing
   Docker Compose topology.

## 3. Scope

### 3.1 Included in the baseline

- Public site shell, header, responsive category navigation, footer, search,
  metadata, sitemap, robots policy, canonical URLs, and error pages.
- Home page composed from managed content blocks.
- About/company profile and management/team pages.
- Product categories with arbitrary parent/child depth.
- Product list, product detail, related products, brands, technical
  specifications, image gallery, PDFs, and enquiry call to action.
- Service and solution pages.
- Partner and client showcases.
- Testimonials.
- Photo, certification, and externally hosted video galleries.
- News/article listing and detail.
- Contact/location details and general enquiry form.
- Newsletter subscription, verification-ready subscription state, suppression,
  and unsubscribe support.
- CMS/catalog administration within `system-frontend-21`.
- MinIO-backed media and Redis-backed public read caching.
- English and Bengali-ready content architecture. Arabic/RTL compatibility is
  retained where shared platform components already support it, but Arabic
  content population is not required for the baseline.

### 3.2 Explicitly excluded

- Scraping or copying copyrighted content or media from the reference website.
- Customer login or registration.
- Prices personalized by customer or contract.
- Stock, warehouse, procurement, cart, payment, order, invoice, delivery,
  return, or refund domains.
- Native video transcoding or streaming; use external video embeds initially.
- Elasticsearch/OpenSearch in the first release.
- Automatic creation of `KycPerson`, `AuthUser`, organization membership, or
  authorization scope from a public submission.

### 3.3 Future extensions

- Formal quotation generation and sales assignment.
- CRM integration.
- Regional price lists and inventory availability.
- Full commerce capability as a separately approved program.
- Dedicated search infrastructure when catalog size or relevance requirements
  exceed PostgreSQL full-text search.

## 4. Mandatory architecture decisions

The decisions recorded below are authoritative for implementation. No phase
may silently choose a different model. Changes require an explicit update to
this plan and the corresponding architecture decision record before schema or
application work proceeds.

### ADR-CATALOG-001: site tenancy

Decision: implement multi-site mode. Every content and catalog aggregate is
tenant-owned, and a trusted hostname mapping resolves the tenant for public
requests.

Every tenant-owned table and every repository operation, including direct-ID
and slug reads, search, writes, archive operations, media access, previews, and
exports, must include the tenant predicate. A branch or business identifier
must not be added unless there is an explicit publishing requirement at that
level. Unknown, inactive, or ambiguous hostnames must fail closed. Public
tenant context must never be accepted from a caller-controlled tenant header.

### ADR-CATALOG-002: persistence boundary

Recommendation: create a dedicated `catalog_db` datasource and Flyway history.
This keeps public content/catalog lifecycles out of Auth, KYC, GIS, Log, and
System persistence. Using `system_db` for an accelerated prototype requires an
explicit time-bounded exception and migration plan.

### ADR-CATALOG-003: public rendering strategy

Recommendation: create `frontendApplications/catalog-frontend-21` with Angular
SSR or route prerendering. At minimum, home, category, product, service, news,
about, contact, and legal routes must return useful content without requiring
client-side JavaScript.

### ADR-CATALOG-004: publication workflow

Decision: implement simple role-controlled draft/publish transitions for the
MVP. Integration with the existing workflow module and author/reviewer
separation is deferred.

Model publication state and revision metadata so later workflow integration
does not require a data redesign. Only users holding the applicable content
management and publication privileges may perform each transition.

### ADR-CATALOG-005: localized content persistence

Decision: use aggregate-specific translation tables for translated fields.
Keep operational fields, relationships, publication state, and audit metadata
on the stable aggregate. Do not store translations in unvalidated free-form
JSON.

The translation model must support tenant- and locale-aware uniqueness,
fallback, publication, search, sitemap links, and later addition of a language
without a schema redesign. English content is required for launch; Bengali
content may be completed incrementally.

## 5. Architecture

### 5.1 Backend boundary

Add `com.nexacore.catalogmodule` as a Spring Modulith application module.
Organize it by feature while keeping persistence private:

```text
catalogmodule/
├── api/                    # stable cross-module contracts
├── config/                 # catalog datasource/JPA/Flyway configuration
├── catalog/                # categories, products, brands, specifications
├── content/                # pages, services, news, testimonials, people
├── media/                  # metadata and links to storage objects
├── engagement/             # enquiries, quote requests, subscriptions
├── publication/            # states, scheduling, cache invalidation
├── publicapi/              # anonymous read/submission controllers
└── privilege/              # ModulePrivilegeProvider implementation
```

Other modules must use contracts from `catalogmodule.api`; they must not access
catalog repositories or entities directly. `catalogmodule` may consume stable
interfaces from `servicesmodule` for storage, email, caching, and messaging.

### 5.2 Frontend boundaries

Use two applications:

- `catalog-frontend-21`: anonymous public website, SSR/prerender, no dependency
  on the authenticated operational layout.
- `system-frontend-21`: authenticated catalog and CMS administration, using the
  existing auth, navigation, route-privilege, form, table, and upload patterns.

Reusable presentation-neutral models and API clients may live in
`frontend-libs-21`. Public visual components should remain in the public app so
marketing styling does not leak into operational applications.

### 5.3 Request paths

```text
Browser / crawler
    -> catalog-frontend-21
    -> /api/public/catalog/** and /api/public/content/**
    -> catalogmodule
    -> catalog_db + Redis + MinIO

Authenticated administrator
    -> system-frontend-21
    -> /api/catalog/admin/**
    -> JWT/Keycloak + privilege/access filters
    -> catalogmodule
```

### 5.4 Publication states

Use the following state machine:

```text
DRAFT -> PUBLISHED -> ARCHIVED
  ^          |
  +----------+ (new revision or unpublish)
```

Only `PUBLISHED` records whose `publish_at` is absent or in the past and whose
`unpublish_at` is absent or in the future may appear through public APIs.
Unpublishing must invalidate affected cache entries and remove URLs from the
next sitemap build.

## 6. Data model

All persistent tables use the `catalog_` prefix and include `created_at`,
`updated_at`, `created_by`, and `updated_by`. All owned records contain a
non-null `tenant_id`, and all unique constraints include that tenant key where
appropriate.

### 6.1 Core catalog

- `catalog_categories`: id, tenant/site key, parent_id, name, slug,
  description, image media ID, display order, publication fields.
- `catalog_brands`: id, name, slug, logo media ID, website, display order,
  publication fields.
- `catalog_products`: id, category_id, brand_id, name, slug, short and rich
  descriptions, model/SKU, quote-only flag, featured flag, SEO fields,
  publication fields.
- `catalog_product_categories`: optional many-to-many secondary category links;
  one canonical category remains on the product for breadcrumbs and URLs.
- `catalog_product_specifications`: product_id, group name, key, value, unit,
  display order.
- `catalog_product_media`: product_id, media_id, role, alternative text,
  display order.
- `catalog_product_documents`: product_id, media_id, document type, label,
  locale, display order.
- `catalog_related_products`: product_id, related_product_id, display order.

Do not store category ancestry as a caller-supplied path. Enforce cycle
prevention in the service and database-safe update logic. Slugs are immutable
after publication unless a redirect from the old path is created.

### 6.2 Managed content

- `catalog_pages`: stable page key, title, slug, rich body, SEO and publication
  fields.
- `catalog_page_sections`: page ID, section type, structured JSON payload,
  display order. Validate payloads against an allowlisted section schema.
- `catalog_services`: title, slug, summary, body, media and publication fields.
- `catalog_articles`: title, slug, excerpt, body, author display metadata,
  hero media, tags, publication fields.
- `catalog_tags` and `catalog_article_tags`.
- `catalog_partners`, `catalog_clients`, `catalog_team_members`, and
  `catalog_testimonials` with media, links, display order, and publication
  fields.
- `catalog_gallery_items`: type, media/embed URL, caption, alternative text,
  display order, publication fields.
- `catalog_site_settings`: contact data, social links, default SEO data,
  supported locales, theme/branding metadata.
- `catalog_redirects`: old path, target path, HTTP status, active dates.

Rich text must be sanitized on write and rendered with a strict allowlist.
Never allow raw scripts, event handlers, iframes outside approved video hosts,
or arbitrary style injection.

### 6.3 Engagement

- `catalog_enquiries`: type, product ID when applicable, normalized contact
  fields, subject, message, source URL, consent version, status, assignment
  metadata, timestamps.
- `catalog_enquiry_events`: immutable status/assignment/note history.
- `catalog_newsletter_subscriptions`: normalized email, state, locale, source,
  verification token hash, verified/unsubscribed timestamps, consent version.

Do not persist raw CAPTCHA tokens, passwords, authentication tokens, or
unnecessary device fingerprints. Define and enforce retention periods for
enquiries and rejected/spam submissions.

### 6.4 Media

Store object bytes through `servicesmodule.fileservice` and keep catalog-owned
metadata in `catalog_media`:

- storage object identifier, MIME type, size, checksum, width/height
- original filename for administration only
- public delivery path or asset key
- alternative text and focal point
- lifecycle state and audit fields

Use a catalog-specific bucket or object prefix. Do not expose MinIO management
credentials or internal endpoints. Validate signatures, MIME types, file size,
image dimensions, and PDF policy on upload. Deleting a product must not delete
a shared media object until reference checks and retention rules permit it.

## 7. API contract

Version new endpoints under `/api/v1` unless the repository establishes a
different API-wide versioning decision before implementation.

### 7.1 Anonymous read APIs

```text
GET /api/v1/public/site
GET /api/v1/public/navigation
GET /api/v1/public/categories
GET /api/v1/public/categories/{slug}
GET /api/v1/public/products?category=&brand=&q=&page=&size=&sort=
GET /api/v1/public/products/{slug}
GET /api/v1/public/services
GET /api/v1/public/services/{slug}
GET /api/v1/public/pages/{slug}
GET /api/v1/public/articles?page=&size=&tag=
GET /api/v1/public/articles/{slug}
GET /api/v1/public/gallery?type=&page=&size=
GET /api/v1/public/search?q=&type=&page=&size=
GET /api/v1/public/sitemap
```

Public DTOs must expose only published fields and public asset URLs. They must
not reuse administrative entities or DTOs containing internal IDs, audit
actors, unpublished content, storage keys, or tenant administration metadata.

### 7.2 Anonymous command APIs

```text
POST /api/v1/public/enquiries
POST /api/v1/public/quote-requests
POST /api/v1/public/newsletter/subscriptions
POST /api/v1/public/newsletter/verify
POST /api/v1/public/newsletter/unsubscribe
```

Apply Bean Validation, normalized inputs, idempotency/duplicate handling,
per-IP and per-address throttles, bot protection, generic responses that avoid
address enumeration, and bounded message sizes.

### 7.3 Administrative APIs

Provide paged CRUD, ordered-reorder, preview, publication, revision, and media
operations under `/api/v1/catalog/admin/**`. Use optimistic locking on editable
aggregates. Destructive operations default to archive; hard deletion is a
separate high-privilege action and must reject referenced records.

Generate and commit an OpenAPI contract or verify generated OpenAPI in tests.
Frontend API models must be generated from or checked against this contract to
prevent drift.

## 8. Authorization and security

### 8.1 Privileges

Register at least:

```text
CATALOG_CATEGORY_VIEW
CATALOG_CATEGORY_MANAGE
CATALOG_PRODUCT_VIEW
CATALOG_PRODUCT_MANAGE
CATALOG_MEDIA_MANAGE
CATALOG_CONTENT_VIEW
CATALOG_CONTENT_MANAGE
CATALOG_CONTENT_PUBLISH
CATALOG_ENQUIRY_VIEW
CATALOG_ENQUIRY_MANAGE
CATALOG_SUBSCRIBER_VIEW
CATALOG_SUBSCRIBER_EXPORT
CATALOG_SETTINGS_MANAGE
```

Expose them through a `ModulePrivilegeProvider` and register the matching API
definitions. Administrative repository queries must include the applicable
tenant predicate; controllers must not fetch cross-tenant data and filter it
in memory.

### 8.2 Public-route policy

Permit only the exact anonymous endpoints. Do not permit a broad
`/api/v1/catalog/**` pattern because that would include administration.
Submission endpoints remain unauthenticated at Spring Security level but are
protected by throttling, CAPTCHA, validation, and request-size limits.

### 8.3 Web security

- Apply a restrictive CSP compatible with explicitly approved analytics and
  video hosts.
- Add HSTS in production, `X-Content-Type-Options`, frame restrictions, and a
  referrer policy.
- Use same-origin API proxying where practical; do not broaden CORS globally.
- Sanitize managed HTML and validate outbound redirects and external links.
- Protect SSR from server-side request forgery; SSR must call a configured
  internal API origin, never a hostname supplied by the browser.
- Keep secrets environment-driven and out of source-controlled content.
- Log security-relevant admin actions without logging enquiry message bodies,
  email verification tokens, or secrets.

## 9. Search and SEO

### 9.1 Search

Start with PostgreSQL full-text search and normalized prefix matching over
published products, categories, services, and articles. Maintain a weighted
search vector through controlled application updates or a database trigger.
Use stable secondary ordering to make pagination deterministic.

Search must:

- apply tenant and publication predicates in SQL;
- cap query length and page size;
- escape user input and use parameters;
- return a typed, compact result DTO;
- cache only safe popular reads, not arbitrary unbounded queries;
- record aggregate query metrics without retaining sensitive search text by
  default.

### 9.2 SEO acceptance requirements

- Server-rendered or prerendered title, description, canonical URL, Open Graph,
  and Twitter metadata.
- Product and article structured data where content qualifies.
- XML sitemap split by content type when necessary.
- `robots.txt` excludes admin, preview, and non-production environments.
- Permanent redirects for changed published slugs.
- Locale alternates only when an equivalent translated page exists.
- Semantic headings, accessible names, useful image alt text, and breadcrumb
  markup.
- Public 404 and 410 behavior returns the correct HTTP status under SSR.

## 10. Frontend implementation

### 10.1 Public application

Scaffold `catalog-frontend-21` using the repository's Angular 21 conventions.
Required route groups:

```text
/
/about
/products
/products/:categorySlug
/product/:productSlug
/services
/services/:serviceSlug
/clients
/partners
/gallery
/news
/news/:articleSlug
/contact
/privacy
/terms
```

Implement loading, empty, error, not-found, and degraded-media states for every
data-backed page. Navigation must work by keyboard and touch; the category
mega-menu must collapse into an accessible mobile navigation pattern.

Do not reproduce the reference site's placeholder content or zero prices.
Products with no public price display `Request a quote`.

### 10.2 Administration

Add a Catalog navigation group to `system-frontend-21` with pages for:

- dashboard/content health;
- categories and ordering;
- products, specifications, related items, media, and documents;
- pages and home-page sections;
- services, articles, tags, team, partners, clients, testimonials, gallery;
- enquiries and event history;
- newsletter subscribers;
- site, SEO, redirect, and domain settings.

Route guards and server-side privileges are both mandatory. The UI hiding a
button is not authorization. Unsaved-change protection, optimistic-lock
conflict handling, preview, and publish confirmation are required.

### 10.3 Localization and accessibility

- Use Transloco and aggregate-specific translation tables as established by
  ADR-CATALOG-005.
- English is required for launch; Bengali content must be supported without a
  schema migration.
- Meet WCAG 2.2 AA for public templates and primary admin workflows.
- Test keyboard navigation, focus management, visible focus, contrast, form
  errors, reduced motion, zoom, and screen-reader labels.

## 11. Delivery phases

Each phase ends with demonstrable acceptance evidence. Early phases deliberately
prioritize work that does not depend on backend persistence or completed APIs.
The public experience is first built against typed fixture data, then connected
to backend contracts through replaceable repository/API adapters. Do not build
all CRUD screens before proving the integrated public vertical slice.

### Phase 0: discovery, content model, and experience definition — 3 to 5 working days

Implementation status: completed for review on 2026-11-23. The experience
definition is recorded in
[`PUBLIC_CATALOG_PHASE_0_EXPERIENCE_DEFINITION.md`](PUBLIC_CATALOG_PHASE_0_EXPERIENCE_DEFINITION.md),
and the shared contracts, fixtures, route manifest, and design tokens are in
`frontendApplications/frontend-libs-21/projects/catalog`.

- Inventory approved brand assets and authoritative content.
- Define the public information architecture, route map, navigation hierarchy,
  content types, field inventory, responsive breakpoints, and user journeys.
- Produce wireframes for every launch route and agree the visual direction,
  typography, color tokens, spacing, imagery rules, and component inventory.
- Define TypeScript view models and representative fixture datasets for site
  settings, navigation, categories, products, services, articles, galleries,
  and localized content.
- Establish accessibility, SEO, performance, availability, and content-quality
  targets.
- Validate the approved multi-site hostname-resolution model conceptually
  against existing tenant/domain controls; detailed backend integration is
  deferred to Phase 2.
- Confirm rendering strategy, public domain topology, CAPTCHA provider, and
  analytics provider. Publication and localization follow ADR-CATALOG-004 and
  ADR-CATALOG-005.

Exit criteria:

- ADR-CATALOG-001 through ADR-CATALOG-005 are approved.
- Launch content owner and administrator roles are named.
- Route map, wireframes, design tokens, typed view models, fixture scenarios,
  and content workbook are reviewed.
- No frontend-blocking content, brand, or external-provider decision is
  unknown.

### Phase 1: public frontend foundation and fixture-backed experience — 6 to 9 working days

Implementation status: completed for review on 2026-11-23. The SSR application
is in `frontendApplications/catalog-frontend-21`, consumes
`@nexacore/catalog`, and is documented in
[`PUBLIC_CATALOG_PHASE_1_FRONTEND_FOUNDATION.md`](PUBLIC_CATALOG_PHASE_1_FRONTEND_FOUNDATION.md).

- Scaffold `catalog-frontend-21` with Angular SSR/prerender support, locale
  routing, environment configuration, testing, linting, and an API-adapter
  boundary that can initially read typed fixtures.
- Implement design tokens, typography, page container, header, accessible
  desktop/mobile navigation, breadcrumb, footer, language selector, loading,
  empty, error, not-found, and degraded-media states.
- Build fixture-backed home, about, product category, product list, product
  detail, services, clients, partners, gallery, news, contact, privacy, and
  terms templates.
- Implement responsive product cards, category navigation, filters, pagination,
  specification groups, document links, related products, article cards,
  galleries, and `Request a quote` entry points without submitting data.
- Add fixture-backed metadata, canonical URL, structured-data, sitemap, and
  robots generation abstractions.
- Add keyboard, responsive, component, accessibility, and primary Playwright
  navigation coverage.
- Use local licensed placeholders or synthetic fixtures only; do not copy the
  reference website's content or assets.

Exit criteria:

- Every launch route is navigable using representative fixture content without
  a running backend, PostgreSQL, Redis, MinIO, or Keycloak instance.
- Layouts pass agreed responsive and keyboard checks, and required page states
  are visibly reviewable.
- SSR/prerender output contains meaningful fixture-backed HTML and metadata.
- The fixture adapter can be replaced without changing page components.
- Public frontend build, unit tests, and fixture-backed browser journeys pass.

### Phase 2: backend and deployment foundation — 5 to 8 working days

- Finalize API contracts from the validated frontend view models and document
  public versus administrative DTO boundaries.
- Declare `catalogmodule` and update Modulith documentation and tests.
- Present the proposed `catalog_db` Flyway migration for explicit user review;
  create or modify migration scripts only after approval as required by the
  repository instructions.
- After migration approval, configure `catalog_db`, JPA, transaction manager,
  Flyway, environment variables, local bootstrap instructions, backup
  inclusion, and health checks; create the audit-complete tenant-owned schema.
- Register catalog privileges and administrative API definitions.
- Implement trusted hostname-to-tenant resolution with inactive, unknown, and
  ambiguous hosts failing closed.
- Configure the catalog media namespace and public asset-delivery policy.
- Add exact public route patterns, administrative authentication, rate-limit
  foundations, and security tests.
- Add the public frontend deployment service and Nginx/proxy configuration.

Exit criteria:

- Backend and frontend agree on versioned contracts without leaking entities or
  administrative fields into public DTOs.
- Clean approved migrations succeed and repeat startup is idempotent.
- Modulith verification passes.
- Hostname resolution returns exactly one active tenant or fails closed.
- Anonymous users can reach only exact public endpoints; authenticated users
  without catalog privileges cannot reach administration endpoints.
- `docker compose config` succeeds for the added deployment configuration.

### Phase 3: integrated catalog vertical slice — 6 to 9 working days

- Implement tenant-owned category, category-translation, product,
  product-translation, product-media, product-document, specification, and
  related-product aggregates.
- Implement public navigation, category, product list, product detail, media,
  document, metadata, and sitemap APIs.
- Replace fixture adapters for the catalog routes with API adapters while
  retaining fixtures for isolated tests and Storybook-like review scenarios.
- Implement administration create/edit/preview/publish/unpublish/archive for
  categories and products in `system-frontend-21`.
- Add MinIO media delivery, image variants, alternative text, PDF download,
  Redis caching, and publication-driven cache invalidation.
- Seed a small synthetic demonstration catalog through supported application
  paths; do not copy reference content.

Exit criteria:

- An authorized administrator can create, preview, publish, update, unpublish,
  and archive a tenant-owned product.
- Draft, archived, expired, and cross-tenant content cannot be retrieved through
  lists, search candidates, direct IDs, guessed slugs, media, or preview paths.
- A published update becomes visible without stale-cache errors.
- Integrated category and product URLs preserve the validated Phase 1 UX and
  render indexable content with correct metadata.

### Phase 4: managed content, engagement, and search — 7 to 11 working days

- Implement pages/sections, services, articles/tags, partners, clients, team,
  testimonials, gallery, site settings, and redirects.
- Connect the corresponding Phase 1 public templates and add administration.
- Implement safe structured page sections instead of accepting unrestricted
  page-builder code.
- Add preview tokens that are short-lived, hashed at rest if persisted,
  tenant-bound, content-specific, and never expose general admin access.
- Implement general enquiry, quote request, enquiry history/status, newsletter
  subscribe/verify/unsubscribe, and notification delivery.
- Add CAPTCHA, throttling, normalization, idempotency, retention, consent, and
  abuse-monitoring controls.
- Implement PostgreSQL search with filters and deterministic pagination.
- Add administration queues and controlled subscriber export.

Exit criteria:

- All launch routes are content-managed, and archived or scheduled content
  observes publication windows.
- Unsafe HTML and unapproved embeds are rejected or sanitized; changed
  published slugs retain working permanent redirects.
- Valid submissions persist once and notify configured recipients.
- Duplicate, automated, oversized, and malformed submissions are handled
  without leaking account/subscriber existence.
- Product quote requests retain the referenced product snapshot or stable ID.
- Public search never returns draft, expired, archived, or cross-tenant content.

### Phase 5: hardening and launch — 5 to 8 working days

- Complete responsive, accessibility, browser, SEO, structured-data, security,
  and performance testing.
- Configure production domains, TLS, CSP, caching headers, analytics consent,
  email sender authentication, backups, monitoring, dashboards, and alerts.
- Import reviewed content through a repeatable validated process.
- Execute restore test, rollback rehearsal, smoke test, and editorial training.
- Freeze content, run launch checklist, deploy, validate production indexing
  controls, and monitor the launch window.

Exit criteria:

- All quality gates in section 13 pass.
- Backup restore and application rollback are demonstrated.
- Production contains no placeholder text, zero-price ambiguity, broken media,
  internal MinIO URLs, test subscribers, or draft content.
- Operations and content owners sign off.

Estimated baseline effort: 32 to 50 developer working days, excluding content
writing, translation, brand design, external-provider procurement, and formal
penetration testing. Parallel frontend/backend staffing may reduce elapsed
calendar time but does not remove dependency gates.

## 12. Migration and content onboarding

1. Create a content workbook containing source owner, rights status, locale,
   destination type, slug, publication state, SEO fields, and media references.
2. Accept only content and assets supplied or licensed by the business.
3. Build a repeatable importer using service-layer validation; do not write
   directly to production tables.
4. Import categories first, then brands/products, then corporate content and
   relationships.
5. Upload media through the storage abstraction and record checksums to prevent
   duplicates.
6. Generate an exception report for invalid parents, duplicate slugs, missing
   alt text, missing documents, unsafe HTML, and broken external embeds.
7. Run import in staging, obtain editorial approval, and rerun from a clean
   snapshot before production.

## 13. Verification and quality gates

### 13.1 Backend

- Unit tests for slugging, publication windows, category-cycle prevention,
  sanitization, enquiry normalization, subscriber state, and cache invalidation.
- Repository integration tests prove tenant and publication predicates on list,
  direct-ID/slug read, update, archive, media, search, and export operations.
- Security integration tests cover anonymous reads, anonymous commands,
  authenticated-but-unprivileged users, each management privilege, preview
  tokens, and cross-tenant attempts.
- Flyway tests cover clean install and upgrade from the last released schema.
- Modulith structural test verifies the new boundary.
- Run `cd backend && mvn test`.

### 13.2 Frontend

- Component tests for navigation, cards, filters, forms, rich content, preview,
  publish controls, and error states.
- Contract tests for public and admin API clients.
- Playwright journeys for browse/search/product enquiry, newsletter lifecycle,
  admin draft-publish, unpublish, and mobile navigation.
- Accessibility automation plus manual keyboard and screen-reader checks.
- Run builds and tests for `catalog-frontend-21`, `system-frontend-21`, and any
  changed shared libraries.

### 13.3 Non-functional targets

Confirm exact targets during Phase 0. Recommended launch gates:

- No critical/high dependency or application-security finding without an
  approved risk acceptance.
- Core Web Vitals evaluated on representative mobile hardware/network.
- Public cached read API p95 below 300 ms in the agreed load environment,
  excluding asset transfer and cold SSR startup.
- Enquiry submission p95 below 1 second while notification delivery runs
  asynchronously.
- No broken internal links, missing canonical tags, indexable preview/admin
  routes, or sitemap entries returning non-200 responses.
- WCAG 2.2 AA automated checks pass, followed by manual validation of critical
  journeys.

### 13.4 Deployment

- Run `docker compose config` after Compose/configuration changes.
- Verify health/readiness for backend, public frontend, PostgreSQL, Redis, and
  object storage dependencies.
- Confirm cache headers separately for hashed assets, public HTML, public JSON,
  and administrative responses.
- Verify backup includes `catalog_db` and the catalog media namespace, and test
  restoration of both to the same recovery point.

## 14. Observability and operations

- Metrics: public/admin request latency and errors, cache hit rate, search
  latency, publication count, enquiry acceptance/rejection, email delivery,
  subscriber transitions, media failures, SSR errors, and sitemap generation.
- Logs: correlation ID, resolved site/tenant, route, status, safe content ID,
  and authenticated actor for administration. Mask contact data and tokens.
- Traces: include backend, database, Redis, storage, and notification boundaries
  using existing OpenTelemetry configuration.
- Alerts: elevated public 5xx, failed migrations, storage unavailability,
  repeated notification failure, abnormal submission rejection, sitemap
  failure, and backup failure.
- Runbooks: publishing recovery, cache purge, compromised preview link, spam
  surge, asset replacement, database restore, media restore, and rollback.

## 15. Deployment and rollback strategy

1. Deploy additive database migrations before code that requires them.
2. Deploy backend with new public routes disabled by a feature flag or without
   public DNS exposure.
3. Deploy the public frontend to staging and warm critical SSR/cache paths.
4. Import and approve content.
5. Enable public traffic through a reversible proxy/DNS switch.
6. Monitor errors, latency, storage, email delivery, and submission abuse.

Application rollback must remain possible without reversing destructive schema
changes. Use expand-and-contract migrations and defer column/table removal to a
later release. Content rollback uses publication revisions or an explicit
unpublish action, not direct database modification.

## 16. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Public endpoints accidentally expose draft or tenant data | Critical | Separate DTOs, SQL predicates, exact route allowlist, direct-slug security tests |
| Angular client-only rendering weakens discovery | High | SSR/prerender, sitemap, canonical metadata, crawl validation |
| Rich text introduces XSS | Critical | Structured sections, server-side sanitizer, CSP, restricted embeds |
| Forms attract spam or exhaust email services | High | CAPTCHA, layered throttling, asynchronous delivery, quotas and alerts |
| Media exposes MinIO credentials/internal URLs | High | Storage abstraction, safe public delivery path, strict upload validation |
| Catalog datasource increases operational complexity | Medium | Standard datasource template, migration/health/backup/restore automation |
| Content project delays software launch | High | Content inventory in Phase 0, named owners, staging import and acceptance deadlines |
| Shared frontend changes destabilize operational apps | Medium | Keep public styling local; run all affected library and application builds |
| Commerce expectations enter the MVP implicitly | High | Enforce scope boundary and require a separate commerce architecture approval |

## 17. Definition of done

The baseline is complete only when:

- all included launch routes are implemented and populated with approved
  content;
- all public results are publication- and tenant-safe;
- administrators can manage the full lifecycle using privileges and audit
  history;
- public forms are validated, rate-limited, bot-protected, observable, and
  retention-controlled;
- SSR/prerender, canonical metadata, sitemap, redirects, and correct HTTP status
  behavior are verified;
- media is delivered without exposing storage internals;
- backend, affected frontend builds/tests, Compose validation, accessibility,
  security, performance, backup restore, and rollback gates pass;
- operating runbooks and editorial instructions are delivered;
- there are no unapproved changes to `KycPerson`, `AuthUser`, organization
  membership, or authorization-scope semantics;
- ecommerce remains absent unless separately approved.

## 18. First implementation backlog

The first pull requests should be small and ordered as follows:

1. Approve ADRs, content inventory, route map, design direction, and view-model
   contracts.
2. Scaffold the public SSR application with typed fixture and API adapter
   boundaries.
3. Implement design tokens, responsive shell, accessible navigation, footer,
   locale handling, and shared page states.
4. Deliver fixture-backed category -> product list -> product detail, metadata,
   and request-a-quote UX.
5. Deliver the remaining fixture-backed corporate templates and run public UX,
   responsive, accessibility, and SSR review.
6. Finalize versioned API contracts from the validated frontend models.
7. Declare the Modulith boundary, privilege provider, tenant resolver, and exact
   public/admin security boundaries.
8. Present the proposed catalog migration for explicit user approval; after
   approval, add datasource/Flyway configuration and migration smoke tests.
9. Implement category/product persistence, publication services, public APIs,
   and system-frontend administration.
10. Replace the catalog fixture adapter with the API adapter; add media variants,
    caching, invalidation, tenant-isolation tests, metadata, and sitemap coverage.
11. Review the integrated vertical slice before expanding into general CMS,
    engagement, and search features.
