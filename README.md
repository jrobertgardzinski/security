# The estate — a microservice portfolio, one clone away

> 👋 **Start here.** This is the map of my portfolio: a shared **identity kernel** and the social
> **meme portal** built on it — twenty-one independent repositories, six JVM flavours, every use case
> an **executable specification**. Two minutes well spent: the
> [security brochure](https://github.com/jrobertgardzinski/microservice-security) (with a video
> walkthrough), the [meme gallery](https://github.com/jrobertgardzinski/microservice-memes), and
> the blog at [jrobertgardzinski.pl](https://jrobertgardzinski.pl/).

**What is on show**

- **DDD + hexagonal architecture** with the dependency rule enforced: domain → config → system →
  application → infrastructure, and the same Gherkin scenarios driven from more than one door.
- **Executable specs** over real HTTP in every build: 18 in `microservice-security` (register,
  authenticate, sessions, MFA and passkeys, OAuth, roles, live password policy, account deletion),
  7 in `microservice-memes` (upload, vote, tag, delete, flag, purge policy, erasure).
- **Six flavours of the JVM**, one estate: Micronaut (security), Quarkus (email), Spring Boot
  (memes, comments), Helidon SE on virtual threads (user-collections), Javalin (paddock), plus
  Python stdlib stubs (IdP, image encoder, SMS, push).
- **Distributed patterns done for real**: a transactional outbox on Kafka, the account-deletion
  saga extracted into its own process manager (orchestration with compensation) next to a
  choreographed cascade, offline JWT/JWKS verification shared by every consumer, Pact contracts
  verified on the provider's CI, a configuration ladder (a database row over a property over the
  code default, with fail-fast and fall-through laws).
- **Proof, not prose**: generated C4 diagrams from the compose file and the pacts, Allure-generated
  documentation of the lower layers, a smoke test that walks the whole stack end to end.

## The workspace

Each sub-directory is an **independent git repository** with its own history and remote; this
repo only ties them together for convenience:

- an **aggregating `pom.xml`** so the whole thing builds as one Maven reactor and
  imports as a single project in the IDE, and
- **shared scripts and tooling** used across the projects (Allure aggregation,
  documentation generation, cheatsheets).

The sub-repositories are gitignored here — this workspace does **not** version
their contents.

**A kernel and a product:** the **shared kernel** (identity, mail chain, stub IdP, notification
channels, every shared library) lives here; the social **PORTAL** (memes gallery, comments,
favourites, the paddock hub) lives in the sibling workspace
[`workspace-portal`](https://github.com/jrobertgardzinski/workspace-portal) and consumes the
kernel through `~/.m2` and the identity compose file. The generated
[C4 diagrams](docs/c4-architecture.md) draw that boundary and the generator enforces it.

## Getting started on a fresh machine

The estate is sibling workspaces holding independent git repositories between them. One script
clones and keeps all of them; its map is data in [`estate/`](estate/) (one `<directory> <url>`
line per repository). Everything the portfolio shows is public; a few repositories in the map are
private and are simply reported as failed unless the GitHub CLI is signed in.

```bash
# prerequisites: git, JDK 25, Docker with compose, Node 20+ (the React UIs), Python 3 (the stubs)
mkdir -p ~/Documents/git && cd ~/Documents/git
git clone https://github.com/jrobertgardzinski/workspace-shared.git shared
./shared/estate.sh clone          # clones every workspace and sub-repository that is missing
cd shared && ./mvnw install       # the kernel first; the products consume it from ~/.m2
```

Day to day:

```bash
./estate.sh status [--fetch]      # one line per repository: branch, ahead/behind, dirty files
./estate.sh pull                  # fast-forward every clean repository; dirty ones are listed, not touched
./estate.sh check                 # the map must match the territory: manifests vs disk vs .gitignore
```

Adding a repository: create it on GitHub, clone it into the right workspace, add its line to the
workspace's `.gitignore` and to `estate/<workspace>.repos`; `./estate.sh check` tells you if you
forgot one of the two.

## Projects

Build order is computed automatically by the Maven reactor; the natural
dependency order is:

| Module | Description |
|--------|-------------|
| `test-starter` | Shared JUnit5 / BDD / system test starters |
| `libs` | Constraint / validation primitives (artifact `constraint`) |
| `config` | The configuration ladder: `ConfigValue`, `Configuration.liveOver/boundOver`, the settings snapshot |
| `email` | Email value objects (`email-domain`, `-config`, `-usecase`) |
| `password` | Password value objects and policy (`password-domain`, `-config`, `-usecase`), hash algorithms (Argon2) |
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

**Not in the reactor:** the Python helper services (`microservice-idp`, `-image`, `-sms`,
`-push`) are not Maven modules.

## Build

The aggregator is a **pure aggregator**, not the parent of the modules — every
sub-project keeps its own parent and stays buildable standalone.

```bash
# The whole kernel reactor, correct order, one command:
./mvnw clean install

# A single project standalone:
cd microservice-security && ./mvnw clean verify
```

Requires JDK 25. The Maven Wrapper (`./mvnw`, Maven 3.9.9) is committed, so no
system Maven is needed.

## Run the whole stack

`docker-compose.yml` starts the portal and its infrastructure: the portal
services (security + email + memes + comments + paddock + user-collections, each
stateful one with its own Postgres), **Kafka** as the portal's event backbone
(mail requests from security's transactional outbox, the account-deletion saga,
the `MEME_DELETED` cascade), MinIO for the gallery's image bytes,
[Mailpit](https://mailpit.axllent.org/) as the dev inbox, the stub OIDC provider,
and the observability stack
(Prometheus/Grafana/Loki/Tempo). The **gallery UI** lives at
http://localhost:8083/ (browsing is public; sign-up/sign-in goes through
security; signed-in users upload, vote and star favourites).

```bash
./infra-up.sh      # package the jars, build the images, start everything
./infra-smoke.sh   # end-to-end proof: register -> mail -> verify -> sign-in,
                   # meme upload, deletion saga, favourites CORS
./infra-down.sh    # stop (add -v to drop the database volumes)
```

Ports: security 8080, email 8082, memes 8083 (gallery UI), comments 8085, paddock 8086, user-collections 8092, collections-ui 8093,
offboarding 8094, Mailpit UI 8025, Grafana 3000. The full map lives in
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
