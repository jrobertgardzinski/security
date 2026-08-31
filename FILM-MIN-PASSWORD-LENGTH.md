# Film 5 — minimalna długość hasła „na żywo" (ściąga)

Sceny wg scenariusza z Drive: spec BDD → default → property → endpoint → 3 z endpointu (odmowa) → 3 z psql (fallback).
Przed każdą rejestracją: GET raportu drabinki.

## 0. Stack

```bash
cd ~/Documents/git/portal && ./infra-up.sh
```

Buduje jary (`shared` install + portal package) i podnosi portal razem ze stackiem tożsamości
(security, email, Mailpit, Kafka, Postgres) jako projekt compose `security`. Formula nie jest potrzebna.

Na **Docker Desktop** (kontekst `desktop-linux`) `node-exporter` nie wstaje (`/:/host rslave` — VM nie ma
shared mountu) i zrywa resztę `up`. Wtedy po `infra-up.sh` dociągnij pozostałe serwisy bez niego:

```bash
docker compose up -d $(docker compose config --services | grep -v '^node-exporter$')
```

Systemowy `dockerd` (kontekst `default`) jest wyłączony (2026-08-30), żeby nie dublował stacku i portów.

Przebudowa jednego serwisu po zmianie w UI/kodzie (np. memes) — `clean`, bo bez niego boot jar
nie przepakowuje świeżego `memes-ui` i kontener serwuje stary bundle:

```bash
cd ~/Documents/git/portal/microservice-memes && ../mvnw -q clean package -DskipTests -pl memes-ui,memes-infrastructure -am
cd ~/Documents/git/portal && docker compose up -d --build memes
```

Sprzątanie: `docker compose -p security down` (z `-v`, gdy chcesz też zerwać dane bazy).

| Co | Gdzie |
|---|---|
| microservice-security | http://localhost:8080 |
| Mailpit (linki weryfikacyjne) | http://localhost:8025 |
| Postgres | localhost:5433, user `postgres`, hasło `secret`, baza `security` |

**Admin:** compose wyznacza `admin@example.com` jako bootstrap-admina (`SECURITY_BOOTSTRAP_ADMINS`). Wystarczy zarejestrować to konto i zweryfikować mail.

**Limity, które mogą przeszkodzić:**
- `/register` — 5 prób / 15 min per IP; w compose podniesione do 100 (`SECURITY_REGISTRATION_MAX_PER_WINDOW`). Z IDE bez tej zmiennej szósta próba = 429.
- `/account/step-up` — 10 / 15 min per IP; w compose 100.
- cache ustawień: domyślnie TTL 10 s, w compose **wyłączony** (`SECURITY_SETTINGS_CACHE_TTL_SECONDS: "0"`) — zmiana z POST/psql jest widoczna natychmiast. Z IDE bez tej zmiennej: odczekać 10 s.

## 1. Endpointy

Wszystko JSON, `Content-Type: application/json`. `$SEC=http://localhost:8080`.

### Rejestracja
```
POST /register            {"email": "...", "password": "..."}
  201  {"status": "REGISTERED"...}   — mail z linkiem w Mailpit
  422  {"emailErrors": [{"DOMAIN_MISSING_DOT": true}], "passwordErrors": [{"MIN_LENGTH_NOT_MET": 10}, {"DIGIT_REQUIRED": true}]}
  429  {"error": "TOO_MANY_REGISTRATIONS"} + Retry-After
```
Parametr przy `MIN_LENGTH_NOT_MET` to minimum **obowiązujące w tej próbie** — to jest scena „system mierzy nową miarą".

### Weryfikacja maila (potrzebna, żeby się zalogować)
```
POST /verify-email        {"token": "<z maila>"}
```
Token z Mailpit: otwórz http://localhost:8025 albo:
```bash
MSG=$(curl -s 'http://localhost:8025/api/v1/search?query=to:admin@example.com' | jq -r '.messages[0].ID')
curl -s "http://localhost:8025/api/v1/message/$MSG" | jq -r .Text | grep -oE '(token|verify)=[A-Za-z0-9_-]+'
```

### Logowanie
```
POST /authenticate        {"email": "...", "password": "..."}
  200  {"accessToken": "..."}
```
Dalej: `Authorization: Bearer <accessToken>`.

### Step-up (wymagany przed każdym POST na ustawienia)
```
POST /account/step-up     {"action": "admin-settings", "password": "<hasło admina>"}
  200  {"status": "ELEVATED"}
```
Elewacja jest per akcja i jednorazowa — przed każdym POST min-length robisz step-up od nowa.

### Polityka hasła — ADMIN
```
GET  /admin/settings/password/min-length
  200  {"value": 5, "source": "rebuild (default)", "rejected": []}
  200  {"value": 10, "source": "live (database)", "rejected": []}
  200  {"value": 5, "source": "rebuild (default)",
        "rejected": [{"source": "live (database)", "value": 3, "reason": "minLength must be at least 5"}]}
  403  {"status": "NOT_AN_ADMIN"}

POST /admin/settings/password/min-length   {"value": 10}
  200  {"status": "ACCEPTED", "value": 10}
  400  {"status": "REFUSED", "reason": "minLength must be at least 5"}
  400  {"status": "NOT_A_NUMBER"}
  403  {"status": "NOT_AN_ADMIN"}
  401/403 ze step-up guarda, gdy brak świeżej elewacji
```

Źródła drabinki: `live (database)` > `restart (property)` > `rebuild (default)`.
Property: `security.password.policy.min.length` (env: `SECURITY_PASSWORD_POLICY_MIN_LENGTH`). Default: `MinLength.DEFAULT = 5`.

## 2. Baza

```bash
psql -h localhost -p 5433 -U postgres -d security          # hasło: secret
# albo bez klienta na hoście:
docker compose -p security exec postgres psql -U postgres -d security
```
IntelliJ Database: PostgreSQL, host `localhost`, port `5433`, user `postgres`, hasło `secret`, database `security`.

```sql
\d security_settings
SELECT * FROM security_settings;

-- scena „ktoś wpisał z konsoli": nielegalna wartość, drabinka ją odrzuci i spadnie na default
INSERT INTO security_settings (name, value)
VALUES ('security.password.policy.min.length', '3')
ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

-- sprzątanie po filmie
DELETE FROM security_settings WHERE name = 'security.password.policy.min.length';
```

Po INSERT: GET raportu pokaże `rejected` z powodem, a w logu serwisu WARN:
```bash
docker compose -p security logs -f security | grep -i "min.length\|WARN"
```

## 3. Sekwencja na film (curl)

```bash
SEC=http://localhost:8080; H='Content-Type: application/json'

# konto admina (raz)
curl -s -X POST $SEC/register -H "$H" -d '{"email":"admin@example.com","password":"StrongPassword1!"}'
#   -> token z Mailpit -> POST /verify-email
curl -s -X POST $SEC/verify-email -H "$H" -d '{"token":"<TOKEN>"}'
T=$(curl -s -X POST $SEC/authenticate -H "$H" -d '{"email":"admin@example.com","password":"StrongPassword1!"}' | jq -r .accessToken)

# scena 1: default
curl -s $SEC/admin/settings/password/min-length -H "Authorization: Bearer $T" | jq
curl -s -X POST $SEC/register -H "$H" -d '{"email":"u1@example.com","password":"Ab1!x"}'      # 5 znaków, przechodzi

# scena 3: admin ustawia 10
curl -s -X POST $SEC/account/step-up -H "$H" -H "Authorization: Bearer $T" -d '{"action":"admin-settings","password":"StrongPassword1!"}'
curl -s -X POST $SEC/admin/settings/password/min-length -H "$H" -H "Authorization: Bearer $T" -d '{"value":10}'
curl -s $SEC/admin/settings/password/min-length -H "Authorization: Bearer $T" | jq
curl -s -X POST $SEC/register -H "$H" -d '{"email":"u2@example.com","password":"Nine1!aaa"}'  # 9 -> 422 MIN_LENGTH_NOT_MET: 10

# scena 4a: 3 z endpointu -> odmowa, nic się nie zmienia
curl -s -X POST $SEC/account/step-up -H "$H" -H "Authorization: Bearer $T" -d '{"action":"admin-settings","password":"StrongPassword1!"}'
curl -s -X POST $SEC/admin/settings/password/min-length -H "$H" -H "Authorization: Bearer $T" -d '{"value":3}'

# scena 4b: 3 z psql -> fallback (patrz sekcja 2), potem:
curl -s $SEC/admin/settings/password/min-length -H "Authorization: Bearer $T" | jq
curl -s -X POST $SEC/register -H "$H" -d '{"email":"u3@example.com","password":"Ab1!x"}'      # znów przechodzi, bo w mocy jest 5
```

Postman: `FILM-MIN-PASSWORD-LENGTH.postman_collection.json` obok — zmienne `baseUrl`, `token`, `verifyToken`; request Authenticate sam zapisuje `token`.
