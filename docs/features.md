# The estate's behavior, in its own words

Every `.feature` across the three workspaces — collected 2026-08-10 by
`build_features.py`. Titles and scenario names only: the steps live with
their repos, this page is the spec surface you can diff in one glance.

## shared

### config

**Hardcoded configuration source** — `shared/config/src/test/resources/com/jrobertgardzinski/config/source/hardcoded/hardcoded-config.feature`

> A HardcodedKey carries its value directly in the key definition. No external dependencies are needed to resolve it — the value is always available at compile time.

- Resolve a hardcoded scalar value
- Resolve a hardcoded list value

**Repository configuration source** — `shared/config/src/test/resources/com/jrobertgardzinski/config/source/repository/repository-config.feature`

> A RepositoryKey resolves its value via RepositoryConfigPort, which abstracts database access. The key name is used as the identifier for the lookup. Values may be absent — the port returns Optional for scalar keys.

- Resolve a scalar value from the repository
- Resolve a list value from the repository
- Resolve a scalar value that is absent from the repository

**Properties configuration source** — `shared/config/src/test/resources/com/jrobertgardzinski/config/source/properties/properties-config.feature`

> A PropertiesKey resolves its value via PropertiesConfigPort, which abstracts application.properties, environment variables, or any other property source. The key name maps directly to the property name.

- Resolve a scalar value from properties
- Resolve a list value from properties

### microservice-email

**Sending mail on behalf of trusted services** — `shared/microservice-email/src/test/resources/features/send-mail.feature`

> The mail service is internal: only callers presenting the shared API key may send a MAIL, and a malformed MAIL command is refused before anything is dispatched.

- a trusted service sends a plain mail
- a caller without the API key is refused
- a malformed command is refused
- a verification link is rendered into the template
- a password-reset link is rendered into the template

### microservice-security

**Authentication** — `shared/microservice-security/specs/authenticate.feature`

> Repeated failed AUTHENTICATION attempts from the same source temporarily block that source, to protect accounts from password guessing.

- 1. Correct CREDENTIALS AUTHENTICATE the USER
- 2. Wrong CREDENTIALS are rejected
- <case>
- 3. Too many failed attempts block the source
- reaching the failure limit blocks the source
- staying under the limit keeps the source open
- 4. A blocked source is rejected even with the correct CREDENTIALS
- 5. Failed attempts stop counting after 15 minutes
- within 15 minutes the earlier failures still count
- after 15 minutes the earlier failures are forgiven
- 6. A block is temporary and expires after a while
- 7. Correct CREDENTIALS are not enough while the EMAIL is unverified

**Authorizing access with an access token** — `shared/microservice-security/specs/authorize.feature`

> A protected resource requires a valid, unexpired ACCESS TOKEN. The token is obtained by AUTHENTICATING and is presented as a Bearer token.

- 1. A valid ACCESS TOKEN grants access
- 2. A missing or unknown ACCESS TOKEN is refused
- <case>
- 3. An expired ACCESS TOKEN is refused

**Changing the email address** — `shared/microservice-security/specs/change-email.feature`

> A signed-in USER changes their EMAIL by proving ownership of the new one: a verification link goes to the new EMAIL, and confirming the token applies the change. Afterwards they AUTHENTICATE under the new EMAIL and no longer under the old one. An unknown token is rejected.

- Confirming the token from the link CHANGES the EMAIL
- An unknown token is rejected
- A taken EMAIL cannot be probed through the change — the reply is quiet, the owner is told by mail
- FEDERATED LINKS follow the account — the subject is the person, not the address

**Changing the password** — `shared/microservice-security/specs/change-password.feature`

> A signed-in USER changes their password by proving the current one. Afterwards they AUTHENTICATE with the new password; the old one no longer works. A wrong current password is rejected.

- The correct current password lets the USER CHANGE it
- A wrong current password is rejected

**Closing the account** — `shared/microservice-security/specs/delete-account.feature`

> A signed-in USER closes their account. Closure is a SAGA across services: the account locks at once (sessions revoked, sign-in refused) and identity announces the deletion to the PORTAL, whose own orchestrator (microservice-offboarding) has every content service purge the USER's content — each axis under the USER's chosen rule (delete / anonymise / keep-popular); votes are retracted. Identity waits for the portal's single outcome: only "content purged" deletes the USER for good; a failed purge — or silence past the safety net — rolls the closure back.

- Requesting closure locks the account immediately
- The USER chooses what happens to their content
- The closure completes only when the PORTAL confirmed its content purged
- A failed portal purge rolls the closure back
- Even total silence rolls the closure back (the safety net)

**Federated sign-in** — `shared/microservice-security/specs/federated-sign-in.feature`

> A USER SIGNS IN with an identity an external PROVIDER vouches for. Registration collapses into the first sign-in, and one ACCOUNT may hold many identities — a password and a provider subject are equal keys to the same ACCOUNT.

- 1. A vouched identity SIGNS the USER IN, creating the ACCOUNT at first contact *(@http-only)*
- first contact
- the second contact opens the same ACCOUNT, not a twin
- 2. A verified local ACCOUNT auto-links: the same inbox proved twice is the same person
- forgot the password sign-up, came back through the provider
- 3. An unverified local ACCOUNT is taken over: the PROVIDER's proof beats an unproven password
- a squatter planted an account on someone else's address
- 3b. A provider login is only link #1 — enrolled factors must still be passed
- a federated account that turned on a second factor
- 3c. An ACCOUNT locked by a running deletion is refused WITHOUT being touched
- the leaver clicks "sign in with the provider" while their deletion is running
- 4. An identity the PROVIDER does not vouch for touches nothing
- the provider did not verify the email

**Listing active sessions** — `shared/microservice-security/specs/list-sessions.feature`

> A signed-in USER sees their active sessions. Each time they AUTHENTICATE a new session is created, and every active one shows up in the list.

- Every active session of the USER is listed

**Logging out** — `shared/microservice-security/specs/logout.feature`

> LOGGING OUT ends the current session: its REFRESH TOKEN can no longer be REFRESHED and its access token no longer authorizes.

- 1. A LOGGED-OUT session can no longer be REFRESHED
- 2. A LOGGED-OUT ACCESS TOKEN no longer grants access
- 3. LOGGING OUT without a session still succeeds

**Passkey sign-in** — `shared/microservice-security/specs/mfa-passkey.feature`

> A USER may enrol a PASSKEY — a possession FACTOR, nothing to type and nothing to copy. Once enrolled, the password alone no longer signs in: the device holding the PASSKEY must prove it is present. This exercises the same factor chain the e-mail and TOTP factors use, proving the factor port is genuinely plug-and-play. (The protocol behind a passkey is an implementation detail and lives in the glue — the argon2 rule.)

- An enrolled PASSKEY signs the USER in without a typed code

**Multi-factor sign-in** — `shared/microservice-security/specs/mfa.feature`

> A USER may enrol extra FACTORS. Once enrolled, a correct password is no longer enough: the sign-in pauses and each FACTOR must be passed, in order, before a session is issued. The e-mail FACTOR sends a one-time CODE that must be quoted back. A RECOVERY CODE — GENERATED ahead of time, shown once — stands in for any FACTOR the USER lost access to; each one works exactly once.

- With a FACTOR enrolled, the password alone does not sign in
- Passing the FACTOR completes the sign-in
- A wrong CODE does not sign in
- A RECOVERY CODE stands in for a FACTOR the USER cannot pass
- each RECOVERY CODE works exactly once

**Refreshing a session** — `shared/microservice-security/specs/refresh-session.feature`

> A USER keeps their session alive by REFRESHING it. A session that has expired, or that no longer exists, cannot be REFRESHED — the USER must AUTHENTICATE again.

- 1. An active session can be REFRESHED
- 2. An expired session cannot be REFRESHED
- 3. A missing session cannot be REFRESHED

**Registration** — `shared/microservice-security/specs/register.feature`

> A new USER REGISTERS with an EMAIL and a password. Registration is refused when the EMAIL or the password is invalid. An already-taken EMAIL is refused quietly: the answer does not reveal that the account exists — the owner of the address learns what happened from a mail only they can read.

- 1. A valid EMAIL and password REGISTER the USER *(@ui)*
- 2. An invalid EMAIL or password is rejected, saying which one
- <case>
- 3. An EMAIL that is already REGISTERED is refused quietly, so nobody can probe who has an account
- the same email
- a provider alias of that email (Gmail treats dots and "+tags" as the same inbox)

**Resetting a forgotten password** — `shared/microservice-security/specs/reset-password.feature`

> A USER who forgot their password requests a reset link, then sets a new password with the RESET TOKEN from the link. Afterwards they AUTHENTICATE with the new password; the old one no longer works. An unknown token is rejected.

- A valid RESET TOKEN sets a new password
- An unknown RESET TOKEN is rejected

**Refresh token theft detection** — `shared/microservice-security/specs/reuse-detection.feature`

> REFRESH tokens are single-use: each REFRESH rotates to a new one. Presenting a REFRESH TOKEN that has already been rotated away signals theft, so the whole session lineage is revoked — including the attacker's freshly obtained token.

- A replayed (already-rotated) REFRESH TOKEN revokes the whole SESSION FAMILY

**Revoking all sessions** — `shared/microservice-security/specs/revoke-all-sessions.feature`

> A USER can log out everywhere at once: revoking all sessions ends every session the USER holds, so afterwards no ACCESS TOKEN authorizes and no REFRESH TOKEN can be REFRESHED.

- REVOKING all sessions ends every session of the USER

**Granting and reporting ROLES** — `shared/microservice-security/specs/roles.feature`

> Security's duty behind every door in the estate: say who the caller is. The who-am-I resource reports the caller's ROLES, so every other service can gate on them without guessing — and this is where the ladder the products speak starts. A GUEST carries no identity and never reaches security at all; what a GUEST may see is each product's own rule. Signing in makes a USER, and every USER holds the USER role. MODERATOR and ADMIN are granted on top, only by an ADMIN's hand.

- A fresh USER is only a USER
- An ADMIN grants a ROLE, and from then on it is reported to every service that asks
- Granting ROLES is an ADMIN's hand alone
- A ROLE cannot be pinned on a USER who does not exist

**Verifying an email address** — `shared/microservice-security/specs/verify-email.feature`

> A USER proves they own their EMAIL by following a verification link sent to it. The link carries a single-use VERIFICATION TOKEN; the matching token marks the EMAIL as verified, and an unknown token is rejected.

- The VERIFICATION TOKEN from the link verifies the EMAIL
- An unknown VERIFICATION TOKEN is rejected
- Registration automatically starts VERIFICATION

## portal

### e2e

**The right to be forgotten — leaving the portal takes the user's traces along** — `portal/e2e/features/account-deletion.feature`

> A person who asks for their account to be deleted is owed more than a dead login: the meme they posted, the comment they signed and the list of things they saved all have to be dealt with, each according to the portal's data policy. By default their memes disappear and their comments stay readable for the thread's sake — but signed by nobody. The leaver may also choose a stricter fate for their words. These scenarios speak the user's language on purpose. The choreography underneath — the deletion fact, the purge commands, the participants' confirmations — is already specified in microservice-offboarding's own features; here only the promise made to the person counts, and it is proven against the LIVE stack: real services, real broker, real mailbox.

- Deleting the account removes the person's traces under the default policy
- The leaver may choose that their words go too

**A deleted meme takes its traces along — including the ones in my favourites** — `portal/e2e/features/deletion-cascade.feature`

> Saving a meme is saving a POINTER to somebody else's thing. When that thing is taken down, the pointer is the last one to hear about it, and a favourites list full of memes that no longer exist is a list nobody trusts. So the portal cleans up after itself: a meme's deletion travels outwards on its own, and everything that pointed at the meme — or at the conversation that hung under it — goes with it. Nothing orchestrates this. Each service reacts to the hop before it and announces its own, which is why every check below waits: the promise is that the list becomes right, not that it is right the instant the delete button is released. These scenarios speak the user's language on purpose. The mechanics — MEME_DELETED, the dropped thread, COMMENTS_DELETED, the item-axis purge — are specified in each service's own features; here only what a person sees in their list counts, and it is proven against the LIVE stack.

- A meme I saved disappears from my favourites when its author takes it down
- So does a comment I saved, when the meme it hung under is taken down

**A participant's outage — the promise of deletion is kept honest, not kept forever** — `portal/e2e/features/participant-outage.feature`

> What does the person see when they ask to be forgotten while a piece of the portal is down? Their account goes into limbo: signing in is refused, no verdict has arrived, and behind the curtain the saga keeps re-asking the silent service. The portal does not pretend — it either finishes the job or gives the account back, WITH the content in it, and says so in writing. That last clause is the whole point of ADR 0007, and this scenario is where it is proved. The participants answer the purge command by MARKING the leaver's content, which takes it out of the gallery immediately and destroys nothing; only the orchestrator's closure erases. So when the sweeper capitulates, the compensation puts the memes back — where this scenario used to end with a step named "their meme stays gone", i.e. an apology for a deletion that had, in fact, happened to everything except the account. This scenario stages the CAPITULATION path, because it is the one that can be arranged deterministically: while the favourites service stays stopped, nothing can confirm its purge, so the give-up is guaranteed by arithmetic alone. The arithmetic, though, is NOT what this paragraph claimed until 2026-08-08, and the difference is minutes. The purge timeout is measured from the last command the participant actually RECEIVED, not from the saga's birth (P18: "the sweeper stops capitulating while a participant is still working"), so a silent participant costs 120s per delivered command and the whole case takes 120s x 4 = about EIGHT MINUTES. The sweeper's 15s cadence only decides how promptly each deadline is noticed. For a few hours on 2026-08-08 that had a consequence worth remembering: security's own safety net still stood at five minutes, so it fired FIRST and the account came back three minutes before its content. Nobody designed that — it was the sum of two independently configured timeouts, one of which had moved. The net now sits at twelve minutes, deliberately behind the portal's worst case, so the mail this scenario waits for is the PORTAL's verdict again and the content comes back with it. The HAPPY-AFTER-RETURN variant (restart the service in time, the saga completes: meme gone, sign-in 401 for good) is real too, but proving it needs the restarted container to boot, rejoin the consumer group and purge before the next 120s wall — a race against container and rebalance timing, not a fact of arithmetic — so it is described here and staged nowhere. The steps sample the sign-in door sparingly on purpose: an account in deletion limbo answers like a wrong password, and three wrong passwords from one address trip the brute-force block — the scenario must watch the limbo without becoming the attacker it looks like.

- When the favourites service stays away too long, the account is handed back *(@outage)*

### microservice-comments

**Adding a COMMENT** — `portal/microservice-comments/specs/add-comment.feature`

> USERS discuss under an existing MEME: a GUEST reads, writing takes a USER, and every COMMENT is signed by who really wrote it — nobody puts words in someone else's mouth. A COMMENT is a remark, not an essay: the THREAD stays a conversation, not a blog.

- A USER comments under a MEME that exists
- A GUEST may read, not write
- A COMMENT needs a real MEME to hang under
- A COMMENT is a remark, not an essay

**Deleting a COMMENT** — `portal/microservice-comments/specs/delete-comment.feature`

> A COMMENT belongs to its author: the author may take their own words down, a stranger may not, and a MODERATOR may take down anyone's. A single deletion is nobody else's business: no cascade is announced for it.

- The author takes their own COMMENT down; a stranger cannot
- A MODERATOR takes down anyone's COMMENT

**A deleted MEME takes its THREAD along** — `portal/microservice-comments/specs/delete-thread.feature`

> When the meme service announces that a MEME was deleted, the whole THREAD of COMMENTS disappears with it. This service is the only one that knew which COMMENTS hung there — so it passes that list on to whoever saved them, and stays silent when there was nothing to take.

- The THREAD goes with the MEME, and the cascade passes the baton on
- A MEME nobody commented on is announced to nobody

**Hiding a COMMENT** — `portal/microservice-comments/specs/hide-comment.feature`

> Moderation that can change its mind: instead of deleting, a MODERATOR hides a COMMENT. A GUEST sees a tombstone without the words, the author still sees their own — marked hidden — and revealing brings the words back. Hiding is a MODERATOR's call, and it must be a decision, not a shrug.

- Hidden for a GUEST, never for the author — and reversible
- Hiding is a MODERATOR's call
- Hiding needs an unambiguous decision

**Reading a THREAD** — `portal/microservice-comments/specs/list-comments.feature`

> Reading is public: a GUEST browses a MEME's THREAD one page at a time. The listing guards privacy — a COMMENT is signed with a masked name and the full address never leaves the portal — while the author still recognises their own words. VOTES are a side dish: when the tally is unavailable, the THREAD still reads.

- A long THREAD is read one page at a time — every COMMENT exactly once
- The listing signs a COMMENT with a masked name
- Behind the mask, the author still recognises their own words
- The THREAD survives the VOTE count going missing

**Voting on a COMMENT** — `portal/microservice-comments/specs/vote-on-comment.feature`

> A signed-in USER has ONE VOTE per COMMENT, worked as a toggle: repeating the same VOTE takes it back. The THREAD carries each COMMENT's SCORE, so a reader sees at a glance what the room thinks.

- One USER, one VOTE — and repeating the VOTE retracts it

### microservice-memes

**An account deletion is a SAGA, so hiding comes first and erasing comes last** — `portal/microservice-memes/specs/account-erasure.feature`

> A meme service that shreds a leaver's pictures the moment the PURGE command arrives leaves the ORCHESTRATOR with nothing to undo when a LATER participant of the same SAGA fails — and that is not a theoretical worry: it is what used to happen, and the leaver got their account back without their memes and an e-mail apologising for a deletion that had not, in fact, been cancelled. So the meme service answers the PURGE by MARKING: the memes leave the gallery at once — the whole of what the leaver asked to see — and stay on disk, restorable, until the ORCHESTRATOR says the case is settled. Only its closure command erases anything, and the image leaving object storage is the point past which nothing can be taken back (ADR 0007).

- A failure at another participant brings the leaver's memes back
- The closure is the point of no return — the memes are erased for good
- The PURGE command arriving twice, as Kafka promises it may, changes nothing

**The purge-policy default is an ADMIN's dial** — `portal/microservice-memes/specs/admin-purge-policy.feature`

> What happens to a leaver's memes is deployment policy — but policy changes faster than deployments. An ADMIN may re-dial the default at runtime; the leaver's own wizard choice still wins over everything. Everyone else is refused at the door.

- The ADMIN's override wins over the deployment default, and the purge obeys it
- A plain USER may not touch the dial
- Clearing the override restores the deployment default

**Deleting a MEME** — `portal/microservice-memes/specs/delete-meme.feature`

> A MEME belongs to its uploader, who may delete it; a MODERATOR may delete anyone's MEME. Everyone else is refused. And a deletion means it: afterwards not a byte remains, in any form the service ever made.

- A stranger cannot delete someone else's MEME
- The author deletes their own MEME
- A MODERATOR deletes anyone's MEME
- A GUEST may look, not delete
- After a deletion not a byte of the MEME remains

**Flagging a MEME as NSFW** — `portal/microservice-memes/specs/flag-meme.feature`

> Not every MEME is fit for every screen. A MODERATOR may flag a MEME NSFW and take the flag back; the gallery carries the flag so every reader can decide what to show. The safe-for-work judgement is a MODERATOR's alone — even the author does not get to grade their own homework.

- The NSFW flag is a MODERATOR's dial, and the gallery carries it
- The safe-for-work judgement is a MODERATOR's alone

**Tagging a MEME and finding it by TAG** — `portal/microservice-memes/specs/tag-meme.feature`

> The uploader curates their MEME's TAGS — a small, legal set of search keys, not free text. Anyone browses the gallery narrowed to one TAG; the TAGS of a purged MEME vanish with it.

- The author's TAGS make the MEME findable — by those TAGS and no others
- Only the author curates the TAGS
- Keyword spam is refused

**Uploading a MEME** — `portal/microservice-memes/specs/upload-meme.feature`

> A GUEST browses freely — the gallery, every MEME, every thumbnail; uploading takes a USER. A MEME is stored optimised for the browser, and the door checks what it is handed — a file that is not an honest image is turned away politely, never crashed on.

- An uploaded MEME is public to fetch, thumbnail and all
- The gallery lists the MEME publicly
- A GUEST may browse, not upload
- A file that is not an honest image is turned away, not crashed on

**Voting on a MEME** — `portal/microservice-memes/specs/vote-meme.feature`

> USERS vote on a MEME (a GUEST only watches); each USER has ONE VOTE per MEME, worked as a toggle: repeating the same VOTE retracts it, the opposite direction switches it. An up-voted MEME becomes a higher-scoring MEME in the public hot list.

- The MEME with more distinct up-voters ranks higher
- Repeating the same VOTE retracts it
- A GUEST may watch, not vote

**Leaving — deleting the account, content and all** — `portal/microservice-memes/memes-ui/e2e/features/account-deletion.feature`

> The danger zone in the panel is the RODO exit, and it is deliberately not a single click: the visitor says what should happen to what they posted, then proves it is really them (step-up — a stolen session must not be able to end an account). What follows is a SAGA across the whole portal: security announces the deletion, offboarding orders every participant to purge, memes, comments and collections do it and confirm, and only then is the account gone for good. These scenarios drive that entire road in a real browser against real services on a real broker — no member of the chain stubbed out, because an end-to-end missing a member proves nothing about the member it skipped.

- Burning it all takes the account AND the memes with it
- The recommended choice keeps the comment, signed by nobody
- The wrong password does not end an account
- Second thoughts leave everything alone
- A second factor is asked for on the way out too

**Favourites — the gallery integrated with user-collections** — `portal/microservice-memes/memes-ui/e2e/features/favourites.feature`

> A signed-in visitor stars memes; the refs live in microservice-user-collections (opaque ids, saved cross-origin straight from the browser) and the gallery hydrates them back into tiles. A ref outlives its meme only until the deletion cascade catches up: collections stores opaque ids and never checks back, so for a moment the wall shows an unavailable keepsake — and then MEME_DELETED reaches user-collections and the ref is swept for good.

- A starred meme lands on the favourites wall
- Unstarring lets the favourite go
- A favourite whose meme is deleted is swept off the wall by the cascade

**The meme gallery in a real browser** — `portal/microservice-memes/memes-ui/e2e/features/gallery.feature`

> The gallery is public to browse; uploading, voting and commenting need a signed-in identity from microservice-security. These scenarios drive the React UI with Playwright against the LIVE compose stack — real services on real Postgres, real Kafka, real mailbox — which run-e2e.sh brings up. The header used to say "(in-memory stores)", a leftover from the old four-jar harness; the sibling features already describe the live stack correctly, and overstating or understating what a suite proves is the one thing living documentation must not do.

- An anonymous visitor browses the gallery
- Signing in through the panel
- An upload appears on the wall
- A vote is a toggle
- A comment lands in the thread

**Getting into the gallery — every door the panel offers** — `portal/microservice-memes/memes-ui/e2e/features/identity.feature`

> The gallery's sign-in panel is the portal's front door, and it has more than one lock: a fresh account made right here and confirmed by the mailed link, a plain password, a password plus a mailed sign-in code when the account carries a second factor — and, when the code cannot reach you, a recovery code in its place. These scenarios drive the real panel in a real browser against real security; only the mailbox is a test-environment backdoor, because a browser cannot read e-mail.

- A visitor makes an account here and the mailed link lets them in
- The wrong password does not open the door
- An unverified account is sent back to its mailbox, not let in
- A second factor adds the code step to the same password
- A recovery code stands in for the mailed one

### microservice-offboarding

**Beginning the offboarding — a deletion FACT opens a CASE** — `portal/microservice-offboarding/specs/begin-offboarding.feature`

> When an account leaves, the portal cleans up after it. Security announces the FACT that the account requested deletion; this service opens a CASE and commands every content participant to PURGE — set the leaver's content aside, ready to be erased for good or brought back. The scenarios pin the message choreography, and every command may safely arrive twice.

- A deletion FACT commands the content PURGE
- The leaver's choices ride the command untouched
- A second deletion request joins the CASE already underway
- A FACT the portal cannot place is dropped — never the requests behind it
- With no content participants the portal is instantly clean
- Past RETENTION the portal remembers nothing — a replayed FACT opens a brand-new CASE

**Collecting the CONFIRMATIONS — the last one settles the CASE** — `portal/microservice-offboarding/specs/record-confirmation.feature`

> Each content participant answers the PURGE with a CONFIRMATION. One early answer settles nothing; the last one does two things in strict order: commands the ERASURE — the closure, the point of no return — and only then announces the single OUTCOME security waits for. A CONFIRMATION that fits no open CASE — a stray, or a late echo of a CASE the portal already gave up on — changes nothing: an announced OUTCOME is never rewritten.

- An early CONFIRMATION announces nothing yet
- The last CONFIRMATION announces the portal purged
- The last CONFIRMATION also commands the ERASURE — that is what closes the CASE
- A CONFIRMATION may echo the PURGE command it answers
- A CONFIRMATION for nobody's CASE is a stray, not an error
- A late CONFIRMATION cannot rewrite an announced failure
- A CONFIRMATION from a closed CASE does not touch a new one

**The SWEEP — silence has a deadline** — `portal/microservice-offboarding/specs/sweep-overdue.feature`

> Nobody is allowed to keep the leaver waiting forever. When a participant stays silent past the deadline, the SWEEP re-sends the PURGE command; when every retry is exhausted, the portal gives up honestly — it commands the RESTORE (the compensation that makes the apology true), and only then announces the failure, naming who had already purged. The SWEEP is also the safety net for the portal's own promises: an OUTCOME that never left is announced at the next round, and one that reached security is never announced twice.

- Silence past the deadline retries the PURGE command before giving up
- The leaver's choices survive the retry
- Silence outlasting every retry announces the failure, naming the partial purge
- Giving up restores what it had reserved, and only then apologises
- An OUTCOME the portal failed to announce is announced at the next SWEEP
- An OUTCOME that reached security is not announced twice

### microservice-user-collections

**An account deletion empties the COLLECTIONS — carefully** — `portal/microservice-user-collections/specs/account-erasure.feature`

> When a person leaves the portal, the deletion arrives as a SAGA command from the offboarding ORCHESTRATOR. The purge first sets the saved REFERENCES aside; only the ORCHESTRATOR's closure destroys them for good, and if the SAGA fails at another participant, a compensation brings everything back. Every answer travels back as a CONFIRMATION naming the SAGA — and a command that names nobody is ignored, not obeyed.

- The purge empties every COLLECTION at once and answers the ORCHESTRATOR *(@saga)*
- A failure at another participant brings the saved list back
- The closure is the point of no return
- A closure for a SAGA that reserved nothing destroys nothing
- A purge naming nobody is ignored

**Listing a COLLECTION** — `portal/microservice-user-collections/specs/list-items.feature`

> A COLLECTION belongs to one USER and one name: alice's "favourites" is not bob's, and not alice's "watchlist". The listing shows the newest save first, and a GUEST gets no listing at all.

- The newest save is listed first
- COLLECTIONS are per person and per name
- For a GUEST there are no COLLECTIONS

**Removing a REFERENCE** — `portal/microservice-user-collections/specs/remove-item.feature`

> Taking a REFERENCE out of a COLLECTION is as idempotent as putting it in (workspace ADR 0006): removing something never saved is answered honestly, not with an error a retrying caller would trip over.

- A removed REFERENCE is gone from the COLLECTION
- Removing what was never there is told, not punished

**Saving a REFERENCE** — `portal/microservice-user-collections/specs/save-item.feature`

> A USER saves an opaque REFERENCE — a meme, a comment — into a named COLLECTION. The service keeps the REFERENCE and nothing else: it never interprets what it points at. Saving twice is safe by the workspace's standing law (ADR 0006); the scenarios below pin the REPLY a caller can lean on.

- A saved REFERENCE lands in the COLLECTION
- Saving twice is not an error — the caller is told it was already there
- A REFERENCE too long to be real is refused at the door

## formula

### formula-simulator

**Car development under a rulebook** — `formula/formula-simulator/src/test/resources/features/car-development.feature`

> R&D explores the design space and costs real budget; homologation freezes the car for the season; an era change reshapes what a team knows — portable know-how is clamped into the new legal window, era-bound branches reset. The rulebook, not the richest wallet, draws the boundaries.

- a research programme charges the budget it spends
- a homologated car is frozen until the rules change
- an era change clamps the car into the new legal window

**The driver market** — `formula/formula-simulator/src/test/resources/features/driver-market.feature`

> Free agents ask a salary their talent justifies; contracts bind; poaching a contracted driver means paying the buyout — to the team that loses them. Money moves, drivers move, nobody teleports.

- a fair offer signs the free agent and empties the market
- poaching a contracted driver pays the buyout to the old team

**A race weekend** — `formula/formula-simulator/src/test/resources/features/race-weekend.feature`

> The manager registers a driver line-up, the backend runs a race weekend (qualifying orders the grid, the start reshuffles it, the race is streamed lap by lap as state), and the championship counts the points. State, never pixels.

- the team races and the championship counts the result
- a race needs a grid

### microservice-paddock

**The paddock — servers, people and what's coming up** — `formula/microservice-paddock/src/test/resources/features/paddock.feature`

> A racer signs in once and finds the servers they play on, who is on each, and the events and live signals around them. Identity is the security service's; game state stays on the servers.

- a private server is the organizer's circle
- an open server is self-service and counts its people
- my paddock carries each campaign's live state
- the organizer plans an event and members answer
- a private server can have more than one admin adding friends
- planning an event notifies the members
- the feed merges planned events with derived signals

**The workshop — the community's garage** — `formula/microservice-paddock/src/test/resources/features/workshop.feature`

> Every mod surface of the game is a data file: a bot script, a track profile, an era rulebook, a scenario. The workshop takes them under the author's signed-in identity, versions them, and hands them to anyone who wants to run them — JA2 and Gothic live because their players could do this.

- an author publishes a track and the community finds it
- only the author ships a new version
- a rulebook that is not JSON is turned away at the door

**The paddock PWA in a real browser** — `formula/microservice-paddock/e2e/features/paddock.feature`

> The social hub around the game: browsing servers is public, everything else — registering a server, joining an open one, planning an event, answering an RSVP — needs the one identity shared with the game and the gallery. Playwright drives the PWA against a real security (test environment) and a real paddock on in-memory H2.

- An anonymous visitor sees an empty registry and no controls
- Signing in through the dialog
- Registering a server puts the organizer on its roster
- Joining an open server from the registry
- An organizer plans an event and a member answers the call

*198 scenarios in total.*
