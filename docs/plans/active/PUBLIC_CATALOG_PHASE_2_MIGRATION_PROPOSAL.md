# Catalog Database Migration Decision Record

Approved by the user on 2026-11-24 and implemented as
`backend/src/main/resources/db/migration/catalog/V1__create_catalog_schema.sql`.

## Proposed database foundation

- Dedicated PostgreSQL database and Flyway history: `catalog_db`.
- Every aggregate table is tenant-owned with a non-null `tenant_id` referencing
  the trusted system tenant identifier at application level (cross-database,
  therefore no physical foreign key).
- Every table includes `created_at`, `updated_at`, `created_by`, and
  `updated_by`; editable aggregates also include an optimistic-lock `version`.
- Stable aggregate tables keep operational relationships, ordering,
  publication state, and audit data. Translated fields use aggregate-specific
  translation tables with `(aggregate_id, locale)` uniqueness.
- English (`en`) is required before publication. Bengali (`bn`) may be added
  incrementally.
- MVP publication state is `DRAFT` or `PUBLISHED`, with `published_at` and
  `published_by`; only role-controlled application transitions may change it.

## Proposed V1 tables

Foundation and navigation: `catalog_sites`, `catalog_site_translations`,
`catalog_navigation_items`, `catalog_navigation_item_translations`.

Catalog: `catalog_categories`, `catalog_category_translations`,
`catalog_brands`, `catalog_brand_translations`, `catalog_products`,
`catalog_product_translations`, `catalog_product_media`,
`catalog_product_documents`, `catalog_product_specifications`, and
`catalog_related_products`.

Corporate content: `catalog_pages`, `catalog_page_translations`,
`catalog_page_sections`, `catalog_page_section_translations`,
`catalog_services`, `catalog_service_translations`, `catalog_articles`,
`catalog_article_translations`, `catalog_organizations`, and
`catalog_gallery_items`.

Media: `catalog_media_assets`, storing tenant ownership, namespace/object key,
media type, MIME type, size/dimensions, accessibility text, visibility,
publication state, and audit fields. Secrets and storage credentials are not
stored.

Engagement tables are intentionally deferred to their later phase.

## Constraints and indexes

- Tenant-scoped unique slugs/keys, for example `(tenant_id, slug)`.
- Translation uniqueness on `(aggregate_id, locale)` and locale check limited
  initially to `en` and `bn`.
- Parent/category/media relationships are foreign-key constrained inside
  `catalog_db`; delete behavior is restrictive for referenced published data.
- Check constraints cover publication states, non-negative ordering and file
  sizes, and prohibit self-related products.
- Public-read indexes begin with `tenant_id` and publication state, followed by
  slug, ordering, featured flags, or publication time as appropriate.

## Implementation result

The V1 SQL, dedicated datasource, JPA persistence unit, transaction manager,
Flyway runner, Actuator datasource health participation, environment settings,
Compose settings, and backup target are implemented. PostgreSQL validated all
25 table definitions and 11 explicit public-read indexes in a rollback-only
execution. `CatalogDatabaseMigrationTest` covers clean migration, repeat-run
idempotency, audit-column coverage, and cross-tenant relationship rejection.
