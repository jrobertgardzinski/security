# Onboarding guide — the whole project in order, junior-friendly

As of **2026-07-11**. This document walks you through the entire project from zero:
**what it is**, **which tools build it**, **what each one is responsible for** and
**how to run it**. I assume you can program, but that many of the tools are new to you.
Read in order — every section builds on the previous ones.

Every section opens with a **🏷️ Tags** block — the list of tools/techniques appearing in
it, each with a one-sentence explanation. Looking for a specific tool? Scan just the tags.

---

## 1. What even is this project?

> 🏷️ **Tags:**
> **microservices** — a system composed of small, independently deployable services;
> **multi-repo** — every service in its own git repository (the opposite of a monorepo);
> **workspace / aggregator** — a binder repo that contains no service code, only glues them together for joint work.

This is **not one program**. It is a **portfolio of microservices** — a dozen-plus
independent services forming **TWO SEPARATE PRODUCTS** (the owner's verdict,
2026-07-11 — never conflate them in descriptions!):

1. **the social portal** — meme gallery, comments, favourites, the "paddock" hub
   (servers/people/events; F1-flavoured in name only);
2. **the F1 game** (`formula-simulator` + `race-sim`) — a manager with an authoritative
   simulation, a separate being with its own database and its own deployment model
   (group servers per league).

The products share **IDENTITY only** (one account + MFA in `microservice-security`,
one token works in both) plus this dev compose; the game has not a single edge to
memes/comments/Kafka (proof: the C4 diagrams generated from compose). The portfolio's
key idea:

> **The same architecture (hexagonal) realised in DIFFERENT frameworks — six "flavours".**

Micronaut, Quarkus, Spring Boot, Javalin, Helidon SE and "bare" JDK. The portfolio shows
the pattern is portable; understand one service and you understand them all.

**Every subdirectory is a separate git repository** with its own history and its own
GitHub remote. The `security` repo (this directory) is only the **workspace binder** —
the services' code is gitignored in it. The workspace versions only:

- the aggregator `pom.xml` (builds everything with one command),
- `docker-compose.yml` + the `infra-*.sh` scripts (run the whole stack locally),
- documentation (`docs/`, including this file), the backlog (`todo.md`), tools
  (`aggregate_allure.py`, `build_features.py`, `build_javadocs.sh`).

**The most important practical consequence:** a commit in the workspace **does not
touch** the services. To change a service's code you enter its directory
(`cd microservice-...`) and commit **there**, against ITS history.

---

## 2. The foundation: language and building

> 🏷️ **Tags:**
> **JDK 25** — the Java compiler + virtual machine; **virtual threads (Loom)** — cheap JVM threads, you can have millions;
> **Maven** — the build tool (compilation, dependencies, tests, packaging); **pom.xml** — Maven's configuration file;
> **Maven Wrapper (`./mvnw`)** — a script that downloads the right Maven version itself (3.9.9);
> **reactor** — Maven's multi-module build, in dependency order;
> **`~/.m2`** — Maven's local artifact repository on your disk.

The whole backend is **Java 25**. Frontends are TypeScript (section 12), the auxiliary
stubs — Python. Virtual threads are used by `user-collections` (Helidon SE) and
`formula-simulator`.

**Maven** reads `pom.xml` ("my name is X, I depend on these libraries, build me like
this"). Always use `./mvnw`, never the system `mvn`. The workspace `pom.xml` is a **pure
aggregator** — it lists the services as `<module>`s but **is not their parent** (each
service has its own parent and builds standalone; don't change that, because it would
mean editing several separate repositories).

The reactor resolves inter-project dependencies itself — `./mvnw clean install` in the
workspace builds the PORTAL's modules in the right order, without pre-installing
anything into `~/.m2`. All modules share the coordinates
`com.jrobertgardzinski:*:1.0.0-SNAPSHOT`.

**The exception — the F1 game (a separate product!):** `formula-simulator` is
deliberately NOT a reactor module (verdict 2026-07-11). You build it standalone, on its
own pom: `./mvnw -f formula-simulator/pom.xml clean verify` — and the only workspace
library it needs is installed once: `./mvnw -pl offline-jwt -am install`.

| Command | What it does |
|---|---|
| `./mvnw clean install` | Build the whole PORTAL (slow the first time — downloads dependencies); the game builds separately (exception above) |
| `./mvnw -pl microservice-security -am clean verify` | One project + what it depends on (`-am` = also make) |
| `./mvnw test` / `verify` / `package` | unit tests / +integration / build the jar |
| `-DskipTests` | skip tests (when you only want the jar) |

Cheat sheet: `maven-cheatsheet.md` in the workspace root.

---

## 3. Git in this project

> 🏷️ **Tags:**
> **git multi-repo** — a dozen-plus independent repositories side by side; **remote / origin** — the repo's remote copy on GitHub;
> **gh (GitHub CLI)** — GitHub from the terminal (PRs, repos, API); **PAT** — Personal Access Token, the password for pushing over HTTPS;
> **Co-Authored-By** — a commit footer naming a co-author.

- Canonical author: `Robert Gardziński <jrobertgardzinski@gmail.com>` (the history of
  all repos was rewritten to it).
- Push works via `credential.helper store` + a PAT. `gh` is installed at
  `~/.local/bin/gh` and logged in.
- Some repos are **private** (`formula-simulator`, `microservice-idp`), the rest are
  public — that matters for CI (section 15).
- Backlog: `todo.md` in the workspace (cross-cutting) + `todo.md` in every sub-repo
  (local). **That's the first place to check "what happened and what's next".**

---

## 4. Architecture: hexagonal (ports and adapters)

> 🏷️ **Tags:**
> **hexagonal architecture / ports and adapters** — business logic separated from technology;
> **DDD (Domain-Driven Design)** — modelling code around business-domain concepts; **value object** — a small immutable object with invariants (e.g. `EmailAddress`);
> **use case** — one application operation as a class with `execute(...)`;
> **port** — an interface stating what the logic needs; **adapter** — a concrete implementation of a port (JDBC, HTTP, in-memory);
> **ADR (Architecture Decision Record)** — a short document capturing an architectural decision and its reasons.

The most important pattern in the project. Code is arranged in layers, dependencies
**pointing down only**:

```
infrastructure (adapters)      <- the outside world: HTTP, database, Kafka, UI
     |  calls
application (use cases)        <- "what the application does": SaveItem, DeleteComment...
     |  uses ports (interfaces)
domain (model + rules)         <- pure business rules, zero technology
```

- **domain** — the pure model (`ItemRef`, `Comment`, `Driver`), without a single line
  about a database or HTTP.
- **application** — use cases depending exclusively on **ports** (e.g.
  `CollectionStore` — "I can save/remove/list", it doesn't say HOW).
- **infrastructure** — adapters: `JdbcCollectionStore` (production),
  `InMemoryCollectionStore` (tests). Swap the adapter → change the technology without
  touching the logic.

`microservice-security` slices this even finer, into **six layer-modules**:
`security-domain` → `security-config` → `security-system` → `security-application` →
`security-infrastructure` → `security-ui`. The **config** layer is a project
peculiarity: all the "knobs" (limits, TTLs, policies) are **framework-free records** in
`security-config`; the infrastructure only binds properties onto them. That makes the
configuration unit-testable.

### One pattern, different dialects — the per-service map

**What all services share is the DEPENDENCY RULE (inward), not package names** — the
variety is deliberate (portfolio!). Who speaks how:

| Service | Package/module layout | Dialect |
|---|---|---|
| `microservice-security` | `domain → config → system → application → infrastructure → ui` (6 Maven MODULES) | full hexagon, finest split; `system` = use cases, `application` = orchestration/services |
| `formula-simulator` | `domain / config / system / application / infrastructure` (same layers, ONE module) | the same dialect as security — packages instead of modules; verified: zero `infrastructure` imports from inner layers |
| `microservice-comments` | `domain / application / config / infrastructure` | 4-package hexagon (no separate `system` — use cases live in `application`) |
| `microservice-user-collections` | `domain / application / infrastructure` | minimal hexagon, 3 packages |
| `microservice-offboarding` | `application / infrastructure` | a hexagon WITHOUT a domain — the saga is a PROCESS, not a model: use cases over a `SagaStore` port, all JSON/Kafka in infrastructure (`EventsRouter` kept pure — driven by scenarios and pacts) |
| `microservice-memes` | `domain / application / config / infrastructure` + `image`, `tags` (7 modules) | "layered modules": layers + extracted capabilities; the framework lives in ONE module of seven |
| `microservice-email` | `boundary / control / entity` | **BCE** — deliberately a DIFFERENT pattern from the same family (Quarkus); boundary≈adapter, control≈use case, entity≈domain |
| `microservice-paddock` | `events / feed / myservers / notifications / registry / workshop / infra` | **package-by-feature**: vertical features instead of horizontal layers — a third way of slicing |

The moral: when you move between services, look for the same RULE ("logic doesn't know
technology; dependencies point inward"), not for the same directories. `system` vs
`application` is a security/formula dialect matter: there, use cases and orchestration
live apart.

**Decisions are written down as ADRs** — `docs/adr/` in the workspace (0001: the domain
does not defend against null, the application layer guards it; 0002: the `_` prefix for
use-case steps; 0003–0005 — sections 9–10; **0006: commands are idempotent BY
DEFAULT** — the law is enforced by one generic test, BDD scenarios remain for exceptions
and response contracts). Before you question something "weird", check whether there's an
ADR about it.

### Spec-first: Gherkin and Cucumber

> 🏷️ **Tags:**
> **Gherkin** — the human-readable `Given/When/Then` scenario language (`.feature` files);
> **Cucumber** — the engine executing Gherkin scenarios as tests; **glue/steps** — the code binding scenario sentences to application calls;
> **spec-first** — the executable specification first, the code after.

Behaviour is described **first** in `.feature` files, then Cucumber executes them as
tests:

```gherkin
Scenario: Saving twice tells the caller it was already there
  Given alice has saved meme 42 into "favourites"
  When alice saves meme 42 into "favourites"
  Then the save reports it was already there
  And alice's "favourites" contains meme 42 once
```

A reading note (and **ADR 0006**, the owner's verdict): the scenario does NOT test
idempotency — **command idempotency holds by default, as a law**, enforced by ONE
generic test per service (`IdempotentCommandsTest`: every command 2× = the state as
after 1×), not by a boilerplate scenario per operation. The scenario above pins what
really is per-operation: the **RESPONSE contract** ("already there" — the UI knows
nothing new was created). A different response does not break idempotency — like PUT:
first time 201, second time 200, same state. `Given has saved` vs `When saves` is
a Gherkin idiom: pre-existing state vs the action under test.

Specification = test: if the documentation drifts from the code, a test goes red.
The project's signature move: **the same scenario driven through several entrances** —
once through the application layer (fast), once through the HTTP black box, once
through the real browser UI. `microservice-security/specs/` holds 16 `.feature` files —
the best catalogue of "what this service can do".

---

## 5. The system map

> 🏷️ **Tags:**
> **flavour** — the framework a given service is realised in; **BCE (Boundary-Control-Entity)** — the alternative layering used in microservice-email;
> **PWA** — a page installable like a mobile app; **SSE (Server-Sent Events)** — a server-to-browser event stream over HTTP.

### Services

| Service | Flavour | Port | Responsibility |
|---|---|---|---|
| `microservice-security` | **Micronaut** (hexagonal, 6 layers) | 8080 | Accounts, sign-in, JWT, MFA, OAuth, sessions; on account deletion it announces a FACT and awaits one portal verdict (saga orchestration extracted to `microservice-offboarding`, 2026-07-11) |
| `microservice-email` | **Quarkus** (BCE, Qute templates) | 8082 | Mail delivery (`POST /mails*`, X-Api-Key), consumer of `mail-requests` |
| `microservice-memes` | **Spring Boot** (multi-module, layered) | 8083 | The meme gallery: upload, thumbnails, votes, moderation/NSFW, UI at `/` |
| `microservice-comments` | **Spring Boot** (single-module) | 8085 | Comment threads under memes + votes |
| `microservice-paddock` | **Javalin** (vertical slices, PWA) | 8086 | The social hub: game servers, memberships, events with RSVP |
| `formula-simulator` | **no framework** (JDK HttpServer) | 8084 | The F1 manager with autonomous drivers; SSE; a SEPARATE PRODUCT outside the reactor (builds standalone) — section 16 |
| `microservice-user-collections` | **Helidon 4 SE** (virtual threads) | 8092 | Generic collections of a user's refs (favourites); 3rd saga participant |
| `microservice-offboarding` | **Helidon 4 SE** (process manager) | 8094 | The PORTAL-side orchestrator of the account-deletion saga (extracted from security); participants = configuration |
| `collections-ui` | React Native Web + nginx | 8093 | The favourites UI on its OWN origin (deliberately, to exercise CORS) |
| `microservice-idp` | Python | 8091 | The **OIDC stub** — "Sign in with Google" without Google (dev/tests) |
| `microservice-image` | Python + Pillow | internal (8087) | PNG→WebP conversion for memes |
| `microservice-sms` / `-push` | Python | internal (8088/8089) | The paddock's notification channels (stub-send) |
| `race-sim` | Python (stdlib) | internal (8090) | The formula race-simulation module — **no host port** (section 16) |

### Shared libraries (separate repos, consumed mostly by security)

| Library | What it gives |
|---|---|
| `test-starter` | Test-dependency bundles: `unit-`/`bdd-`/`system-test-starter` |
| `libs` | Validation/constraint primitives (artifact `constraint`) |
| `config` | The configuration ladder: `ConfigValue`, `Configuration.liveOver/boundOver`, the settings snapshot |
| `email` | E-mail address value objects (`email-domain`, `-config`, `-usecase`) |
| `password` | Password value objects and policy (`password-domain`, `-config`, `-usecase`), hashing algorithms (**Argon2**) |
| `adjustable-clock` (+ `infrastructure-micronaut-clock`) | A steerable test clock + the Micronaut adapter |
| `voting` | The voting bounded context as a library (toggle + tally over a `Ballots` port) — used by memes and comments |
| `offline-jwt` | **New 2026-07-10:** the shared offline JWT verification (section 7) |

---

## 6. microservice-security in depth

The richest service — the identity core for everything else. Every other service, when
it needs to know **who is talking to it**, ultimately relies on this one. This section
walks the topic bottom-up, assuming you have never built sign-in before. Read the
subsections in order — each builds on the previous one.

The full capability catalogue = `specs/*.feature`: register, authenticate, verify-email,
reset-password, change-email, change-password, logout, list/revoke sessions, refresh +
reuse-detection, federated-sign-in, authorize, mfa, mfa-passkey, delete-account.

### 6.1 The problem being solved

A dozen services, one user. Two things must hold:

1. **Authentication** — "prove you are alice". Only security ever sees a password.
2. **Propagating that proof** — when alice then uploads a meme to a *different* service,
   that service must be able to trust "this really is alice" **without** seeing her
   password and ideally without asking security every single time.

The industry-standard answer to (2) is a **signed token**, and that is what security
issues. Everything below is variations on "how do you get the token" and "how do others
check it".

### 6.2 The life of an account — the happy path

> 🏷️ **Tags:**
> **verification link** — the "click to confirm your address" mail; **prefetcher** — mail programs that pre-open links in messages (why the link must not be a plain GET);
> **anti-enumeration** — responses never reveal whether an address already exists.

Follow one user, in order (you can literally click this through — section 17):

1. **Register** (`register.feature`): alice submits an address + password. Security
   stores the password only as a **hash** (a one-way scramble; you can check a guess
   against it but never recover the original) and sends a verification mail. In dev all
   mail lands in **Mailpit** (http://localhost:8025) — a fake inbox for the whole stack.
2. **Verify the address**: alice clicks the link in the mail. Subtlety: the link opens
   the **gallery page** (`:8083/?verify=...`), and the page then POSTs the token to
   security. Why not a simple GET link straight into the API? Because corporate mail
   scanners and preview **prefetchers** open links automatically — a GET that verifies
   on open would get "clicked" by a robot before alice ever sees the mail.
3. **Sign in** (`authenticate.feature`): address + password. Until the address is
   verified, sign-in is refused — that is the gate from step 2. On success alice
   receives **two tokens** (next subsection).
4. **Use the system**: every request to any service carries
   `Authorization: Bearer <token>` — like showing a festival wristband at each tent.
5. **Stay signed in / sign out**: tokens expire quickly on purpose; the refresh token
   (6.5) renews them. Logout (or "revoke session" from the sessions screen) kills the
   session server-side.

### 6.3 What exactly is the token (JWT)

> 🏷️ **Tags:**
> **JWT (JSON Web Token)** — a signed identity "ticket": readable payload + a cryptographic signature; **claim** — one field of the payload (who, roles, expiry...);
> **EdDSA** — the signature algorithm used here (asymmetric: sign with a private key, verify with a public one);
> **JWKS** — security's public keys, published at `/.well-known/jwks.json`, that anyone can use to verify the signature.

A JWT is three base64 chunks glued with dots: `header.payload.signature`. The
**payload is not encrypted** — anyone can decode and read it (paste one into jwt.io and
see). What makes it trustworthy is the **signature**: security signs the payload with
its **private key**, which never leaves security. Anyone holding the matching **public
key** can check that (a) security really issued this token and (b) nobody altered
a single character since. Forging a token without the private key is computationally
infeasible.

The claims carried here: **who** (the user id), **roles** (USER/MODERATOR/ADMIN),
**`mfaCompliant`** (did they complete MFA — see 6.7), and **`exp`** (expiry). Public
keys are published at `/.well-known/jwks.json` (**JWKS**) — that endpoint is how other
services verify signatures on their own.

### 6.4 How other services check the token — two ways, both on purpose

> 🏷️ **Tags:**
> **introspection** — asking security's `/me` about a token on every request; **offline verification** — checking the signature yourself against JWKS;
> **revocation** — invalidating a token server-side before it expires; **fail closed** — when unsure, refuse.

Think of the token as an ID card. A service that receives one has two options:

- **Introspection** — *phone the issuing office*: call security's `GET /me` with the
  token. Costs a network hop per request, but security answers with the **current**
  truth — a token revoked by logout is refused instantly. This is how **memes** runs in
  compose.
- **Offline verification** — *check the hologram yourself*: fetch the JWKS once, then
  verify each token's signature and expiry locally. No network hop, and it keeps
  working even if security is down — but a stolen-and-revoked token stays "valid" in
  your eyes until its `exp` passes. This is how **comments, paddock, formula and
  collections** run, via the shared `offline-jwt` library (section 7).

Neither is "the right one" — it is a genuine trade-off (revocation freshness vs
latency/resilience), and the stack deliberately keeps one live example of each so the
trade-off can be narrated with running code. Both fail **closed**: an unverifiable
token = an anonymous caller, never a trusted one.

### 6.5 Sessions and refresh tokens

> 🏷️ **Tags:**
> **access vs refresh token** — the short-lived "wristband" vs the longer-lived "renewal coupon";
> **reuse detection** — spending the same refresh token twice reveals theft; **session family** — all tokens descending from one sign-in.

Why does the access token expire in minutes? Damage control: a leaked token is only
useful briefly. To avoid re-typing the password every few minutes, sign-in also issues
a **refresh token** — a longer-lived, single-use coupon exchanged at security for
a fresh token pair. Each exchange **spends** the coupon and issues a new one.

That single-use property enables **reuse detection**: if a spent refresh token shows up
again, two parties hold the same coupon — one of them is a thief (someone copied the
token before it was spent). Security cannot tell which one is legitimate, so it revokes
the **whole session family** descending from that sign-in. Honest alice has to sign in
again — mildly annoying; the thief is locked out — the point. The sessions screen in
security-ui lists a user's active sessions and lets them revoke any one by hand.

### 6.6 Sign-in with Google/GitHub (OAuth2 / OIDC)

> 🏷️ **Tags:**
> **OAuth2 / OIDC** — "sign in through an account you already have elsewhere"; **IdP (identity provider)** — the external party vouching for the user;
> **PKCE** — protection of the code-for-token exchange; **stub IdP** — the project's fake "Google" (:8091) for dev and tests;
> **federated account** — an account whose proof of identity comes from an IdP, not a local password.

The "Google"/"GitHub" buttons in the gallery. The idea: instead of a local password,
an external **identity provider** vouches — "Google confirms this is alice@gmail.com" —
and security creates/signs-in the account on that basis. Such **federated** accounts
are passwordless here.

In dev **you don't need real Google**: both buttons point at the **stub IdP**
(:8091) — a small Python service speaking just enough of the OIDC protocol to play
Google's role (it even shows a mock consent form). Production swaps only env vars —
recipes in `microservice-security/docs/oauth-providers.md`, including a tested
Keycloak. Two provider shapes are supported, because the ecosystem is split: ID_TOKEN
(identity arrives as a signed token — the Google shape) and USERINFO (identity is
fetched from an endpoint — the GitHub/Facebook shape). One more subtlety: when a user
changes their e-mail address, their federated links **follow the account**
(`relinkAll`) instead of dangling on the old address.

### 6.7 MFA — more than a password

> 🏷️ **Tags:**
> **MFA (multi-factor authentication)** — proving identity with more than one independent factor; **TOTP** — 6-digit codes from an Authenticator-style app;
> **WebAuthn / passkey** — sign-in by a cryptographic signature from your phone/hardware key; **recovery codes** — one-time printed backup codes;
> **step-up** — re-authenticating right before a sensitive operation; **MFA floor** — consumers strip privileged roles from callers without completed MFA.

A password can be phished or guessed; MFA demands a second, independent proof.
Security models sign-in as a **factor chain** — link #1 is the password (or an OAuth
provider), then any of: a code sent by e-mail/SMS, **TOTP** (the 6-digit
Authenticator-app codes, derived from a shared secret + the clock), **WebAuthn
passkeys** (your phone or hardware key signs a challenge — phishing-resistant, nothing
to retype), or **recovery codes** (a batch of one-time codes shown exactly once at
setup, each consumed atomically — the "I lost my phone" escape hatch).

Two consequences ripple beyond sign-in:

- **Step-up**: some operations are too sensitive to trust an old session. Per-action
  policies force re-authentication *right now*: account deletion = FULL_CHAIN (redo
  everything), password change = SECOND_FACTORS. The gallery's account-deletion dialog
  performs a real step-up — try it.
- **The MFA floor at consumers**: the token's `mfaCompliant` claim says whether the
  chain was completed. A moderator/admin **without** completed MFA is treated by
  memes/comments as a plain USER (`Caller.withMfaFloor`) — privileged powers require
  the stronger proof, and when in doubt the system fails **closed** (drops privileges
  rather than granting them).

### 6.8 Defensive hygiene

> 🏷️ **Tags:**
> **brute-force lockout** — a temporary block of a source after a streak of failed sign-ins; **throttle / rate limit** — capping request frequency per source;
> **anti-enumeration** — responses never reveal whether an address exists; **GDPR delete** — full account removal together with the user's content.

The unglamorous layer that makes the rest hold up:

- **Lockout**: a streak of failed sign-ins temporarily blocks the source — a password
  guesser gets a handful of attempts, not millions.
- **Registration throttle**: per-IP cap on account creation (raised in compose so the
  smoke test does not trip it).
- **Anti-enumeration**: no response may betray whether an address is registered —
  that alone is valuable data to an attacker (which of these 10 000 leaked addresses
  have an account here?). Flagship example: changing your e-mail to an address that is
  already taken answers **exactly** like a fresh one (202 + a note delivered by mail).
  The difference plays out privately, in the inbox, never in the API response.
- **GDPR delete**: `DeleteAccount` clears sessions → factors → codes → federated links
  → the user, then triggers the cross-service content saga (section 8) so the user's
  memes/comments/favourites are handled too.

### 6.9 A rule for reading (and writing) the specs

**The abstraction-level rule (the owner's verdict 2026-07-11, "the argon2 rule"):**
a feature speaks the USER's language, never the protocol's. `authenticate.feature` knows
no argon2 — hashing is a detail under the hood; likewise the passkey spec knows neither
"WebAuthn" nor "challenge" (it says: "the device holding the passkey must prove
presence") — the protocol's name may live only in the glue (`webauthn.steps.mjs`),
because the glue IS the mask.

---

## 7. offline-jwt — a lesson about duplication

> 🏷️ **Tags:**
> **shared library vs copied code** — the two ways to reuse logic between services, each with a price;
> **coupling** — services no longer able to change independently, because they share a moving part;
> **copy drift** — copies of "the same" code silently diverging over time.

This small library is the concrete form of the "check the hologram yourself" option
from 6.4: it fetches security's public keys (JWKS) and then verifies each bearer
token's signature and expiry locally. Four services use it, and its whole API is two
lines:

```java
OfflineJwtVerifier verifier = OfflineJwtVerifier.overHttp(securityUrl, objectMapper);
Optional<VerifiedToken> caller = verifier.verify(bearerToken);  // empty = fail closed
```

`verify` returns the confirmed identity (who + roles + `mfaCompliant`) or an **empty**
Optional. Empty means "treat the caller as anonymous", never "let it through and hope" —
fail-closed, in code form.

Why the library gets its own section: it teaches a rule. When several services need the
same logic, you can either **share a library** (one place to fix, but now every change
ships to everyone — the services are *coupled*) or **copy the code** (each service free
to evolve, at the cost of maintaining copies). Microservice folklore usually prefers
copying — coupling is what microservices exist to avoid. And that is how this
verification started: **five identical copies** (memes, comments, paddock,
user-collections, formula) with a "change one, change both" comment.

The comment did not work — it never does. Converging the copies into `offline-jwt`
(2026-07-10) uncovered **real drift**: the memes copy had silently lost the MFA floor,
so a moderator without MFA kept, offline, the privileges introspection would have
stripped. Nobody had noticed, because each copy was tested only inside its own repo.

Hence the project rule: between services duplication usually beats coupling, **but not
for security-critical code** — there a silent divergence is not a style problem, it is
a hole. Note the line drawn: only the **verification core** is shared; each service
still keeps its own *policy* about what to do with the verified identity (e.g.
`Caller.withMfaFloor` lives in the service, not the library).

---

## 8. Inter-service communication

> 🏷️ **Tags:**
> **synchronous REST/HTTP** — you call and wait for the answer; **Apache Kafka** — the event backbone; **topic** — a named event channel;
> **transactional outbox** — a table guaranteeing the state change and its event leave together; **poller** — the thread draining the outbox to Kafka;
> **at-least-once + dedup** — "at least once" delivery, the consumer deduplicates; **DLQ (dead-letter queue)** — the parking lot for unprocessable events, with redrive;
> **saga** — a distributed step sequence with confirmations; **orchestrator** — the component tracking who has confirmed;
> **correlation-id (cid)** — an identifier travelling with a request through all services (HTTP header and Kafka header).

Two ways, both used deliberately:

**a) Synchronously (HTTP)** — a phone call: you ask and hold the line until the answer
comes back. E.g. memes asks security `/me` on upload. Simple to reason about; the price
is that both sides must be up at the same moment — if the callee is down, the caller
waits or degrades.

**b) Asynchronously (events on Kafka)** — a bulletin board: the sender pins a message
("account 123 requested deletion") on a named board — a **topic** — and moves on,
neither knowing nor caring who reads it. Consumers read at their own pace; one that was
down catches up on the backlog when it returns. **Kafka** is the server that keeps those
boards durable and ordered. The stack's topics: `mail-requests`, `content-commands`,
`memes-events`, `comments-events`, `usercollections-events`.

**Transactional outbox** — the fix for a classic trap. A service that changes its
database AND publishes an event performs two writes into two different systems, and no
transaction spans both: crash between them and you get a state change nobody was told
about — or an event about a change that never happened. The fix: security writes the
event into its own `outbox_events` **table**, in the **same database transaction** as
the state change — one transaction, so the change and its event either both happen or
neither does. A background **poller** then drains the table to Kafka. The event may
reach Kafka with a small delay, or even twice — but never inconsistently with the
database (hence "at-least-once + dedup" in the tags: consumers must shrug off
a duplicate). The outbox row also carries the **cid** (column, V14) and the **W3C
`traceparent`** (V16) — which is why one operation's log and trace stitch together
across asynchronous boundaries (section 14).

**The account-deletion saga** — the flagship flow. First, why a "saga" at all: deleting
an account touches four services' databases (security, memes, comments, collections),
and there is no such thing as one transaction across four databases. A **saga** is the
distributed substitute: a sequence of local steps, each confirmed by an event, with
a coordinator — the **orchestrator** — tracking who has confirmed and deciding the
outcome, including the unhappy path ("someone failed → unlock, apologise"). Since the
extraction of 2026-07-11 the orchestrator is **`microservice-offboarding`** (the
PORTAL's process manager):
1. security locks the account and announces the FACT `ACCOUNT_DELETION_REQUESTED` on
   `security-events` (via the outbox; the fact carries the user's wizard choices as an
   opaque map),
2. **offboarding** opens the saga and publishes `PURGE_USER_CONTENT` on
   `content-commands`,
3. **the three participants** clean up and confirm (`USER_CONTENT_PURGED`): memes (per
   `ContentPurgePolicy` — DELETE/ANONYMIZE/KEEP), comments (ditto), user-collections
   (wholesale, the refs are opaque),
4. offboarding collects the full set of confirmations and announces ONE verdict on
   `offboarding-events`: `PORTAL_CONTENT_PURGED` (security deletes the account for good
   + a farewell mail) or — after a 2-minute timeout — `PORTAL_PURGE_FAILED` (security
   unlocks the account + an apology mail). Security also keeps its own safety net:
   5 minutes of silence (a dead orchestrator) unlocks the account too.

**Why so (an old debt — PAID OFF 2026-07-11):** previously security knew the three
participants BY HEART (columns in the saga table!) and the identity domain knew the
portal's content axes by name — a "security + game only" deployment could not delete an
account. After the extraction: **participants are offboarding CONFIGURATION**
(`OFFBOARDING_PARTICIPANTS=name=topic,...` — a new content service adds itself in
compose, zero security code changes), confirmations are ROWS not columns,
`PurgeChoices` is a generic map, and a pure-identity deployment sets
`account-deletion.await-portal-purge=false` and deletes immediately. Idempotency:
a duplicate fact finds its saga by the fact's `id` (the replay key), the
STARTED→COMPLETED transition is a one-shot latch.

**The trap (mitigated):** a new service holding user content still must join the saga —
but now that is an entry in offboarding's configuration + its own consumer/confirmation,
not a change in security.

**ADR 0005 — two integration styles with email, on purpose:** mails *owed* after a state
change (registration, reset, the saga) go through the outbox/Kafka (they must not be
lost); the paddock's *best-effort* notifications (an event reminder) go by synchronous
HTTP fan-out to email/sms/push (short timeout, an empty URL disables the channel). A new
integration chooses **by the obligation rule**, not by copying its neighbour.

**ADR 0004 — event versioning:** every envelope carries `"version": 1`. Within
a version, changes are **additive only** (fields someone reads never vanish or change
type); consumers are **tolerant readers** (take their fields, ignore the rest).
A breaking change = a version bump + expand/contract (the old shape emitted alongside
the new one until everyone has moved).

---

## 9. Contracts between services (CDC / Pact)

> 🏷️ **Tags:**
> **CDC (consumer-driven contracts)** — the consumer declares what it uses, the producer verifies it; **Pact** — the standard CDC tool;
> **pact** — the generated JSON file with the consumer's expectations; **Pact broker** — the central pact server (here REPLACED by the workspace layout);
> **provider state** — the state the producer prepares before verifying an HTTP pact; **tolerant reader** — a consumer ignoring unknown fields.

The problem, concretely: memes reads the field `userId` out of security's purge
command. One day security renames it to `accountId`. Security's build stays green (its
own tests still pass), memes' build stays green (its tests feed it fixtures with the
old name) — and the live stack breaks. Unit tests cannot catch this, because each side
tests only itself, against its own *idea* of the message.

**CDC** closes the gap with a two-step handshake:

1. The **consumer** (e.g. memes) writes a pact test: it feeds its REAL consuming code
   an example payload and records **only the fields it actually reads** into a JSON
   file — the **pact**. The pact is committed into `pacts/` in the consumer's repo
   (HTTP pacts separately in `pacts-http/` — a Pact V3 file does not mix styles).
2. The **producer** (security) replays every consumer's pact against its REAL producing
   code: "produce the message exactly as production would — does it still satisfy what
   memes recorded?" Renaming `userId` now fails **security's** build, with "memes" in
   the error message.

The classic setup adds a **Pact broker** — a server ferrying pact files between teams'
CI pipelines. Here (**ADR 0003**) the workspace layout replaces it: every consumer and
producer sit next to each other on disk, so the producer simply reads the sibling
checkout (`@PactFolder` pointing at `../../<consumer>/pacts`). Sibling absent = **skip,
not fail** (a standalone build doesn't fall over); CI always checks out and verifies.

Coverage: both sides of the saga (the purge commands AND the confirmations — security
is at times producer and consumer), 6 mail shapes, and two HTTP contracts: JWKS (the
consumer is the `offline-jwt` library!) and the `/me` introspection (the memes pact,
with a **provider state** — before verifying, the producer prepares a real signed-in
user, register→verify→authenticate, so the check runs against reality, not a mock).

The effect: a producer's breaking change goes red **in the producer's build**, with the
consumer's name in the message — not in the live stack.

---

## 10. Data storage

> 🏷️ **Tags:**
> **PostgreSQL** — the relational database; **database-per-service** — every service has its OWN database, nobody rummages in another's;
> **H2** — the in-memory database for dev/tests (Postgres compatibility mode → one adapter); **Flyway** — versioned schema migrations as `V1__*.sql` files;
> **MinIO / S3** — object storage for binaries (images), a local server speaking the S3 protocol.

- Six services hold durable data and **each has its own Postgres** (security, memes,
  comments, paddock, formula, collections).
- Without `DB_URL` a service comes up on **in-memory H2** — that's how tests and quick
  dev runs go.
- The schema is versioned by **Flyway**: on startup the service executes the missing
  migrations (`src/main/resources/db/migration/V*.sql`). In security the migrations
  reached V16 — you'll see the numbers in the todo as "V13 recovery codes", "V14 cid in
  the outbox" etc.
- `memes` keeps metadata in Postgres and the **image bytes in MinIO** (the
  `S3ObjectStore` adapter works with both MinIO and real S3). Note: memes
  **deduplicates identical bytes** by hash — two uploads of the same PNG are one meme
  (this bit the e2e tests once).

---

## 11. Running the whole: Docker and Compose

> 🏷️ **Tags:**
> **Docker** — packs an application with its environment into an isolated container; **image vs container** — the template vs a running instance; **Dockerfile** — the image recipe;
> **Docker Compose** — one YAML file describing all containers, the network and variables; **healthcheck** — the "is the service REALLY ready" probe dependents wait for;
> **smoke test** — a quick end-to-end "are the basics alive" test; **Mailpit** — a fake SMTP server with a web mail viewer.

You don't run Compose by hand — there are scripts in the workspace root:

| Script | What it does |
|---|---|
| `./infra-up.sh` | Builds the jars on the host, fetches the OTel agent, brings up the whole stack |
| `./infra-smoke.sh` | Proves the flows end to end (registration→mail→verification→sign-in→upload→account-deletion saga→favourites CORS) |
| `./infra-down.sh` | Stops and cleans up (`-v` also wipes the database volumes) |
| `./memes-up.sh` / `./formula-up.sh` | Stack slices (the gallery / the formula with the dev drive-ui via `docker-compose.dev.yml`) |

All containers have **healthchecks** (bare TCP probes — the temurin/python images ship
no curl), and dependents wait for `service_healthy` instead of racing Kafka's/security's
startup.

**Ports worth knowing by heart:**

| Port | What |
|---|---|
| 8080 | security (API) |
| 8082 | email (API, X-Api-Key) |
| 8083 | **the meme gallery** (UI; also the Google button and the favourite stars) |
| 8084 | formula-simulator (race viewer) |
| 8085 / 8086 | comments / paddock (PWA) |
| 8091 | the stub IdP (the "Google sign-in" form) |
| 8092 / 8093 | user-collections (API) / collections-ui (favourites UI) |
| 8094 | offboarding (health/metrics; the saga lives on Kafka) |
| 8025 | **Mailpit** — the dev inbox (all mail lands here) |
| 3000 / 9090 | Grafana / Prometheus |

Kafka (KRaft, single-node), MinIO, Loki, Tempo, Promtail, cAdvisor and node-exporter run
inside the compose network. `race-sim` **deliberately has no host port** (section 16).

---

## 12. Frontends

> 🏷️ **Tags:**
> **React** — the component UI library; **TypeScript** — JavaScript with types; **Vite** — the frontend bundler/dev-server;
> **Material UI** — ready-made components (the gallery); **React Native Web** — React Native components rendered in the browser;
> **nginx** — the static-file server (serves collections-ui); **CORS** — the browser mechanism controlling cross-origin requests; **preflight** — the trial OPTIONS request before the real one;
> **Expo / React Native** — the formula's mobile app; **PWA** — the paddock's installable page.

- **security-ui** (in the security repo) — React + TS (rewritten from Angular;
  preference: React). Account, MFA and session screens; split into presentational
  components + state in `App`.
- **memes-ui** (a memes module) — React + TS + Material UI, built by Vite through
  frontend-maven-plugin and **packed into the jar** (Spring serves it at `/`). Dev:
  `cd memes-ui && npm run dev`.
- **collections-ui** (in the user-collections repo) — React Native **Web** + Vite,
  served by nginx on **its own origin :8093 on purpose**: the browser calls security
  and collections **cross-origin**, so real CORS gets exercised (a hand-rolled
  `CorsFilter` in Helidon, an origin allowlist, preflight 204). The star on a gallery
  tile saves a favourite straight into collections; the "Favourites" wall hydrates the
  refs, and a deleted meme shows an "unavailable" tile — **silent degradation**: with
  collections down, the gallery works without stars.
- **paddock** — a mobile-first PWA served by the service itself.
- **formula-simulator/app** — the mobile app (Expo/React Native); the race viewer at
  :8084 is a separate, built-in front (SVG + SSE).

---

## 13. Tests — levels and tools

> 🏷️ **Tags:**
> **JUnit 5** — the base test framework (`@Test`); **test pyramid** — many fast unit tests, fewer integration, fewest E2E;
> **Testcontainers** — a real database/MinIO in Docker for the duration of a test; **RestAssured** — "over the wire" HTTP tests;
> **cucumber-js + Playwright** — Gherkin scenarios executed in a REAL browser (Chromium), with a virtual authenticator for passkeys;
> **Allure** — test reports; **living documentation** — flat markdown documents generated from tests and sources (`docs/features.md`, `docs/javadocs.md`, `allure-summary.md`).

The floors (bottom up):
1. **Unit** (JUnit 5) — domain/config/system, seconds.
2. **Use cases through Cucumber** — `.feature` scenarios on in-memory adapters.
3. **Integration/wire** (RestAssured, Testcontainers) — the HTTP black box, a real
   database.
4. **Contract (Pact)** — section 9.
5. **E2E through the browser** (cucumber-js + Playwright) — security-ui 36 scenarios,
   memes-ui, the gallery e2e with favourites; **the same Gherkin specifications as the
   floors below**, just a different entrance.
6. **Live-stack smoke** — `./infra-smoke.sh`.

Reports and documentation from tests:
- `aggregate_allure.py` + `allure-serve.sh` — the aggregate Allure report over all
  projects; `allure-summary.md` — the current coverage summary in markdown.
- `build_features.py` → `docs/features.md` — the catalogue of every Gherkin `.feature`
  across the three workspaces (titles, descriptions, scenarios) — the diffable spec
  surface.
- `build_javadocs.sh` → `docs/javadocs.md` — runs `javadoc:javadoc` through the three
  reactors and indexes the generated HTML (in `target/`, gitignored).
- `create-documentation.sh` — regenerates all of the above in one go.

---

## 14. Observability — seeing what happens

> 🏷️ **Tags:**
> **Prometheus** — collects metrics (numbers: RPS, latencies, heap) by scraping `/metrics` endpoints; **Grafana** — dashboards over all the sources;
> **cAdvisor / node-exporter** — container and host metrics with zero code changes; **Loki + Promtail** — the log store + the collector of every container's stdout;
> **OpenTelemetry (OTel)** — the telemetry standard; **OTel agent** — attached to a JVM via `JAVA_TOOL_OPTIONS`, instruments HTTP and Kafka without code changes;
> **Tempo** — the trace store; **trace / span** — a request's timeline across services / one segment of it; **alerting** — Prometheus rules (TargetDown, Http5xxBurst).

Three signals, everything in **Grafana (http://localhost:3000)**:

- **Metrics**: Prometheus scrapes 10+ targets (every service exposes `/metrics` in its
  own flavour: micrometer, actuator, quarkus-micrometer, hand-rolled endpoints in
  paddock/formula). Dashboards: "Stack — containers", "Services — HTTP, JVM and logs",
  "Stack — availability and health" + alerts.
- **Logs**: Promtail collects the stdout of **all** containers through the Docker
  socket → Loki.
- **Traces**: the OTel agent (**must be 2.29.0+** — 2.11.0 loads on JDK 25 but
  instruments nothing) exports spans to Tempo. An account deletion = **one trace**
  through security, memes, comments, collections and email, because the outbox carries
  the `traceparent`.

**The thread through everything — the cid**: every request gets an `X-Correlation-Id`,
the cid lands in every log line, and rides over HTTP and in Kafka headers. In Grafana:
`{service=~".+"} |= "<cid>"` shows one request's whole journey across all services;
clicking `trace=<id>` in a log opens the waterfall in Tempo. **A real-life gotcha:**
**MDC** (Mapped Diagnostic Context — the logging library's per-thread pocket: stash
a value like the cid there once and every log line printed by that thread carries it
automatically) does not cross thread/async boundaries — which is why the cid is carried
in an outbox column and a request attribute, not "in the thread".

---

## 15. CI — GitHub Actions

> 🏷️ **Tags:**
> **CI (Continuous Integration)** — automatic build+tests on every push; **GitHub Actions** — GitHub's CI engine (`.github/workflows/*.yml` files);
> **independent deployability** — every service testable and deployable on its own, hence CI per repo.

Two levels:
- **Workspace** (`.github/workflows/ci.yml`): checks out 14 sub-repos, builds the whole
  reactor with one `./mvnw clean install` **plus the F1 game as a separate step**
  (a separate product outside the reactor, with no CI of its own — the workspace tests
  it standalone), and a second **e2e** job drives the specifications through real
  Chromium (both UIs, passkeys on a virtual authenticator).
- **Per repo** (since 2026-07-10 the PORTAL services have their own `ci.yml`; the game
  has none): builds the service standalone; security's CI additionally checks out the
  consumers' repos so pact verification also runs at the producer. Note: a private repo
  needs a PAT in the secrets (the default GITHUB_TOKEN reads only the owner's public
  repos).

---

## 16. formula-simulator — a separate world

> 🏷️ **Tags:**
> **JDK HttpServer** — the HTTP server built into Java, zero framework; **contract-first** — JSON schemas in `contracts/` as the Java↔Python↔user-bots treaty;
> **SSE** — the race broadcast to viewers; **determinism per seed** — the same simulation given the same seed;
> **bot sandbox / exam** — user-supplied code run under controlled conditions; **defense in depth** — a time limit + verdict cache + no network access;
> **eras as data** — regulation/physics packages as files, not code.

An F1 manager game inspired by Jagged Alliance 2 (drivers have attributes and
personality; history emerges from the simulation). **The repo is PRIVATE** and has its
own extensive document world — **the canon: `formula-simulator/docs/zalozenia-projektu.md`**,
the expansion plan: `docs/expansion-plan.md`, the backlog: `todo.md` (session history:
`todo-archiwum.md`). (The game's docs are Polish — it is the private product.)

- The **Java backend** (no framework) is authoritative: it builds the simulation
  request, calls the Python module, stores the timeline and replays it to clients over
  SSE — the server sends STATE, not pixels.
- The **race module** (`sim/race/`, Python stdlib): tick physics, tyres, dirty air,
  safety car, driver controllers behind the `DriverController` contract.
- **User bots**: players upload their own controllers; before admission a bot passes an
  **exam**. Protections (fresh, 2026-07-10): a hard exam time limit (a hostile bot
  cannot take the examiner hostage), verdicts cached by file sha (the same bytes never
  mill twice), and **race-sim has no host port** — the engine with its secrets lives
  only on the internal network; the world talks to it exclusively through the game's
  JWT gate.
- **The active development direction**: "eras as data" — 6 era packages
  (CIGAR/WINGS/TURBO/V10/V8/HYBRID) with per-component physics (turbo lag, ERS, brake
  fade, crossply/radial tyres...), phases F0–F9 (F0 done) and **two independent
  championships** on the shared engine: the agents branch (an AI benchmark) and the
  users branch (the JA2 persona).
- **The game's architecture maps (2026-07-11)** — before touching code, read the three
  maps: `docs/architektura-java.md` (backend), `docs/mapa-sim-python.md` (simulation
  modules) and `docs/infra.md` (the roads between them). Plus `docs/rodowod.md`:
  **every balance number has a written pedigree** — a historical anchor / a caricature /
  a knob; numbers without a pedigree are not added.
- After the "grand review" (2026-07-11): the economy (money) is **fail-closed**, bot
  licences sit behind the gate, and selling not-yet-existing features is blocked.
- The owner's manual driving (drive-ui) needs `docker-compose.dev.yml` →
  `./formula-up.sh`.

---

## 17. Getting started — day one

```bash
# 0. Requirements: JDK 25, Docker, git. Do NOT install Maven — ./mvnw is there.

cd ~/Documents/git/security
./mvnw clean install        # 1. the whole PORTAL reactor (takes a while first time)
./mvnw -f formula-simulator/pom.xml package -DskipTests   # 1b. the F1 game (separate product)
./infra-up.sh               # 2. the whole stack in Docker
./infra-smoke.sh            # 3. proof the flows work (green = OK)

# 4. Click around the live system:
#    http://localhost:8083  the gallery: create an account, click the link in Mailpit (:8025),
#                           sign in, upload a meme, star it
#    http://localhost:8093  the favourites wall (cross-origin!)
#    http://localhost:3000  Grafana: metrics, logs, traces
./infra-down.sh             # 5. cleanup
```

Then, in this order:
1. Read `microservice-security/specs/*.feature` — the behaviour catalogue of the core.
2. Trace the `domain → application → infrastructure` layout in
   `microservice-user-collections` — the smallest, cleanest hexagon example.
3. Open `docs/adr/` — six short decisions explaining the "oddities".
4. Make one request with your own `X-Correlation-Id` and find it in Loki + Tempo.
5. Change something small in one service, run its tests in its directory, and check in
   `pacts/` whether you touched a contract.

## 18. Where to find answers

| Question | Place |
|---|---|
| How do services connect? | [`docs/c4-architecture.md`](c4-architecture.md) — C4 diagrams **generated** from compose + pacts (`python3 build_c4.py`) |
| What happened recently / what's next? | `todo.md` (workspace) + each sub-repo's `todo.md` + the sub-repo's `git log` |
| Why was it decided this way? | `docs/adr/` (6 ADRs), `formula-simulator/docs/zalozenia-projektu.md` |
| How is the F1 game built? | `formula-simulator/docs/`: `architektura-java.md`, `mapa-sim-python.md`, `infra.md`, `rodowod.md` (the pedigree of balance numbers) |
| What can security do? | `microservice-security/specs/`, `Readme.md`, `docs/mfa-design.md`, `docs/oauth-providers.md` |
| How to plug in real Google? | `microservice-security/docs/oauth-providers.md` |
| Deployment plans (VPS, k3s)? | `docs/deployment-plan.md` |
| What does the system do (spec surface)? | [`docs/features.md`](features.md) (all Gherkin scenarios), [`docs/javadocs.md`](javadocs.md), `allure-summary.md` |
| Maven commands | `maven-cheatsheet.md` |

## 19. Mini-glossary (the interview minimum)

- **Hexagonal / ports and adapters** — logic separated from technology; port = interface, adapter = implementation.
- **Use case** — one application operation as a class with `execute`.
- **JWT / JWKS** — the signed identity token / the public keys to verify it.
- **Introspection vs offline** — asking security about a token vs verifying the signature yourself.
- **MFA / TOTP / passkey / step-up** — additional sign-in factors and re-authentication before a sensitive operation.
- **Kafka / topic / event** — the event backbone; a channel; a message.
- **Outbox** — the event written in the same transaction as the state change; a poller pushes it to Kafka.
- **Saga** — a distributed sequence with confirmations (account deletion: 3 participants).
- **Pact / CDC** — the consumer declares the fields it reads; the producer verifies that in its own build.
- **Tolerant reader** — a consumer ignores unknown fields (which is why additive changes are safe).
- **Versioned envelope** — every event carries `version: 1`; a breaking change = bump + expand/contract.
- **Flyway / migration** — versioned database schema changes as SQL files.
- **Testcontainers** — a real database in Docker for the duration of a test.
- **Gherkin / Cucumber / spec-first** — executable Given/When/Then specifications, written before the code.
- **cid** — the correlation-id; one identifier through every service's logs.
- **Trace / span (OTel, Tempo)** — a request's timeline across services; the agent instruments the JVM without code changes.
- **Healthcheck** — a container readiness probe; dependents wait for `service_healthy`.
- **Smoke test** — a quick end-to-end test of the live stack.
- **Reactor** — Maven's multi-module build in dependency order.
- **Virtual threads (Loom)** — cheap JVM threads (Helidon SE, formula).
- **CORS / preflight** — the browser's cross-origin request control (collections-ui exercises it for real).

---

Read this top to bottom and you know **what every piece is for**. You'll still learn the
most from section 17: bring the stack up, click around, and watch in Grafana what
happens underneath.

---

# Annex A — microservice-memes under the microscope (interview preparation)

Memes is the showcase service: a public repo, a showy UI, and underneath a full set of
"grown-up" techniques. This annex gives you interview depth: the anatomy, **decisions
with their reasoning** (recruiters ask "why", not "what") and the list of questions
you're likely to hear.

## A.1 Anatomy — 7 modules

> 🏷️ **Tags:**
> **layered modules** — a Maven module per layer (related to the hexagon, less granular than in security);
> **frontend-maven-plugin** — Maven builds the frontend (its own pinned Node) and packs it into the jar.

| Module | Contents | Technologies |
|---|---|---|
| `memes-domain` | Entities: `Meme`, `RankedMeme`, `VoteDirection` | pure Java |
| `memes-config` | Typed knobs: `ImageLimits`, `ThumbnailSize`, `ContentPurgePolicy`, `RateLimit`, `TagLimits` | pure Java |
| `memes-image` | `WebImageOptimizer`: re-encoding any image to PNG within limits | pure JDK (`java.desktop`) |
| `memes-tags` | The `Tag` VO (normalisation: lowercase/trim, 2–30 chars `[a-z0-9-]`) | pure Java |
| `memes-application` | Use cases (`PublishMeme`, `ServeMeme`, `MakeThumbnail`, `CastVote`, `RankMemes`, `TagMeme`, `SearchMemesByTag`, `FlagMeme`, `PurgeUserContent`) + ports (`MemeRepository`, `VoteRepository`, `MemeContentIndex`, `ObjectStore`, `ImageEncoder`, `PublicationLog`, `PurgePolicyOverride`) | framework-free |
| `memes-ui` | The gallery: React + TS + Material UI, Vite; the dist in the jar as `META-INF/resources` | frontend-maven-plugin |
| `memes-infrastructure` | The Spring Boot application: controllers, the sign-in gate, JDBC/S3/HTTP adapters, Flyway, Kafka | Spring Boot 3.5 |

**The interview punchline:** the framework appears in ONE module of seven. The domain,
use cases, image processing and tags compile and test without Spring — Spring is
a replaceable infrastructure detail.

## A.2 The upload flow — image safety

> 🏷️ **Tags:**
> **re-encoding** — the image is decoded and encoded anew (PNG), destroying metadata and payloads inside the file;
> **EXIF stripping** — removing metadata (GPS!) from files; **rate limiting** — 429 + `Retry-After`;
> **content dedup** — SHA-256 of the bytes; **atomic operation / putIfAbsent** — one operation settles the race, not "check-then-act".

1. `POST /memes` (multipart) requires a Bearer token; the author = **the confirmed
   identity from security**, never a request field (impersonation through the body is
   impossible).
2. **Rate limit** per uploader (default 12/min, env) → 429 + `Retry-After`.
3. `WebImageOptimizer` re-encodes everything ImageIO can read (BMP, JPEG…) to PNG within
   size limits. **The side effect = a security feature:** re-encoding loses EXIF (there
   is a test with a crafted JPEG carrying a GPS segment — it enters with a location,
   leaves clean) and neutralises any payloads glued onto the file.
4. **Dedup:** SHA-256 of the bytes *after* optimisation; a second upload of the same
   bytes returns the existing id. Concurrency solved by an **atomic
   `claim(data, candidateId)`** (putIfAbsent in memory; in Postgres the PK constraint
   settles the race) — the save happens only AFTER a won claim, so nothing orphaned
   lands in the database. There is a test with two threads on one latch.

## A.3 Where the bytes live — the `ObjectStore` port with three adapters

> 🏷️ **Tags:**
> **one port, many adapters** — the textbook hexagon in practice; **bytea vs object storage** — a blob in the database vs S3;
> **path-style S3** — bucket addressing compatible with MinIO; **path traversal** — the `../../` attack on the filesystem adapter;
> **the `@Primary` gotcha** — an unconditional default bean can break adapter switching.

Metadata always in the database; the bytes behind the `ObjectStore` port with adapters
selected by the `MEMES_BLOB_STORE` env: `db` (a blob table — transactional consistency
with the metadata), `filesystem` (with a path-traversal protection test) and `s3` (AWS
SDK, path-style for MinIO, the bucket created idempotently on startup; a round-trip
against live MinIO via Testcontainers). In compose the stack rides on MinIO.

**An interview story (a real bug):** `DbObjectStore` was unconditionally `@Primary`, so
`memes.blob-store=filesystem` switched nothing — it surfaced while wiring S3. The fix:
exactly one bean per mode, **pinned by a test** (`BlobStoreSelectionTest`). A second real
bug: `S3ObjectStore` with two constructors and no `@Autowired` = death on startup, but
only in s3 mode.

## A.4 Serving: WebP, thumbnails, ranking

> 🏷️ **Tags:**
> **content negotiation** — format choice by the `Accept` header; **degrade quality, not availability** — a dead encoder = PNG instead of an error;
> **cache-once** — WebP encoded once and kept in the ObjectStore; **hot ranking with decay** — freshness weighted by age (a Reddit-like formula).

- `ServeMeme` negotiates on `Accept: image/webp`: WebP is encoded **once** by the
  separate `microservice-image` (Python + Pillow) and cached in the ObjectStore under
  `{id}.webp`; encoder down → we serve PNG (**degrading quality, not availability**).
  Measured: PNG 1790 B → WebP 900 B.
- Thumbnails are generated **on demand** (`MakeThumbnail`), not at upload.
- The hot ranking: `score / (ageHours+2)^1.5` — the decay only **orders**, the returned
  score is unchanged, so the `GET /memes/hot` contract never moved. Publication time is
  known to the `PublicationLog` port (an unknown meme = fresh, fail-safe); time flows
  through a `java.time.Clock` bean (testability).
- Votes: semantics from the `voting` library — one vote per user per meme/comment,
  a repeat vote **replaces** the previous one (never accumulates).

## A.5 Integration with security — two gates and the MFA floor

> 🏷️ **Tags:**
> **RequireSignInFilter / gate** — one place enforcing identity; **introspection vs offline JWT** — the revocation-freshness vs network-hop trade-off;
> **RBAC** — MODERATOR/ADMIN roles from security; **MFA floor** — stripping privileged roles when `mfaCompliant=false`, fail-closed.

- Reads are public; every write requires `Authorization: Bearer` — otherwise
  `401 {"status":"SIGN_IN_REQUIRED"}`.
- The gate has **two implementations**: introspection (`GET /me` — sees a logout
  instantly; that's how compose runs) and offline JWT via JWKS (less traffic, blind to
  revocation until `exp`). Being able to narrate this trade-off = a big interview plus.
- Moderation: MODERATOR/ADMIN deletes others' memes and flags **NSFW** (gallery blur;
  `FlagMeme`, the V3 table). The admin panel sets the purge-policy default
  (`/admin/purge-policy`, ADMIN role).
- **The MFA floor:** a privileged user without completed MFA is cut down to USER at the
  gate (`Caller.withMfaFloor`, fail-closed). An anecdote worth telling: the offline
  gate's copy **once lost this floor**, and only the convergence of five copies into the
  `offline-jwt` library + a regression test caught it — the argument why
  security-critical code must not live as copies.

## A.6 Memes in the saga and the event cascade

> 🏷️ **Tags:**
> **saga participant** — memes consumes `PURGE_USER_CONTENT`, confirms on `memes-events`;
> **per-axis policy** — content fate as a rule: DELETE / ANONYMIZE_AUTHOR / KEEP_POPULAR_ANONYMIZED:n;
> **resolution precedence** — the user's wizard choice > the database setting (`settings`, V4) > env; **fail-safe** — an unparsable rule = the default, the saga never wedges;
> **event cascade** — a deleted meme announces `MEME_DELETED`, comments deletes the thread.

On account deletion memes decides the leaver's content fate **by a per-axis rule**:
`DELETE` (the meme disappears with its thread and votes), `ANONYMIZE_AUTHOR`
("deleted account"), `KEEP_POPULAR_ANONYMIZED:n` (score ≥ n survives anonymised — "the
community earned it"). The leaver's votes are withdrawn **always** — identity-keyed data
gets no policy loophole (the GDPR argument). The user's choice from the deletion wizard
(carried in the saga command) overrides the default. The confirmation goes to
`memes-events` with the cid and `version: 1`.

Separately: deleting a single meme publishes `MEME_DELETED`, upon which
`microservice-comments` deletes the thread — an example of why comments were split into
a separate service (a different lifecycle, its own database), with consistency between
them **eventual**, not transactional.

## A.7 How memes proves it works

> 🏷️ **Tags:**
> **tests per layer** — unit (image/config/application), MockMvc, Cucumber HTTP black box, Playwright e2e;
> **consumer pacts** — memes declares what it reads from the saga command (`pacts/`) and from `GET /me` (`pacts-http/`);
> **Testcontainers** — the S3 round-trip on live MinIO; **Allure + `docs/features.md`** — documentation generated from tests.

- The Cucumber features (`upload`, `vote`, `tag-meme`, `moderate-meme`,
  `admin-purge-policy`) are the **living contract** — an HTTP black box, green in every
  build.
- The browser suite (cucumber-js + Playwright) clicks the gallery against a real
  security+memes+comments trio; accounts and seed via the API, the UI clicked only where
  the scenario is about it.
- **Pacts:** memes as a consumer declares the fields it reads from the purge command
  (a message pact in `pacts/`) and from the `/me` introspection (an HTTP pact in
  `pacts-http/` — a separate directory, because a Pact V3 file does not mix styles);
  security verifies both against real code.
- Metrics at `/actuator/prometheus`, traces via the OTel agent, logs with the cid — an
  upload shows in Tempo as the trace `[memes, security]`.

## A.8 Questions you are likely to hear (with the gist of the answer)

1. **"Why Spring Boot here when it's Micronaut elsewhere?"** — The portfolio deliberately
   realises the same pattern in several frameworks; memes shows the layers don't depend
   on the framework (Spring lives in 1 module of 7).
2. **"What happens when two users upload the same image at once?"** — SHA-256 dedup with
   an atomic claim; in the database the constraint settles it, the save comes after the
   won claim; there's a two-thread test.
3. **"Where do you keep the images and why?"** — The ObjectStore port, 3 adapters
   (db/filesystem/S3); metadata always in Postgres; the choice is a deployment matter,
   not a code matter. Bonus: the `@Primary` bug story.
4. **"How do you defend against a malicious upload?"** — Re-encoding to PNG (destroys
   EXIF and payloads, a test with GPS in a JPEG), size limits, a 429 rate limit, NSFW
   moderation, the author from the token not the body.
5. **"How do you know you didn't break the security integration?"** — Pacts: a breaking
   change goes red in the producer's build with the consumer's name; plus e2e and the
   live-stack smoke.
6. **"Introspection or offline verification?"** — I have both and can say when each fits:
   introspection = revocation freshness, offline = no hop and resilience to a security
   outage; offline requires moving verdicts into claims (`mfaCompliant`).
7. **"What happens to content after account deletion?"** — A saga with confirmations;
   a per-axis policy with the precedence wizard > database > env; votes always
   withdrawn; an unparsable rule doesn't wedge the saga.
8. **"How would you scale it?"** — The bytes are already behind a port (S3), WebP cuts
   transfer, thumbnails on demand, the ranking is computed with decay without a contract
   change; public reads = easy cache/CDN in front of the service.
9. **"Why are comments a separate service?"** — A different lifecycle and data model;
   eventual consistency via `MEME_DELETED`; the shared voting semantics extracted into
   the `voting` library instead of copies.
10. **"How do you test?"** — A pyramid with the same scenario at several entrances: unit
    → use cases → MockMvc/HTTP black box → pacts → Playwright in the browser → the stack
    smoke.
11. **"What would you improve?" / "Tell me about a refactoring"** — A ready story with
    a happy ending: I diagnosed that the saga orchestrator in security knew its
    participants BY HEART (columns in a table!) and the identity domain knew the
    portal's content axes by name — an "identity + game only" deployment could not
    delete an account. **I extracted the orchestration into a separate portal service**
    (`microservice-offboarding`): security announces a fact and awaits one verdict,
    participants are configuration, and the boundary is guarded by pacts in both
    directions — the participants never noticed the command producer change (their
    contracts passed without payload modifications). Diagnosis → options → execution →
    proof by contracts: exactly what a senior wants to hear.

**Before interviews, rehearse the demo (15 minutes):** `./infra-up.sh` → registration →
the link in Mailpit → upload → a star (cross-origin to collections) → an NSFW flag as
a moderator → account deletion through the wizard → show in Tempo ONE saga trace across
5 services. It beats slides.
