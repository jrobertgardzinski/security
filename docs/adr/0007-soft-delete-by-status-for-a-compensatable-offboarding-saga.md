# ADR 0007: The offboarding saga hides before it erases — a status on the aggregate, closed by the orchestrator

- Status: Accepted
- Date: 2026-08-08
- Scope: the portal's account-deletion saga — microservice-offboarding (orchestrator),
  microservice-memes, microservice-comments and microservice-user-collections (participants)

## Context

The portal's account deletion is an orchestrated saga: security announces the fact,
microservice-offboarding commands each content service to purge, and the leaver's account is
deleted once every participant has confirmed. The word *compensation* was already in the code —
the saga has a `COMPENSATED` state, and a participant that never answers makes the orchestrator
announce `PORTAL_PURGE_FAILED`, after which security unlocks the account and mails an apology.

The act was missing. Each participant destroyed content the moment the purge command arrived:
rows deleted, votes retracted, images removed from object storage. So the saga's FIRST step was
irreversible while its LATER steps could still fail, and the only outcome that could follow was
the one nobody wants — the leaver gets their account back, an apology for a deletion that "could
not be completed", and no memes. The workspace's own e2e feature said so out loud, in a step
named *"their meme stays gone"*. Everything the saga did afterwards was theatre.

## Decision

**A status on the aggregate, not a separate entity.** `MemeMetadata`, `Comment` and `SavedItem` carry
`status ∈ {ACTIVE, PENDING_ERASURE}` and `markedForErasureAt`; the transitions are aggregate
methods (`markForErasure(at)`, `restore()`), never a setter, and both are idempotent — Kafka
delivers at-least-once, and a second mark keeps the FIRST instant so a redelivery cannot rejuvenate
an obligation. We deliberately did **not** build a generic `ToDelete<T>` or a queue table of things
to erase: the fact is a property of exactly one row with exactly one lifetime, and a second table
would need that row's key duplicated, its own cascade, its own idempotence story, and a join on
every read that must not see the content. The vocabulary is the GDPR's — `PENDING_ERASURE`, not
`TO_DELETE`, because article 17 is the right to *erasure* and an auditor, a lawyer and a reviewer
should read the same word. The filter that makes the status mean anything is written down **once**
per service, as a database view (`active_memes`, `active_comments`, `active_collection_items`):
every read goes through it, so a query cannot forget the condition — there is no condition to forget — and a build-time guard
(`MemeReadFilterTest`, `CommentReadFilterTest`, `ItemReadFilterTest`) fails the build if any SQL
outside the one erasure-aware adapter names the base table. That guard is a source-level rule
rather than ArchUnit on purpose: ArchUnit reasons about types, and this rule is about the text inside a string constant.

**Erasure is triggered by the saga's state, never by elapsed time.** When the last required
participant confirms its mark, the orchestrator emits `ERASE_USER_CONTENT` — the closure — and only
that command destroys anything; when the orchestrator gives up, it emits `RESTORE_USER_CONTENT` and
the content is public again. A participant never decides on its own clock: a saga stuck for an hour
because a sibling is down is a saga that may still compensate, and content erased on a timer cannot
come back, so a local timeout would be a guess that is wrong exactly where it is expensive. The
reaper is therefore not a scheduler but a query — `WHERE author = ? AND status = 'PENDING_ERASURE'`
— run when the closure arrives. The passage of time buys exactly one thing: an ALARM.
`StuckErasureWatch` gauges marks older than any saga can legitimately last
(`memes_erasure_backlog`, `comments_erasure_backlog`, `collections_erasure_backlog`) and says in
the log that the content is hidden but NOT erased and that nothing will delete it on a timer. A lost closure is a GDPR problem;
it is now a visible one, which is the most a participant can honestly offer.

**The pivot is the blob leaving object storage.** Everything before `objects.delete(...)` inside
`PurgeUserContent` is undoable — the mark changes a status, and votes, tags, the dedup claim and
the bytes are all untouched. That one call removes an image from MinIO/S3 and no message from
anywhere brings it back, which is why the saga only reaches it after every confirmation is in, and
why the obligation to complete it is itself durable (`pending_blob_deletes`, V9) rather than a
promise in one JVM's memory. Past the pivot the saga has exactly one move left: retrying. It is
marked as such in the code (`PurgeUserContent`, `JdbcMemeRepository.deleteById`), in the sequence
diagram in `microservice-memes/docs/account-deletion-across-services.md`, and in a Gherkin step
that asserts it (`account-erasure.feature`: *"the image is gone from object storage"*).

## Consequences

- The confirmation the orchestrator collects now means "reserved", not "destroyed" — the wire name
  `PURGE_USER_CONTENT` is unchanged on purpose, so the participants' committed pacts keep their
  meaning; the two new command types are additive within envelope version 1 (ADR 0004).
- The purge RULE (delete / anonymise / keep the popular ones) is applied at closure time, not at
  mark time, because it reads vote scores and the leaver's own votes are only retracted by the
  erasure itself. A meme or comment the rule KEEPS returns to `ACTIVE` under the placeholder
  author — a reservation nobody is erasing must not linger in the backlog.
- The closure and the verdict are published together and marked together: a saga is recorded as
  announced only when every one of its events reached the broker, so a lost closure is
  re-published by the same sweep that re-publishes a lost outcome.
- The leaver's content disappears from the world at the MARK, exactly as before — the two-phase
  design costs them nothing in perceived speed.
- **All three participants are converted** (microservice-user-collections followed on the same day,
  V3 + `active_collection_items` + `ItemErasure`). It differs from its two siblings in one honest
  way: the refs it stores are opaque, so there is no purge RULE to apply and no per-row decision to
  make, and its closure is therefore one statement — `DELETE ... WHERE user_email = ? AND status =
  'PENDING_ERASURE'` — rather than a loop over aggregates. The status filter, the view, the
  build-time guard, the three commands and the backlog alarm are the same in all three.
  Its `CollectionStore.purgeUser(user)` was **removed** rather than left unused: a wholesale
  "delete everything this user has" is exactly the operation that made the participant impossible
  to compensate, and leaving it in reach invites the next caller to bypass the saga.
