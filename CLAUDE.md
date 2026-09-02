# CLAUDE.md

Guidance for Claude Code when working in this workspace.

## What this repo is

The **SHARED KERNEL workspace** (`workspace-shared`, directory `shared/`) — one of
THREE sibling workspaces that replaced the old all-in-one `security` workspace
(the owner's verdict, 2026-07-12):

```
Documents/git/
├── shared/    ← THIS repo: identity + channels + every shared library
├── portal/    ← workspace-portal: the social PORTAL product
└── formula/   ← workspace-formula: the F1 GAME product
```

This workspace aggregates the independent git repositories of the kernel: the
shared libraries (`test-starter`, `libs` (artifact `constraint`), `config`,
`email`, `password`, `adjustable-clock`, `infrastructure-micronaut-clock`,
`voting`, `offline-jwt`), the hexagonal Micronaut auth service
(`microservice-security`), the mail service (`microservice-email`, BCE Quarkus)
and the Python channel/identity stubs (`microservice-idp`, `microservice-sms`,
`microservice-push`). Each sub-directory has its **own `.git`, history and
remote** and is gitignored here. This repo versions only the aggregating
`pom.xml` (a pure aggregator, **not** a parent pom), the identity/observability
compose files, the cross-estate tooling (`estate.sh` + its map in `estate/*.repos` — clone/pull/status/check
for all 27 repositories; `infra-smoke.sh`, `aggregate_allure.py`,
`build_features.py`, `build_javadocs.sh`, `build_c4.py`, `allure-serve.sh`) and shared docs
(`docs/`, `todo.md` — the cross-project backlog lives here).

**TWO PRODUCTS, not one (the owner's verdict, 2026-07-11; amended 2026-07-12):**
the social PORTAL (memes, comments, favourites — `../portal`) and the F1 GAME
(`formula-simulator` + its Python `race-sim` + `microservice-paddock`, the game's
social hub — `../formula`) are separate beings that share ONLY identity
(`microservice-security` — one account, one token). Never conflate them in docs
or diagrams. The 2026-07-12 amendment moved paddock to the GAME: its users are
players and its `infra` pulls live game state from the instances.

## How the pieces couple

- Products consume this kernel through **`~/.m2`** (build here first:
  `./mvnw install`) and through the **running identity stack**
  (`docker-compose.identity.yml`, included by each product's compose).
- The compose project name is pinned to `security` in all three workspaces —
  one dev stack, shared volumes, no port fights when both products are up.
- Products' up-scripts (`../portal/infra-up.sh`, `../formula/formula-up.sh`)
  build the kernel themselves; `./infra-smoke.sh` HERE proves the whole estate
  end to end (both products must be up).

## Working across repos — important

- A new sub-repo goes into BOTH the workspace `.gitignore` and `estate/<workspace>.repos`;
  `./estate.sh check` catches a miss. On a fresh machine: clone `workspace-shared`, then
  `./estate.sh clone`.
- Commits made here **do not** touch the sub-repos. To change project code,
  `cd` into the relevant sub-repo and commit there against **its** history.
- All modules share `com.jrobertgardzinski:*:1.0.0-SNAPSHOT`.
- Every sub-project stays buildable standalone (own parent preserved). Do not
  convert the aggregator into their parent.

## Build & test

```bash
./mvnw clean install          # the whole shared kernel
./mvnw -pl microservice-security -am clean verify   # one project + its deps
```

JDK 25. Wrapper pinned to Maven 3.9.9.

## Conventions

- Javadoc and code comments in **English**.
- Git author is canonical: `Robert Gardziński <jrobertgardzinski@gmail.com>`.
- Backlog lives in `todo.md` (here — cross-project) and each sub-repo's own
  `todo.md`. Read it BEFORE proposing anything; many verdicts are recorded.
