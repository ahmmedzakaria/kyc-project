# Public Catalog Phase 0 Experience Definition

## Status and ownership

- Status: implemented for review
- Implemented: 2026-11-23
- Business content owner: Tenant Content Administrator
- Publication owner: Tenant Catalog Publisher
- Technical owner: Catalog Application Team
- Source plan: [Public Catalog and Corporate Website Implementation Plan](PUBLIC_CATALOG_AND_CORPORATE_WEBSITE_IMPLEMENTATION_PLAN.md)

This document captures the Phase 0 information architecture, content model,
journeys, design direction, fixture scenarios, and acceptance evidence. It does
not authorize database migrations or backend implementation.

## Information architecture and route map

| Route | Purpose | Primary content | Main action |
|---|---|---|---|
| `/` | Establish proposition and guide discovery | Hero, featured categories/products, services, proof | Explore products |
| `/about` | Establish company credibility | Company profile, capabilities, team, memberships | Contact the team |
| `/products` | Browse the complete catalog | Category tree, filters, product cards | Select category/product |
| `/products/:categorySlug` | Browse one category | Breadcrumb, child categories, filters, products | View product |
| `/product/:productSlug` | Evaluate one product | Gallery, summary, specifications, documents, related products | Request a quote |
| `/services` | Discover solution capabilities | Service cards and delivery approach | View service |
| `/services/:serviceSlug` | Understand one service | Outcomes, scope, process, related products | Discuss a project |
| `/clients` | Provide customer evidence | Approved client logos and summaries | Contact sales |
| `/partners` | Establish supplier credentials | Approved partner logos and links | Explore products |
| `/gallery` | Show certifications and delivery evidence | Photos, certificates, approved videos | Contact the team |
| `/news` | Browse useful articles | Article cards, tags, pagination | Read article |
| `/news/:articleSlug` | Read an article | Article, metadata, related content | Explore related content |
| `/contact` | Start a qualified conversation | Contact data, enquiry form, consent | Send enquiry |
| `/privacy` | Explain personal-data handling | Approved legal content | None |
| `/terms` | Explain website terms | Approved legal content | None |

All content routes are localized. English is the required default. Bengali is
supported from launch at the contract level and may be populated incrementally.

## Navigation hierarchy

```text
Home
Products
  Structured cabling
    Copper cabling
    Fiber cabling
  Data center infrastructure
Services
About
News
Gallery
Contact

Secondary/footer
  Clients
  Partners
  Privacy
  Terms
```

Desktop uses a keyboard-operable product mega-menu. Mobile uses a nested,
disclosure-based navigation with visible back/close controls. Navigation must
never require hover.

## Primary journeys

### Product discovery and quote intent

```text
Landing/search -> category -> filters -> product -> specifications/documents
-> request a quote -> contact details and consent -> confirmation
```

The MVP shows `Request a quote`; it never renders a synthetic `0.00` price.

### Service discovery

```text
Home/navigation -> service list -> service detail -> discuss a project
-> contact form -> confirmation
```

### Content discovery

```text
Home/news -> article list -> article -> related product/service
```

### Locale selection

```text
Any localized page -> choose locale -> equivalent localized route when present
-> English fallback when Bengali content is not yet published
```

The selector must announce the active language and preserve the user's current
content context where an equivalent translation exists.

## Page composition wireframes

### Public shell

```text
[skip link]
[utility/contact strip]
[logo] [primary navigation] [search] [language] [menu]
[breadcrumb where applicable]
[page content]
[newsletter callout]
[contact + product/service links + social + legal footer]
```

### Product listing

```text
[breadcrumb]
[category title + summary]
[child categories]
[search/sort] [mobile filter trigger]
[filter rail] [result count + product card grid]
[pagination]
```

### Product detail

```text
[breadcrumb]
[media gallery] [name + model + summary + brand + request quote]
[specification groups]
[documents]
[related products]
```

### Content page

```text
[breadcrumb]
[hero]
[allowlisted structured sections]
[contextual call to action]
```

## Content model and inventory

| Type | Required launch fields | Translation requirement | Owner |
|---|---|---|---|
| Site settings | name, hostname, logo, contact, default SEO, locales | Contact labels and SEO | Tenant Content Administrator |
| Category | parent, slug, name, summary, order, state | English required; Bengali optional | Catalog Editor |
| Product | canonical category, slug, name, summary, description, model, media, quote flag, state | English required; Bengali optional | Catalog Editor |
| Specification | group, label, value, unit, order | Labels and textual values | Catalog Editor |
| Document | product, type, label, safe asset, locale | Label and locale | Catalog Editor |
| Page | stable key, slug, title, structured sections, SEO, state | English required; Bengali optional | Content Editor |
| Service | slug, title, summary, body, media, SEO, state | English required; Bengali optional | Content Editor |
| Article | slug, title, excerpt, body, tags, hero, date, SEO, state | Per-locale publication | Content Editor |
| Partner/client | kind, name, approved logo, optional link, order, state | Name/summary where needed | Content Editor |
| Gallery item | type, safe media/embed, title, alt text, order, state | Title and alt text | Content Editor |
| Legal page | approved title/body/version/effective date | Locale-specific approval | Legal/Compliance |

Content readiness states for the content workbook are `MISSING`, `DRAFT`,
`RIGHTS_REVIEW`, `APPROVED`, and `PUBLISHED`. Assets require an owner, rights
status, alternative text, locale, checksum, and intended placement.

## Design direction

- Tone: credible, technical, calm, and procurement-friendly.
- Layout: generous public-site spacing with dense specifications only where
  users need comparison detail.
- Color: inherit NexaCore theme primitives while exposing catalog-specific
  semantic tokens from `@nexacore/catalog`.
- Typography: system-first body and heading stacks; avoid blocking font loads.
- Imagery: authentic licensed infrastructure/product imagery; never use
  reference-site assets without explicit rights.
- Icons: use the NexaCore SVG icon registry, never emoji or icon fonts.
- Motion: restrained and disabled through reduced-motion tokens.
- Breakpoints: small `36rem`, medium `48rem`, large `75rem`.

## Required UI states

Every data-backed template must define loading, loaded, empty, recoverable
error, not found, and degraded-media behavior. Product filtering additionally
requires no-results and invalid-filter recovery. Form journeys require idle,
submitting, validation-error, service-error, and success states.

## Fixture scenarios

`@nexacore/catalog` provides synthetic, non-production fixtures for:

- one trusted tenant/site and a rejected hostname;
- English and Bengali home content;
- a two-level category tree;
- three quote-only products with images, specifications, and related products;
- featured/non-featured, category, brand, locale-search, empty, and pagination
  behavior;
- safe `.invalid` contact data and local placeholder asset paths.

Fixtures are view data, not backend seed data, and must never be imported into
production.

## Shared library contract

`@nexacore/catalog` owns framework-light public view contracts and the
`CatalogContentSource` abstraction. The fixture source fails closed when the
hostname/site key does not match. A future HTTP adapter may replace it without
changing feature components.

The package deliberately does not contain endpoint URLs, backend entities,
tenant headers, credentials, feature pages, or administrative authorization.

## Phase 0 acceptance evidence

- Route manifest: `projects/catalog/src/lib/routes/catalog-route-manifest.ts`
- Typed view models: `projects/catalog/src/lib/models/`
- Fixture contract and source: `projects/catalog/src/lib/source/`
- English/Bengali fixtures: `projects/catalog/src/lib/fixtures/`
- Design tokens: `projects/catalog/src/lib/styles/_catalog-tokens.scss`
- Tests: route uniqueness/prerender coverage, tenant fail-closed behavior,
  locale-aware search, pagination, and localized page retrieval.

Backend datasource, Flyway, API, MinIO, Redis, Keycloak, CAPTCHA, and analytics
implementation remain outside Phase 0.
