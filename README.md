# security

Workspace for the security projects. Each sub-directory is an **independent git
repository** with its own history and remote; this repo only ties them together
for convenience:

- an **aggregating `pom.xml`** so the whole thing builds as one Maven reactor and
  imports as a single project in the IDE, and
- **shared scripts and tooling** used across the projects (Allure aggregation,
  documentation generation, cheatsheets).

The sub-repositories are gitignored here — this workspace does **not** version
their contents.

**Two products, not one:** the social **PORTAL** (memes gallery, comments,
favourites, the paddock hub) and the **F1 GAME** (`formula-simulator` + its
Python `race-sim`) are separate beings that share only **identity**
(`microservice-security` — one account, one token works in both). The generated
[C4 diagrams](docs/c4-architecture.md) draw that boundary and the generator
enforces it.

## Projects

Build order is computed automatically by the Maven reactor; the natural
dependency order is:

| Module | Description |
|--------|-------------|
| `test-starter` | Shared JUnit5 / BDD / system test starters |
| `constraint` | Constraint / validation primitives |
| `config` | Configuration primitives (`PropertiesConfigPort`/`Source`) |
| `email` | Email value objects + email-security |
| `password` | Password value objects, hash algorithms (Argon2), password-security |
| `adjustable-clock` / `infrastructure-micronaut-clock` | Steerable test clock + its Micronaut adapter |
| `voting` | Voting bounded context as a library (toggle + tally over the Ballots port) |
| `offline-jwt` | Offline verification of security's tokens (JWKS + EdDSA), shared by the consumer services |
| `microservice-security` | The shared identity: hexagonal on Micronaut (16 executable specs: register, authenticate, sessions, MFA/passkeys, OAuth, deletion saga, …) |
| `microservice-email` | Mail microservice, BCE on Quarkus (`POST /mails*`, Qute templates) |
| `microservice-memes` | Meme microservice, layered modules on Spring Boot (upload/thumbnails/votes, gallery UI) |
| `microservice-comments` | Comment threads + comment votes; Spring Boot with its own Postgres |
| `microservice-paddock` | The portal's social hub (servers, people, events; PWA), vertical slices on Javalin |
| `microservice-user-collections` | A user's saved refs (favourites), Helidon 4 SE on virtual threads |
| `microservice-offboarding` | The portal's account-deletion process manager (the saga orchestration, extracted from security); participants are configuration |

**Not in the reactor:** `formula-simulator` — the F1 game is a **separate
product** and builds standalone (`./mvnw -f formula-simulator/pom.xml clean verify`,
after a one-time `./mvnw -pl offline-jwt -am install`). The Python helper services
(`microservice-idp`, `-image`, `-sms`, `-push`, `race-sim`) are not Maven modules.

## Build

The aggregator is a **pure aggregator**, not the parent of the modules — every
sub-project keeps its own parent and stays buildable standalone.

```bash
# The whole PORTAL reactor, correct order, one command:
./mvnw clean install

# The F1 game (separate product):
./mvnw -f formula-simulator/pom.xml clean verify

# A single project standalone:
cd microservice-security && ./mvnw clean verify
```

Requires JDK 25. The Maven Wrapper (`./mvnw`, Maven 3.9.9) is committed, so no
system Maven is needed.

## Run the whole stack

`docker-compose.yml` starts both products and their infrastructure: the portal
services (security + email + memes + comments + paddock + user-collections, each
stateful one with its own Postgres), **Kafka** as the portal's event backbone
(mail requests from security's transactional outbox, the account-deletion saga,
the `MEME_DELETED` cascade), MinIO for the gallery's image bytes,
[Mailpit](https://mailpit.axllent.org/) as the dev inbox, the stub OIDC provider,
the F1 game with its sealed `race-sim`, and the observability stack
(Prometheus/Grafana/Loki/Tempo). The **gallery UI** lives at
http://localhost:8083/ (browsing is public; sign-up/sign-in goes through
security; signed-in users upload, vote and star favourites).

```bash
./infra-up.sh      # package the jars, build the images, start everything
./infra-smoke.sh   # end-to-end proof: register -> mail -> verify -> sign-in,
                   # meme upload, deletion saga, favourites CORS
./infra-down.sh    # stop (add -v to drop the database volumes)
```

Ports: security 8080, email 8082, memes 8083 (gallery UI), formula 8084 (race
viewer), comments 8085, paddock 8086, user-collections 8092, collections-ui 8093,
offboarding 8094, Mailpit UI 8025, Grafana 3000. The internal wiring is published
too (security's Postgres 5433, Kafka's host listener 29092, Mailpit SMTP 1025,
sms 8088, push 8089) so that ONE service can run from the IDE against the rest:
`./dev-swap.sh security` stops the container and prints the env from
`dev/local/security.env` to paste into the Run Configuration; `./dev-swap.sh back
security` brings the container back. Same script for the portal services from
`../portal` (their env files live there). The full map lives in
[docs/onboarding-guide.md](docs/onboarding-guide.md) and the generated
[C4 diagrams](docs/c4-architecture.md).

## Tooling

| Script | Purpose |
|--------|---------|
| `build_c4.py` | Generate C4 diagrams (`docs/c4-architecture.md`) from docker-compose.yml + the Pact files |
| `aggregate_allure.py` | Merge Allure results across projects |
| `allure-serve.sh` | Serve the aggregated Allure report |
| `create-documentation.sh` | Generate project documentation |
| `infra-up.sh` / `infra-down.sh` / `infra-smoke.sh` | Run and smoke-test the whole service stack (see above) |
| `maven-cheatsheet.md` | Maven command reference |
| `allure-summary.md` | Current test/documentation summary |
| `todo.md` | Cross-project backlog |
