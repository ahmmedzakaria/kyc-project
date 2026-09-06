# AI-Assisted Development and Token Optimization Implementation Plan

## 1. Purpose

Implement a safe, measurable AI-assisted development workflow for the NexaCore
repository that:

- gives models only the context required for the current task;
- improves relevant-file discovery across backend and frontend modules;
- separates stable source-code knowledge from live operational data;
- reduces input, output, and reasoning-token waste;
- preserves security, tenant isolation, migration, and verification rules; and
- introduces infrastructure only after simpler retrieval methods are measured.

The plan deliberately starts with repository hygiene and deterministic search.
Vector retrieval, semantic caching, and automated model routing are later phases,
not prerequisites for productive AI-assisted development.

## 2. Success Criteria

The implementation is successful when:

1. A routine task normally sends no more than 3–8 relevant source excerpts to the
   model.
2. Generated artifacts, binaries, backups, and dependency trees do not enter AI
   context or the source index.
3. Every task declares its goal, scope, constraints, and completion evidence.
4. Repository retrieval is tied to a repository, branch, and commit SHA.
5. Cached results are invalidated when relevant source content changes.
6. Live database, CI, ticket, and environment state is obtained through tools or
   MCP rather than treated as durable source knowledge.
7. Security-sensitive and migration-related tasks are routed to a sufficiently
   capable model and always require verification.
8. Token cost, cache effectiveness, task success, and retry rate are observable.

Initial targets, to be revised after collecting a two-week baseline:

- reduce median uncached input tokens per completed task by at least 40%;
- keep irrelevant retrieval results below 20% of supplied chunks;
- achieve at least 90% first-pass relevant-file recall for benchmark tasks;
- reduce repeated repository-orientation context by at least 60%; and
- introduce no increase in escaped defects or failed verification.

## 3. Guiding Principles

### 3.1 Progressive context loading

Load context in this order:

1. stable repository rules;
2. the current task contract;
3. exact text and symbol matches;
4. neighboring callers, dependencies, and tests;
5. architecture excerpts when the task crosses a boundary;
6. semantic/vector results only when deterministic retrieval is insufficient;
7. live state through an authorized tool.

Do not send the whole repository or entire long documents by default.

### 3.2 Outcome-sized tasks

Break work into independently verifiable outcomes, not individual file reads or
single-line edits. Each task should end with a useful checkpoint that can be
carried into a new conversation without replaying the full history.

### 3.3 Hybrid retrieval before vector-only retrieval

Exact identifiers such as Java class names, route paths, table names, privilege
codes, and Flyway versions should be found lexically. Semantic retrieval should
supplement exact search for conceptual questions, not replace it.

### 3.4 Cache facts, not unsafe conclusions

Cache embeddings, parsed metadata, summaries tied to content hashes, and
retrieval candidates. Do not reuse patches, authorization conclusions,
migration decisions, or mutable environment results without revalidation.

## 4. Target Architecture

```text
Developer request
       |
       v
Task classifier and risk evaluator
       |
       +-- Stable context: AGENTS.md + PROJECT_CONTEXT.md
       |
       +-- Deterministic retrieval: file search + symbol index + Git
       |
       +-- Optional hybrid RAG: lexical score + vector score + dependency score
       |
       +-- Live tools/MCP: database, CI, logs, tickets, cloud services
       |
       +-- Redis: embedding, metadata, and retrieval-result cache
       |
       v
Model router
       |
       v
LLM receives a bounded context package
       |
       v
Patch, explanation, or review + required verification
```

## 5. Repository Context Design

### 5.1 `PROJECT_CONTEXT.md`

Create a root `PROJECT_CONTEXT.md` as a concise orientation map. Keep it between
approximately 1,000 and 2,500 tokens.

It should contain:

- module locations and technology choices;
- critical domain and authorization invariants;
- database and Flyway rules;
- common verification commands;
- pointers to authoritative detailed documents; and
- a short list of generated/runtime directories.

It should not contain:

- complete endpoint catalogs;
- complete schemas or entity descriptions;
- copied source code;
- volatile branch status;
- local credentials;
- large command transcripts; or
- information already stated identically in `AGENTS.md`.

`AGENTS.md` remains authoritative for agent behavior. `PROJECT_CONTEXT.md` is a
compact system map. Repeated rules should be replaced with links or short
references where possible.

### 5.2 `.aiignore`

Create a root `.aiignore` and apply equivalent exclusions in every indexing
service because `.aiignore` support is tool-specific.

Initial exclusions:

```gitignore
**/node_modules/
**/dist/
**/.angular/
**/target/
**/coverage/
**/uploads/
**/*.class
**/*.jar
**/*.log
**/*.db
**/*.db-lock
db-backup/
```

Do not broadly exclude:

- Flyway migrations;
- lock files used for dependency diagnosis;
- generated clients that are compilation inputs;
- checked-in configuration templates; or
- design documents referenced by `PROJECT_CONTEXT.md`.

### 5.3 Context ownership

| Context | Owner | Update trigger |
|---|---|---|
| `AGENTS.md` | Engineering leads | Development policy changes |
| `PROJECT_CONTEXT.md` | Architecture owner | Module or invariant changes |
| `.aiignore` | Build/platform owner | Artifact layout changes |
| Retrieval index | Automated pipeline | Commit or branch change |
| Task checkpoint | AI workflow | Completion of an outcome |

## 6. Prompt Contract

Adopt this compact task format for development work:

```text
Goal:
<one observable outcome>

Scope:
<modules, files, services, or environment in scope>

Constraints:
<security, compatibility, migration, and side-effect restrictions>

Evidence:
<facts, errors, logs, issue links, or known relevant symbols>

Done when:
<tests, build, database checks, or review output required>
```

Optional fields:

```text
Out of scope:
<explicit exclusions>

Output:
<patch, review findings, design, JSON, or concise explanation>
```

Prompt-generation rules:

- state the expected outcome before implementation details;
- avoid pasting files that retrieval can locate;
- reference exact error messages and symbols when available;
- specify an output limit for explanations and reviews;
- place stable instructions before volatile task context; and
- do not prescribe a step-by-step solution unless the procedure itself is a
  requirement.

## 7. Relevant-File Retrieval

### 7.1 Stage A: deterministic retrieval

Implement deterministic retrieval first using:

- `rg` for file names, identifiers, SQL objects, routes, and error fragments;
- language-server or IDE indexes for definitions and references;
- import and call relationships;
- Git diff and history for recently affected files; and
- test-name and production-symbol matching.

Retrieval sequence:

1. Search for exact error text and identifiers.
2. Locate definitions.
3. Locate direct callers and implementations.
4. Locate narrow tests.
5. Read the applicable architecture invariant.
6. Expand one dependency level only when the first set is insufficient.

Default context budget:

- 3–8 excerpts;
- 50–150 lines per excerpt;
- no more than two test excerpts;
- no more than one architecture/documentation excerpt; and
- path, symbol, and line metadata for every excerpt.

### 7.2 Stage B: structural index

Create a structural index with records for:

- Java classes, interfaces, methods, repositories, controllers, and Spring
  configuration;
- Angular components, services, routes, guards, models, and templates;
- SQL migrations and the tables they read or write;
- Compose services and environment-variable references; and
- Markdown headings and their parent documents.

Store relationships including:

- imports;
- implements/extends;
- callers and callees where reliably derivable;
- endpoint to service to repository paths;
- component to service and route relationships;
- migration version ordering; and
- test-to-production symbol references.

### 7.3 Stage C: hybrid RAG

Add semantic retrieval only after measuring deterministic retrieval failures.

Recommended ranking baseline:

```text
score =
    0.50 * lexical_or_exact_score
  + 0.30 * vector_similarity
  + 0.10 * dependency_proximity
  + 0.10 * recent_change_relevance
```

Apply metadata filters before vector ranking:

- repository;
- branch;
- commit SHA or index generation;
- module;
- language;
- file type; and
- optionally changed-files scope.

The retrieval service must return citations containing file path, symbol,
start/end lines, commit SHA, retrieval method, and score.

## 8. Chunking Strategy

Use structure-aware chunks:

| Content | Chunk boundary |
|---|---|
| Java | Class/interface; large classes split by method |
| TypeScript | Component/service/model; large files split by symbol |
| Angular HTML | Logical template section tied to its component |
| SCSS | Selector or related selector group |
| SQL | Migration, then statement group when very large |
| Markdown | Heading and its child content |
| YAML/properties | Logical configuration section |

Each chunk should store:

```text
repository
branch
commit_sha
file_path
module
language
symbol
chunk_type
start_line
end_line
content_hash
content
embedding_model
embedding
indexed_at
```

Use the content hash as the primary invalidation key. Re-embed only changed
chunks and remove chunks whose files or symbols were deleted.

## 9. PostgreSQL and pgvector Design

Introduce pgvector when multiple repositories, conceptual queries, or shared
team retrieval justify persistent semantic search.

Illustrative schema:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE ai_code_chunks (
    id bigserial PRIMARY KEY,
    repository text NOT NULL,
    branch text NOT NULL,
    commit_sha text NOT NULL,
    file_path text NOT NULL,
    module text,
    language text,
    symbol text,
    chunk_type text NOT NULL,
    start_line integer NOT NULL,
    end_line integer NOT NULL,
    content_hash text NOT NULL,
    content text NOT NULL,
    embedding_model text NOT NULL,
    embedding vector,
    indexed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (repository, branch, commit_sha, file_path, content_hash)
);
```

The production implementation must choose the vector dimension based on the
selected embedding model and add an appropriate HNSW or IVFFlat index only
after representative performance testing.

Security requirements:

- never index secrets, `.env` values, access tokens, or private keys;
- enforce repository access before retrieval;
- preserve tenant/repository isolation in database predicates;
- record the source commit for every result; and
- log retrieval metadata without logging sensitive source unnecessarily.

## 10. MCP and Live Tools

Use MCP or direct authorized tools for mutable state:

- database schema and Flyway history;
- CI runs and test failures;
- issue trackers and current acceptance criteria;
- application logs and observability data;
- deployment configuration; and
- cloud resources.

Do not permanently embed live results into the source index by default. A code
question and a production-state question should have separate retrieval paths.

Every live tool must document:

- when it should be used;
- required inputs;
- read versus write behavior;
- authorization boundaries;
- retry safety;
- destructive side effects; and
- expected evidence returned to the model.

## 11. Redis Cache Design

Use Redis initially for deterministic reusable work:

| Cache | Suggested key | Invalidation/TTL |
|---|---|---|
| Embedding | `ai:embedding:<model>:<content-hash>` | Model or content change |
| Parsed symbols | `ai:symbols:<parser-version>:<content-hash>` | Parser/content change |
| Retrieval result | `ai:retrieval:<repo>:<commit>:<query-hash>` | Short TTL or commit change |
| Module summary | `ai:summary:<repo>:<commit>:<module>` | Commit change |
| Read-only explanation | `ai:answer:<repo>:<commit>:<query-hash>` | Short TTL and hash validation |

Do not cache final answers for:

- patches or refactors;
- authentication and authorization decisions;
- Flyway repair or data migration decisions;
- current database or deployment state;
- incident response; or
- a failed or unverified task.

A cache entry must include the repository commit, model/version, creation time,
and relevant source hashes. Semantic cache hits must pass both similarity and
source-freshness checks.

## 12. Prompt Caching

Arrange model input so reusable content forms a stable prefix:

1. system and safety instructions;
2. repository-wide rules;
3. stable tool definitions;
4. task-type instructions;
5. retrieved context;
6. live observations and the current request.

Operational requirements:

- use a stable prompt cache key for the same application/workflow;
- avoid timestamps, random identifiers, and volatile state in the prefix;
- measure cached input tokens rather than assuming a cache hit;
- version the stable prompt deliberately; and
- keep context small even when cached because caching lowers cost/latency but
  does not make irrelevant context useful.

## 13. Model Routing

### 13.1 Task classes

| Task class | Default route |
|---|---|
| Query normalization, classification, file ranking | Small/fast model |
| Documentation summary and localized mechanical edit | Small or mid-tier model |
| Normal feature implementation with clear tests | Coding model |
| Cross-module refactor | Strong coding/reasoning model |
| Authentication, authorization, tenant scope | Strong model + mandatory verification |
| Flyway/schema/data migration | Strong model + database validation |
| Final security review | Strong model, preferably independent review |

### 13.2 Escalation signals

Escalate when any of these are true:

- more than three modules are affected;
- authentication, authorization, tenant ownership, or secrets are involved;
- a migration or destructive data operation is involved;
- retrieval confidence is below the configured threshold;
- requirements conflict;
- two implementation attempts fail verification; or
- the requested change lacks an authoritative acceptance criterion.

Do not route solely by prompt length. Risk and dependency breadth are stronger
signals than character count.

## 14. Conversation and Checkpoint Management

At the end of each outcome, create a compact checkpoint:

```text
Goal completed:
<result>

Files changed:
<paths>

Decisions:
<important choices and why>

Verified:
<commands and results>

Remaining:
<next outcome or none>
```

Start a new session when moving to a materially different feature or incident.
Do not carry unrelated build logs, discarded hypotheses, or full prior patches
into a new task.

## 15. Observability and Evaluation

Record per task:

```text
task_id
repository
commit_sha
task_class
risk_class
selected_model
reasoning_level
input_tokens
cached_input_tokens
output_tokens
reasoning_tokens
retrieval_tokens
retrieved_chunk_count
tool_call_count
retry_count
verification_result
human_acceptance
elapsed_time
estimated_cost
```

Primary metrics:

- cost per accepted task;
- first-pass verification success;
- retrieval precision and relevant-file recall;
- cached-input ratio;
- average context size by task class;
- retry and escalation rate;
- escaped-defect rate; and
- median time to accepted result.

Create a benchmark set containing at least:

- a localized backend defect;
- an Angular component defect;
- a cross-database identity question;
- a tenant-isolation review;
- a Flyway version/checksum incident;
- a cross-frontend shared-library change; and
- a documentation-only request.

Compare workflow changes against this fixed benchmark before broad rollout.

## 16. Implementation Phases

### Phase 0: baseline measurement

Deliverables:

- select 20–30 representative historical tasks;
- record current token, retry, latency, and success metrics;
- identify the most common irrelevant directories and context sources; and
- define high-risk task categories.

Acceptance criteria:

- a documented baseline exists;
- benchmark tasks and expected evidence are agreed; and
- no new infrastructure is selected without a measured need.

### Phase 1: context hygiene and prompt standardization

Deliverables:

- root `PROJECT_CONTEXT.md`;
- root `.aiignore`;
- matching exclusions for IDE/indexing tools;
- prompt templates for implementation, diagnosis, review, and migration work;
- checkpoint template; and
- secret-scanning check before indexing.

Acceptance criteria:

- generated directories are absent from sample context packages;
- repository orientation fits within the agreed token budget;
- benchmark prompts use the structured contract; and
- critical `AGENTS.md` invariants remain authoritative and visible.

### Phase 2: deterministic relevant-file retrieval

Deliverables:

- search orchestration around files, exact text, symbols, Git, and tests;
- a bounded context-package format;
- retrieval citations with paths and line numbers;
- module-aware search filters; and
- retrieval evaluation against the benchmark.

Acceptance criteria:

- at least 90% relevant-file recall on benchmark tasks;
- default packages remain within the excerpt budget;
- every excerpt is traceable to a commit and path; and
- the model can request an explicit second retrieval pass.

### Phase 3: structural indexing

Deliverables:

- parsers for Java, TypeScript, Angular templates, SQL, and Markdown;
- symbol/dependency metadata;
- incremental indexing based on content hashes; and
- branch/commit isolation.

Acceptance criteria:

- changed files alone are reprocessed;
- deleted files disappear from results;
- branch results cannot leak into one another; and
- endpoint/service/repository and component/service relationships are queryable.

### Phase 4: hybrid RAG with pgvector

Entry condition:

- deterministic retrieval misses a meaningful percentage of conceptual or
  cross-module benchmark questions.

Deliverables:

- pgvector schema and migrations;
- embedding pipeline;
- hybrid ranking service;
- metadata filters and access control;
- stale-index detection; and
- retrieval-quality dashboard.

Acceptance criteria:

- hybrid retrieval improves recall without materially reducing precision;
- no secret or excluded artifact appears in the index;
- all results identify their source commit; and
- stale results are rejected or clearly marked.

### Phase 5: Redis caching and prompt-cache optimization

Deliverables:

- content-hash embedding cache;
- commit-scoped retrieval cache;
- cache metrics and invalidation tests;
- stable prompt-prefix versioning; and
- cached-token monitoring.

Acceptance criteria:

- cache invalidation tests cover changed and deleted source;
- no mutable operational answer is reused without revalidation;
- cached input ratio improves for repeated workflows; and
- total cost per accepted benchmark task decreases.

### Phase 6: model routing

Deliverables:

- task/risk classifier;
- routing policy configuration;
- escalation and retry policy;
- model-specific budgets; and
- audit logs explaining routing decisions.

Acceptance criteria:

- high-risk tasks never route below their minimum capability class;
- routine classification/retrieval tasks use the low-cost route;
- failed verification triggers controlled escalation; and
- routing reduces cost without reducing benchmark success.

### Phase 7: MCP/live-tool integration

Deliverables:

- prioritized connectors for database, CI, issues, and observability;
- least-privilege credentials;
- read/write and destructive-action policies;
- tool-result schemas; and
- audit logging.

Acceptance criteria:

- live facts are retrieved on demand rather than stored as source truth;
- write operations require the appropriate authorization;
- sensitive values are redacted from model-visible output; and
- every action is attributable and auditable.

## 17. Security and Governance

- Treat source access and retrieved context as authorization-sensitive.
- Never index `.env`, secrets, private keys, production dumps, or raw customer
  records.
- Run secret detection before embedding and before logging prompts.
- Apply repository and branch access filters in database predicates.
- Redact credentials from tool calls and traces.
- Require human approval for destructive production operations.
- Never let semantic similarity override explicit tenant or repository access.
- Preserve the rule that applied Flyway migrations are immutable; repair actions
  require evidence from migration history and an explicit recovery plan.
- Define retention periods for prompts, retrieved source, tool output, and cache
  entries.

## 18. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Stale code retrieved | Commit-scoped index and content-hash validation |
| Vector result misses exact identifier | Hybrid lexical-first ranking |
| Secrets enter embeddings | Ignore rules plus pre-index secret scanning |
| Cached patch is reused incorrectly | Do not cache generated patches |
| Small model mishandles risky task | Risk-based minimum model and escalation |
| Too much context still supplied | Hard excerpt/token budgets and telemetry |
| Long conversations dilute context | Outcome checkpoints and fresh sessions |
| MCP tool causes unintended write | Read/write classification and approval policy |
| RAG infrastructure costs exceed savings | Phase entry criteria and benchmark gates |

## 19. Initial Backlog

### Priority 1

- [ ] Create and approve `PROJECT_CONTEXT.md`.
- [ ] Create `.aiignore` and mirror it in indexing configuration.
- [ ] Define implementation, diagnosis, review, and migration prompt templates.
- [ ] Select benchmark tasks and capture baseline token metrics.
- [ ] Define the context-package schema and excerpt budget.

### Priority 2

- [ ] Implement deterministic repository retrieval.
- [ ] Add language-server symbol and reference retrieval.
- [ ] Add Git diff/history relevance.
- [ ] Add test-to-production symbol matching.
- [ ] Evaluate precision and recall.

### Priority 3

- [ ] Build incremental structural indexing.
- [ ] Evaluate whether hybrid RAG materially improves benchmark results.
- [ ] Add pgvector only if the evaluation passes the entry condition.
- [ ] Add Redis embedding and retrieval caching.
- [ ] Implement task/risk-based model routing.

### Priority 4

- [ ] Add selected MCP integrations using least privilege.
- [ ] Add dashboards for tokens, cache hits, retries, success, and cost.
- [ ] Run a limited team pilot.
- [ ] Review results and update routing/context budgets before wider rollout.

## 20. Definition of Done

The complete initiative is done when:

- context and ignore files are maintained as part of normal engineering work;
- deterministic and optional semantic retrieval are evaluated and observable;
- all retrieved source is permission-filtered, commit-scoped, and cited;
- caches have tested invalidation behavior;
- routing policies are risk-aware and auditable;
- live tools operate with least privilege;
- benchmark quality is unchanged or improved; and
- measured cost per accepted development task is lower than the Phase 0 baseline.

