# Przegląd DDD — portal memów + kernel współdzielony (security)

- Data: 2026-08-15
- Zakres: `portal/` (memes, comments, user-collections, offboarding, image) oraz
  `shared/` ze szczególnym uwzględnieniem `microservice-security`; biblioteki
  `voting`, `email`, `password`, `constraint`, `transactional-outbox` przejrzane
  pod kątem tego, co narzucają konsumentom.
- Charakter dokumentu: **przegląd modelu, nie plan naprawczy**. Nic nie zostało
  zmienione w kodzie. Znaleziska są ponumerowane i uszeregowane, żeby dało się z
  nich zrobić kolejny PLAN-P.
- Kryterium oceny: klasyczne DDD (agregat pilnuje swoich niezmienników, język
  wszechobecny, granice kontekstów, repozytorium oddaje agregat a nie kolumny),
  konfrontowane z ADR-ami tego repo (0001, 0002, 0006, 0007) — bo tam, gdzie
  projekt sam podjął świadomą decyzję, ocena jest wobec **tej** decyzji.

---

## 1. Werdykt w trzech zdaniach

Warstwy są rozdzielone porządnie i konsekwentnie: heksagon jest prawdziwy, porty
są portami, adaptery nie wyciekają do use-case'ów, a `security-system` jest
jednym z lepiej poskładanych kawałków kodu w całym majątku (kompozycja kroków
`_`, sealed eventy, `switch` po nich zamiast `if`-ów po flagach).

Natomiast model dziedzinowy jest tu **modelem stanu i pytań, a nie modelem
zmiany**. Typy potrafią o sobie coś powiedzieć (`isStillActive`, `hasExpired`,
`hasReachedTheLimit`, `hasRole`), ale nie potrafią się zmienić: **każde przejście
stanu w tym majątku jest wywołaniem repozytorium**, nie metodą modelu. Skutek
uboczny jest taki, że niezmienniki, o które naprawdę chodzi (kto może usunąć,
kiedy saga jest zamknięta, czego nie wolno pokazać), są egzekwowane w adapterach:
w kontrolerze HTTP, w widoku SQL i w `UPDATE ... WHERE state = 'STARTED'`.

Uwaga ważna dla proporcji: **to nie znaczy, że model jest anemiczny wszędzie i
tak samo.** Rejestracja ma prawdziwy model — tylko mieszka on w `email`/`password`,
nie w `security-domain`. Rozdział 3.0 rozbiera te trzy przypadki użycia po kolei,
bo różnią się między sobą bardziej niż od reszty majątku.

Wyjątkiem na plus są dwa miejsca, które pokazują, że stać ten kod na więcej:
`MemeMetadata` (przejścia jako metody, niezmiennik w konstruktorze zwartym,
idempotencja z uzasadnieniem) i biblioteki `email`/`password` (polityki złożone
z ograniczeń, VO, które naprawdę bronią wartości).

---

## 2. Znaleziska ponadserwisowe

### A1 — [WYSOKA] Autoryzacja jest poza modelem, a każdy serwis kładzie ją gdzie indziej

Ta sama reguła („autor albo moderator") ma dziś trzy różne miejsca zamieszkania:

| Przypadek użycia | Gdzie jest reguła |
|---|---|
| `DeleteMeme.execute(String memeId)` | **wyłącznie w kontrolerze** — `MemeController.java:266-280` |
| `TagMeme.execute(memeId, caller, tags)` | w use-case, porównanie `author().equals(caller)` |
| `DeleteComment.execute(commentId, caller, callerIsModerator)` | w use-case, dwa argumenty |
| `FlagMeme` / `HideComment` | w use-case, ale jako `boolean callerIsModerator` |

`DeleteMeme` nie zna wołającego. Zdanie „only the author or a moderator can
delete this meme" istnieje w tym systemie jako *string w odpowiedzi HTTP*
(`MemeController.java:278`). Drugi wejściowy adapter (konsument Kafki, CLI
admina, test kontraktowy) omija ją bez śladu, a żaden test jednostkowy use-case'u
nie jest w stanie jej złamać, bo nie ma czego złamać.

`boolean callerIsModerator` to ten sam problem w łagodniejszej postaci: decyzja
zapada w adapterze, use-case dostaje **wynik decyzji**, nie dane do jej podjęcia.
Model nie potrafi odpowiedzieć na pytanie „kto może", bo nikt go o to nie pyta.

Dodatkowo `Caller.roles` to `Set<String>` porównywany z literałami
`"MODERATOR"`/`"ADMIN"` (`Caller.java:12-17`) — mimo że `security-domain` ma enum
`Role`. Wspólny język urywa się na granicy serwisu i wraca jako łańcuch znaków.

**Kierunek:** wprowadzić w portalu typ wołającego (choćby `Caller(AuthorId, Set<Role>)`)
jako argument use-case'u i przenieść decyzję do modelu — np. `MemeMetadata.mayBeDeletedBy(caller)`.
Reguła zapisana raz, testowalna bez HTTP, identyczna w memes i comments.

### A2 — [WYSOKA] Repozytoria mutują kolumny, nie zapisują agregatów

Wzorzec powtarza się w każdym serwisie:

- `MemeRepository.reassignAuthor(memeId, newAuthor)` (`MemeRepository.java:88`)
- `CommentRepository.reassignAuthor(commentId, newAuthor)` (`CommentRepository.java:30`)
- `UserRepository.setRoles / updatePassword / updateEmail / markPendingDeletion / clearPendingDeletion`

To są settery przebrane za repozytorium. Konsekwencja jest widoczna gołym okiem
w `PurgeUserComments.java:49-51`: anonimizacja komentarza to **dwa zapisy przez
dwa różne obiekty** —

```java
commentRepository.reassignAuthor(comment.id(), DeletedAccount.AUTHOR);
erasure.store(comment.restore());
```

— czyli jedno przejście dziedzinowe („zachowaj, ale odetnij od konta") rozbite na
dwie operacje, z których pierwsza omija konstruktor zwarty `Comment` (ten, który
pilnuje, że autor nie jest pusty, a status i znacznik chodzą parami). Między
jednym a drugim zapisem rekord jest w stanie, którego model nie dopuszcza.

Ten sam kod jest w `PurgeUserContent.java:78-79` dla memów.

**Kierunek:** `Comment anonymise()` / `MemeMetadata anonymise()` w modelu, a
repozytorium przyjmuje cały agregat. Znika `reassignAuthor` i znika okno
niespójności.

### A3 — [ŚREDNIA] `pendingDeletion`, `hidden`, `nsfw` i `state` sagi to stany, których agregaty nie mają

Cztery przykłady tego samego:

- `User` nie ma pola „w trakcie kasowania" — jest tylko
  `UserRepository.markPendingDeletion/isPendingDeletion`, czyli kolumna w bazie.
  `_VerifyCredentials.java` musi zrobić **drugie zapytanie** do repozytorium,
  żeby dowiedzieć się czegoś o użytkowniku, którego właśnie wczytał.
- `Comment` ma status `ACTIVE`/`PENDING_ERASURE`, ale moderacyjne „ukryty" leży
  w osobnym porcie `CommentModeration`. Agregat nie potrafi więc odpowiedzieć,
  czy wolno go pokazać.
- Analogicznie `ContentFlags` (nsfw) w memes.
- Stan sagi offboardingu — patrz D-OFF1.

Efekt: pytanie „w jakim stanie jest ten byt" nie ma jednego adresata, a każde
nowe czytanie musi pamiętać o dołożeniu warunku. To dokładnie ta klasa błędu,
którą ADR 0007 rozwiązał **dla erasure** (status na wierszu + widok
`active_memes`) i której nie rozciągnięto na resztę stanów.

### A4 — [ŚREDNIA] Prymitywy zamiast tożsamości, w całym portalu

`String memeId`, `String author`, `String commentId`, `String user`,
`String collection`, `String voter` — konsekwentnie, we wszystkich trzech
serwisach portalu. W `shared` jest odwrotnie: `Email`, `NormalizedEmail`,
`HashedPassword`, `IpAddress`, `AttemptedAccount` — i to działa, bo `AttemptedAccount`
wymusiło normalizację adresu w liczniku blokad.

Praktyczna cena w portalu, nie teoretyczna:

1. `PurgeUserContent.execute(String author, ...)` i `MarkUserContentForErasure.execute(String author)`
   przyjmują ten sam typ, co `Meme.author()` i co `DeletedAccount.AUTHOR = "deleted account"`.
   Konto o adresie literalnie równym `"deleted account"` jest nieodróżnialne od
   anonimizowanego autora — a stringa nikt nie waliduje po drodze.
2. `Voting.toggle(String targetId, String voter, ...)` z biblioteki współdzielonej
   przyjmie w tej kolejności memeId i commentId, i vice versa. Kompilator nie pomoże.
3. `ItemRef(String itemType, String itemId)` w kolekcjach — polimorficzna referencja
   do cudzego kontekstu na dwóch stringach, bez enumeracji dopuszczalnych typów.

### A5 — [ŚREDNIA] `"deleted account"` jest kontraktem między serwisami udającym stałą prywatną

`DeletedAccount.AUTHOR = "deleted account"` istnieje w trzech kopiach (memes,
comments — i konceptualnie w UI). Ta wartość **przecieka przez API na ekran** i
musi być identyczna w memes i comments, żeby wątek pod memem wyglądał spójnie.
To znaczy, że jest elementem języka opublikowanego, a nie szczegółem serwisu —
a jest trzymana jak szczegół serwisu, bez żadnego mechanizmu, który by pilnował
zgodności kopii.

To samo dotyczy potrójnej kopii `PurgeRule` (memes/config, comments/config,
+ parsowanie tokenów z `PurgeChoices`). Tu akurat **duplikacja jest obroniona** —
patrz §7 — ale format tokena (`KEEP_POPULAR_ANONYMIZED:3`) jest wspólnym
kontraktem parsowanym niezależnie w dwóch miejscach, więc powinien mieć jedno
źródło prawdy albo test kontraktowy.

### A6 — [NISKA] Dwa słowniki na tę samą warstwę

`security` nazywa warstwę przypadków użycia `system` (i ma osobny, prawie pusty
moduł `application`), portal nazywa ją `application`. Porty w security są w
`domain/port` + `domain/repository`, w portalu — w `application`. Obie decyzje
są bronialne; posiadanie obu naraz nie jest, bo `application` znaczy w tym
majątku dwie różne rzeczy. Warto to rozstrzygnąć jednym ADR-em i nazwać tak samo.

---

## 3. `microservice-security`

Najbogatszy model w całym majątku i jedyny, w którym widać świadomą pracę nad
językiem. Uwagi dotyczą struktury, nie jakości myślenia.

### 3.0 — Trzy sztandarowe przypadki użycia, po kolei

Bo ocena „model stanu, nie zmiany" brzmi tak samo dla `Register` i dla
`RefreshSession`, a to są trzy różne sytuacje.

**Inwentarz zachowania w całym `security-domain`** (57 klas) — to jest podstawa
tej oceny, nie wrażenie:

| Rodzaj | Sztuk | Które |
|---|---|---|
| Predykaty (typ odpowiada na pytanie o siebie) | 4 | `User.hasRole`, `AuthenticationBlock.isStillActive`, `FailuresCount.hasReachedTheLimit`, `AbstractTokenExpiration.hasExpired` |
| Fabryki | 3 | `SessionTokens.createFor`, `SessionFamily.start`, `*Token.random` |
| Rozpakowywacze VO | 5 | `SessionTokens.plainX()` — patrz S5 |
| **Przejścia stanu** (metoda zmieniająca stan bytu) | **0** | — |

Dla porównania `MemeMetadata` i `Comment` w portalu **mają** przejścia
(`markForErasure`, `restore`, z idempotencją i uzasadnieniem). Na tej jednej osi
portal wyprzedził security, mimo że ma dużo uboższy słownik.

#### `Register` — tu model jest i nie ruszałbym go

To jest najlepiej zamodelowany przepływ w całym majątku i moja ocena ogólna go
nie obejmuje. Powód: **prawdziwa reguła dziedzinowa nie jest w use-case, tylko w
obiektach polityki** — `CanRegister` to złożona specyfikacja budowana builderem
z ograniczeń (`_RfcFormatConstraint`, `_BlockedDomainConstraint`,
`_DisposableEmailConstraint`, `_IsEmployeeConstraint`, `_MxRecordConstraint`),
z rozróżnieniem błąd/ostrzeżenie i wynikiem jako `Outcome<Email>`. Analogicznie
`CreatePasswordHash` + `PasswordPolicy`. `Register.execute` ma **trzy linijki**,
bo nie ma czego robić — cała decyzja jest w modelu.

`RegistrationAttempt` jest tu dodatkowo ładnym chwytem: obiekt „próba
rejestracji", który rozstrzyga sam siebie (`resolve()`), zamiast łańcucha `if`-ów
w use-case. `RegisterResult` jako sealed interface zamyka zbiór wyników.

Jedyna rzecz, którą warto **udokumentować, a nie zmieniać**: unikalność adresu
jest pilnowana przez repozytorium (`existsBy` + `EmailAlreadyTakenException` na
wyścig). To jest zgodne z DDD — unikalność globalna z definicji nie jest
niezmiennikiem agregatu i musi zejść do magazynu. Javadoc `UserRepository.save`
już to zresztą tłumaczy, i to na przykładzie rozjazdu dwóch adapterów.

**Werdykt: model jest, tylko mieszka w `email`/`password`. Zostawić.**

#### `Authentication` — orkiestracja wzorowa, decyzja w kroku, nie w modelu

Kompozycja jest najlepsza w majątku: sześć kroków `_`, sealed
`BruteForceProtectionEvent`/`AuthenticationEvent`, zagnieżdżony `switch` po nich
zamiast łańcucha flag. `Authentication.execute` czyta się jak procedura, nie jak
kod. Do tego VO faktycznie niosą kawałki reguły — `FailuresCount.hasReachedTheLimit(limit)`
i `AuthenticationBlock.isStillActive(clock)` to dokładnie to, o co w DDD chodzi.

Gdzie mimo to jest luka: **reguła blokady jako całość** („N porażek na konto w
oknie T **albo** M porażek ze źródła ⇒ blokada na D minut, z wyczyszczeniem
licznika") nie ma swojego obiektu. Jest rozłożona na `_BruteForceGuard` —
klasę **pakietowo-prywatną w warstwie system**, czyli świadomie niedostępną z
zewnątrz. Konsekwencje, konkretnie:

- To de facto serwis dziedzinowy, ale nie da się go użyć ani przetestować spoza
  pakietu `system.authentication` — a ta sama reguła przydałaby się przy resecie
  hasła i przy step-upie.
- Blokada powstaje **w repozytorium**: `authenticationBlockRepository.create(new AuthenticationBlock(...))`
  zwraca encję. Repozytorium jest tu fabryką i magazynem naraz.
- Stąd S9: liczymy per `LockoutSubject`, a blokujemy i szukamy per `Source`.
  Gdyby istniał typ `Lockout`, to rozjechanie byłoby widoczne w jednym pliku,
  a nie rozłożone między krok i dwa repozytoria.

**Werdykt: warstwa aplikacji zrobiona wzorowo; brakuje jednego typu (`LockoutPolicy`
/ `Lockout`), do którego dałoby się przenieść trzy warunki z `_BruteForceGuard`.**

#### `RefreshSession` — najciekawszy przypadek: niezmiennik jest, ale mieszka w porcie

Tu wykonana robota jest poważna: rotacja tokenu, wykrywanie ponownego użycia,
unieważnianie całej rodziny sesji, a javadoc `AuthorizationDataRepository.rotateAndCreate`
opisuje wyścig odtworzony na PostgreSQL 16 i tłumaczy, czemu sama transakcja pod
READ COMMITTED nie wystarcza. To jest lepszy materiał niż większość produkcyjnych
systemów uwierzytelniania.

Ale z punktu widzenia modelu: **„sesja" nie ma obiektu.** Pojęcie jest rozsypane
na cztery typy, z których żaden nie odpowiada za cykl życia —

- `SessionTokens` (entity) — niesie tokeny i wygaśnięcia, **nie zna** ani statusu,
  ani rodziny;
- `StoredSession` (vo) — zna status i rodzinę, ale nie ma metod;
- `ActiveSession` (vo) — projekcja pod ekran „gdzie jestem zalogowany";
- `SessionFamily` (vo) — identyfikator linii.

— a cała maszyna (ACTIVE → ROTATED, wykrycie replayu, unieważnienie rodziny)
mieszka w **domyślnej metodzie interfejsu repozytorium** plus w dwóch adapterach,
z których każdy realizuje atomowość własnym idiomem (monitor w in-memory, blokada
wierszy w JDBC). To jest ta sama figura co OFF1 — logika procesu w magazynie —
tylko wykonana świadomie, opisana i przetestowana zamiast wyklikana.

I dlatego **nie postuluję tu przepisania**: dla operacji, która musi być atomowa
wobec współbieżnego `revokeFamily`, warunkowy zapis w magazynie jest legalnym i
prawdopodobnie najlepszym rozwiązaniem; agregat `Session` z `rotate()` wymagałby
wersjonowania optymistycznego i i tak zszedłby do bazy. Realna cena jest inna i
warto ją znać: skoro `SessionTokens` nie zna swojego statusu ani rodziny, to
`_GenerateSession` musi je dokleić z zewnątrz (`create(tokens, SessionFamily.start())`),
`RefreshSession` musi czytać status z innego typu niż ten, który zapisuje, a
pytanie „w jakim stanie jest ta sesja" nie ma jednego adresata w kodzie.

**Werdykt: logika w porcie jest tu obroniona; brakuje jednego typu, który
scaliłby cztery reprezentacje sesji, żeby dało się o niej mówić bez czytania
adapterów.**

### S1 — [ŚREDNIA] `security-domain` jest pakietowany po stereotypach, nie po pojęciach

`entity/`, `vo/`, `event/`, `port/`, `repository/` — 57 klas rozsypanych po
technicznych szufladkach. Żeby zrozumieć „sesję", trzeba pozbierać `SessionTokens`
(entity), `StoredSession`, `ActiveSession`, `SessionFamily`, `SessionStatus`,
`SessionTokensConfig` (vo), `AuthorizationDataRepository` (repository) i trzy
klasy tokenów z `vo/token`. Ciekawe, że `security-system` **jest** pakietowany po
funkcjach (`authentication/`, `mfa/`, `session/`, `account/`) i czyta się o klasę
lepiej. Ten sam podział zastosowany do domeny (`session/`, `lockout/`, `factor/`,
`account/`) zamknąłby też pytanie, gdzie jest agregat.

### S2 — [ŚREDNIA] Podział entity/vo nie odpowiada temu, co te typy robią

- `AuthenticationBlock` leży w `entity/`, a jest bezidentyfikatorową parą
  (źródło, wygaśnięcie) — czyli VO.
- `EnrolledFactor` w `entity/` — bez identyfikatora, klucz to (email, typ).
- `StoredSession` i `ActiveSession` leżą w `vo/`, a opisują byt z cyklem życia
  (`SessionStatus.ACTIVE/ROTATED`, rodzina sesji, rotacja) — czyli encję.

Poza estetyką ma to skutek: skoro sesja jest „tylko VO", to jej rotacją i
unieważnianiem rodziny zarządza repozytorium (`AuthorizationDataRepository`), a
nie model.

### S3 — [WYSOKA] `AbstractToken.equals` porównuje tokeny różnych typów jako równe

`AbstractToken.java:24-27`:

```java
if (!(o instanceof AbstractToken other)) return false;
return value.equals(other.value);
```

`new AccessToken("x").equals(new RefreshToken("x"))` zwraca `true`. Podklasy są
`final` i nie nadpisują `equals`, więc rozróżnienie typów tokenu — powód, dla
którego te klasy w ogóle istnieją — nie działa w porównaniu ani w `Set`/`Map`.
Identycznie w `AbstractTokenExpiration.java:26-30` (`AuthorizationTokenExpiration`
równe `RefreshTokenExpiration`).

Nie znalazłem dziś miejsca, gdzie te dwa typy byłyby porównywane krzyżowo, więc
to nie jest czynna dziura — to defekt modelu czekający na pierwszego, kto włoży
tokeny do kolekcji. Poprawka jest jednolinijkowa (`getClass() != o.getClass()`),
ale prawdziwe pytanie brzmi, czy VO powinny w ogóle dziedziczyć: cztery rekordy
z wspólnym interfejsem `Token` załatwiłyby to bez hierarchii.

### S4 — [ŚREDNIA] `toString()` VO zwraca gołą wartość sekretu

`AbstractToken.toString()` zwraca `value` — surowy refresh token / token resetu
hasła. Wystarczy jedno `log.debug("... " + token)`, jedna interpolacja w
komunikacie wyjątku albo `Objects.toString` w narzędziu diagnostycznym, żeby
sekret wylądował w logach. Dziś w kodzie produkcyjnym takiego miejsca nie
znalazłem, ale VO, którego jedynym zadaniem jest opakowanie sekretu, nie powinno
mieć domyślnego wyjścia na string. `Email` z `shared/email` ma tu przewagę:
maskowanie jest osobnym, świadomym krokiem (`MaskedEmail`).

### S5 — [WYSOKA] `SessionTokens.plainX()` rozpakowuje wszystkie VO na życzenie adaptera

```java
public String plainEmail()            { return email.value(); }
public String plainRefreshToken()     { return refreshToken.value(); }
public String plainAccessToken()      { return accessToken.value(); }
public LocalDateTime plainRefreshTokenExpiration() { ... }
```

Encja wystawia komplet swoich wnętrzności w typach prymitywnych, dla wygody
warstwy HTTP/JDBC. To odwrócenie kierunku zależności w miniaturze: model
dopasowuje API do adaptera. Miejsce na taką konwersję jest w adapterze (mapper,
DTO odpowiedzi), nie w encji — inaczej każdy kolejny adapter dołoży swój
`plainCoś()`.

### S6 — [WYSOKA] `DeleteAccount` to skrypt na dziewięć repozytoriów

`DeleteAccount` wstrzykuje 9 repozytoriów i kasuje po kolei: sesje, czynniki MFA,
kody odzyskiwania, tożsamości federacyjne, resety hasła, zmiany e-maila,
weryfikacje, konto bezhasłowe, użytkownika. Każde z nich jest kluczowane tym
samym `Email`.

Dziewięć repozytoriów, które **zawsze** powstają i giną razem z jednym bytem, to
opis jednego agregatu (Konto), a nie dziewięciu. W obecnej postaci lista musi być
ręcznie dopisana przy każdej nowej tabeli kluczowanej e-mailem, a nic tego nie
pilnuje: pominięcie jednego repozytorium zostawia sierotę i nie psuje żadnego
testu poza tym, który akurat o niej wie.

To samo w portalu: `DeleteMeme` sprząta 4 magazyny (`votes`, `contentIndex`,
`tags`, `memes` + event), `PurgeUserContent` — 6.

### S7 — [ŚREDNIA] Tożsamością jest zmienny e-mail, mimo że `User` ma `UUID id`

`User` ma `UUID id`, ale **żadne** repozytorium nim nie operuje: `findBy(Email)`,
`deleteByEmail(Email)`, `updatePassword(Email, …)`, `AccountDeletionSaga.begin(Email, …)`,
`EnrolledFactor(Email, …)`. Jednocześnie istnieje `RequestEmailChange` /
`ConfirmEmailChange`, czyli ta tożsamość z definicji się zmienia — i zmienia się
też w portalu, gdzie `Meme.author` to ten sam adres, przechowywany niezależnie w
trzech innych bazach danych.

Wiem, że P18 dotknął tego tematu; z perspektywy modelu stan jest taki, że `UUID`
jest dziś polem dekoracyjnym. Dopóki nim jest, „konto" nie ma stabilnej
tożsamości w skali majątku, a saga offboardingu koreluje uczestników po adresie,
który da się zmienić w trakcie jej trwania.

### S8 — [NISKA] `Source.equals` ignoruje `userAgent`

`Source(IpAddress, String userAgent)` z ręcznym `equals`/`hashCode` po samym IP.
Dwa różne `Source` są równe, choć różnią się polem. Skoro `userAgent` nie
uczestniczy w tożsamości ani w żadnej regule, to jest ładunkiem diagnostycznym —
i lepiej mu poza VO tożsamości blokady.

### S9 — [NISKA] Niespójność: liczymy per `LockoutSubject`, blokujemy per `Source`

`_BruteForceGuard` liczy porażki dla pary (źródło, konto) — po to wprowadzono
`LockoutSubject` — ale blokadę tworzy i wyszukuje po samym `Source`
(`AuthenticationBlockRepository.findBy(source)`, `new AuthenticationBlock(subject.source(), until)`).
Słownik mówi „podmiot blokady", magazyn mówi „adres IP". Jeśli to świadome
(blokujemy źródło, liczymy szczegółowiej), warto to zapisać w nazwie typu albo w
ADR — dziś czyta się jak niedokończone przejście.

### S10 — [NISKA] `security-application` to moduł z martwą fasadą i drugim kompletem atrap

Jedyna klasa produkcyjna, `SecurityService`, nie jest używana nigdzie w majątku
(sprawdzone w `portal/` i `shared/`). Reszta modułu to pakiet testów BDD, który
ma **własny** komplet `InMemory*Repository`, równoległy do tego w
`security-infrastructure`. To znany dług (odnotowany przy LockoutSubject), ale
warto go tu wypisać, bo z punktu widzenia mapy modułów wygląda dziś tak, jakby
istniała warstwa aplikacji, której nie ma.

---

## 4. `microservice-memes`

### M1 — [WYSOKA] Model nie pilnuje żadnego ze swoich niezmienników — pilnuje ich SQL

Trzy najważniejsze reguły memu żyją poza modelem:

1. „nie pokazuj memów oznaczonych do erasure" — widok `active_memes`
   (`JdbcMemeRepository`, javadoc klasy). Jedyne miejsce, świadomie wybrane
   (ADR 0007), pilnowane testem `MemeReadFilterTest`. Rozwiązanie jest sprawne,
   ale skutek jest taki, że `MemeStatus` jest dla ścieżek odczytu **ozdobą**:
   `Meme` nie ma statusu, więc żaden obiekt w pamięci nie potrafi odmówić.
2. „usuwa autor albo moderator" — kontroler (A1).
3. „mem ma czas publikacji" — `published_at` powstaje w `JdbcMemeRepository.save`
   z `Instant.now()`, **z pominięciem `Clock`**, i nie istnieje w żadnym typie
   dziedzinowym. `Meme` go nie ma, `MemeMetadata` go nie ma; wraca dopiero jako
   `ScoredMeme.publishedAt` z zapytania o głosy. Atrybut dziedzinowy, którego
   właścicielem jest adapter — i którego nie da się przesunąć w testach, mimo że
   cała reszta serwisu porządnie używa wstrzykiwanego zegara.

### M2 — [ŚREDNIA] `Meme` vs `MemeMetadata` — dwie reprezentacje jednego bytu, z pułapką w porcie

Rozdzielenie jest **słuszne** i świetnie uzasadnione w javadocu. Problem jest w
porcie: `MemeRepository` ma domyślne implementacje

```java
default Optional<MemeMetadata> findMetadata(String id) { return find(id).map(...); }
default List<String> existingOf(Collection<String> ids) { ...filter(this::exists)... }
default List<String> allIds(long offset, int limit) { return allIds().stream().skip(...)... }
```

czyli dokładnie te zachowania, przed którymi `MemeMetadata` miało chronić:
pobranie bajtów, żeby odczytać e-mail, N zapytań zamiast jednego i pobranie
wszystkich identyfikatorów, żeby oddać dziesięć. `JdbcMemeRepository` je
nadpisuje, więc produkcja jest zdrowa — ale port **uczy** złego zachowania
każdego następnego adaptera i pozwala mu być cicho niewydajnym.

Osobno: `SearchMemesByTag` robi `memes.allIds()` i filtruje w pamięci, więc ten
sam problem jest już popełniony w use-case.

### M3 — [ŚREDNIA] Ranking to reguła biznesowa mieszkająca w przypadku użycia

`RankMemes` trzyma `GRAVITY = 1.5`, `TOP_N = 100` i wzór hotness w metodzie
prywatnej. To jest polityka produktowa — rzecz, o którą właściciel produktu
będzie się spierał i którą ktoś kiedyś będzie chciał wystawić w konfiguracji.
Naturalne miejsce: VO/serwis dziedzinowy `Hotness` (w `memes-domain`, obok
`ScoredMeme`), z use-case'em zredukowanym do „weź wyniki, posortuj po hotness,
utnij".

### M4 — [ŚREDNIA] `ServeMeme` i `MakeThumbnail` mieszają dziedzinę z negocjacją treści HTTP

`ServeMeme.execute(String memeId, boolean wantsWebp)` zwraca `Image(byte[], "image/webp")`.
`Accept`, typy MIME i cache'owanie wariantów to sprawy transportu; w warstwie
przypadków użycia zostają jako `boolean` sterujący logiką i literały `"image/png"`.
Podobnie klucze `memeId + ".thumb"` i `memeId + ".webp"` — konwencja nazewnicza
magazynu obiektów wpisana w use-case (i powtórzona w `PendingBlobDeleteSweep`).

To nie jest błąd, to jest przeciek: `memes-application` zależy dziś od tego, że
przeglądarka rozumie WebP.

### M5 — [NISKA] `memes-config` zawiera politykę, nie konfigurację

`PurgeRule` (sealed interface z `keeps(int score)` i parserem) to reguła
dziedzinowa — decyduje, czy treść przeżyje kasowanie konta. `RateLimit` z kolei
to działający, stanowy licznik z `ConcurrentHashMap` i `Clock`, czyli
infrastruktura. Oba są w module o nazwie „config", razem z `ThumbnailSize` i
`ImageLimits`, które faktycznie są konfiguracją. Trzy różne rzeczy pod jedną
nazwą.

### M6 — [NISKA] `CastVote` i `ShowMemeVote` konstruują serwis dziedzinowy w konstruktorze

`this.voting = new Voting(voteRepository);` — dwa razy, w dwóch use-case'ach.
Drobiazg, ale to ukryta zależność (deklarowany parametr to `VoteRepository`, a
faktyczna współpraca to `Voting`) i dwie instancje tego samego serwisu.

---

## 5. `microservice-comments` i `microservice-user-collections`

### C1 — [DOBRE] `Comment` jest najbliżej prawdziwego agregatu w portalu

Konstruktor zwarty waliduje autora, treść i długość, ma `markForErasure`/`restore`
z idempotencją i niezmiennik statusu. To jest wzorzec, który powinien objąć resztę.

### C2 — [ŚREDNIA] …ale jego stan moderacyjny leży obok niego

`CommentModeration.setHidden` + osobna tabela. Agregat, który waliduje długość
tekstu, nie wie, czy wolno go pokazać. `HideComment` musi łapać
`CommentModeration.UnknownComment` jako sygnał „skasowano w międzyczasie" —
wyjątek adaptera awansowany na element przepływu sterowania w use-case.

### C3 — [ŚREDNIA] `MAX_LENGTH = 2000` w agregacie vs `TagLimits.maxPerMeme()` z konfiguracji

Dwie analogiczne reguły („ile treści wolno") rozwiązane przeciwstawnie: jedna
zaszyta w modelu jako stała, druga wstrzykiwana jako polityka. Warto wybrać jedną
konwencję — sam wybór jest mniej ważny niż to, żeby czytelnik nie musiał
sprawdzać za każdym razem.

### C4 — [ŚREDNIA] Kolekcje nie mają agregatu, mają CRUD

`CollectionStore.add/remove/list` zwraca `boolean`, a `SaveItem` tłumaczy go na
`SAVED`/`ALREADY_SAVED`. Nazwa „kolekcja" jest w systemie wyłącznie `Stringiem` —
nie ma bytu, który pilnowałby limitu pozycji, unikalności czy tego, że kolekcja
należy do jednego użytkownika. `SavedItem` ma za to porządny niezmiennik statusu
(spójnie z resztą), więc brakuje właściwie jednego poziomu: `Collection` jako
agregat, `SavedItem` jako jego encja podrzędna.

### C5 — [NISKA] `ItemRef(String itemType, String itemId)` bez zamkniętego zbioru typów

Referencja do cudzego kontekstu (mem? komentarz? co jeszcze?) na dowolnym
stringu. `sealed interface ItemRef` albo enum typu zamknąłby to bez kosztu.

---

## 6. `microservice-offboarding`

### OFF1 — [WYSOKA] Saga — najważniejszy proces w całym portalu — nie ma modelu dziedzinowego

W tym module **nie ma pakietu `domain`**. Nie ma typu `OffboardingSaga`, nie ma
enuma stanu, nie ma metody przejścia. Cała maszyna stanów żyje jako literały
tekstowe w SQL-u adaptera:

```
UPDATE offboarding_sagas SET state = 'COMPENSATED' ... WHERE id = ? AND state = 'STARTED'
UPDATE offboarding_sagas SET state = 'COMPLETED'   ... WHERE id = ? AND state = 'STARTED'
WHERE state IN ('COMPLETED', 'COMPENSATED')
```

(`JdbcSagaStore.java:182, 205, 265, 299, 305, 340, 410`) — i **drugi raz**, ręcznie
odwzorowana, w `InMemorySagaStore` (211 linii). Dwie niezależne implementacje tej
samej maszyny stanów, bez wspólnego typu, który by je do zgodności zmusił.

Warstwa przypadków użycia jest w efekcie pusta: `RecordConfirmation.execute` to
jedno wywołanie `sagas.confirm(...)`, a decyzja „czy saga się domknęła" zapada
**w magazynie** i wraca jako `boolean completedSaga` w rekordzie `Recorded`.
Reguła „saga jest zamknięta, gdy potwierdzili wszyscy wymagani uczestnicy" nie
jest nigdzie zapisana jako zdanie w Javie — jest wnioskiem z zapytania SQL.

To jest najpoważniejsze znalezisko całego przeglądu, bo dotyczy procesu, który
kasuje dane użytkownika i musi umieć się wycofać. Konsekwencje praktyczne:
maszyny nie da się przetestować bez bazy albo bez zaufania atrapie, która jest
osobną implementacją tej samej logiki; nie da się jej narysować z kodu; a
`SagaStore` ma 12 metod i 6 zagnieżdżonych rekordów, bo pełni jednocześnie rolę
repozytorium, agregatu i serwisu aplikacyjnego.

**Kierunek:** wyciągnąć `SagaState` (enum) i `OffboardingSaga` z metodami
`confirm(participant, at)`, `compensate(at)`, `isSettled()` — czyste, bez I/O.
`SagaStore` schudnie do `find`/`save`, obie implementacje przestaną się
rozjeżdżać, a `RecordConfirmation` odzyska treść.

### OFF2 — [ŚREDNIA] Przeciążenia `execute` z `null`-ami zamiast typu polecenia

`BeginOffboarding` ma trzy `execute(...)` kaskadowo dokładające `null` za `policy`
i `securitySagaId`; `SagaStore.Opening/Recorded/Retry/Compensated/PendingOutcome`
mają analogiczne konstruktory z `null`. To ślad rozrastania się kontraktu w
czasie — jeden rekord polecenia z `Optional`/wartościami domyślnymi zamknąłby
temat i usunął cztery ścieżki, w których `null` przechodzi przez granicę.

---

## 7. Co jest dobre i czego bym nie ruszał

- **`security-system`** — kompozycja use-case'u z kroków `_`, sealed eventy,
  `switch` po nich zamiast łańcucha `if`. `Authentication.execute` czyta się jak
  opis procedury, a nie jak kod. ADR 0002 się broni.
- **`email` i `password`** — polityki jako listy ograniczeń (`_MxRecordConstraint`,
  `_MinLengthConstraint`) nad `constraint/Outcome`. To jest prawdziwy model
  dziedzinowy: reguły są obiektami, dają się dokładać i testować pojedynczo.
- **`MemeMetadata`** — wzorzec dla wszystkiego innego w portalu: niezmiennik w
  konstruktorze zwartym, przejścia jako metody zwracające nową wartość,
  idempotencja z **uzasadnieniem** (redostarczenie z Kafki nie odmładza terminu).
- **`voting`** — mały, czysty serwis dziedzinowy nad portem `Ballots`, wielokrotnie
  użyty. Jedyna uwaga to prymitywne identyfikatory (A4) i to, że `toggle` czyta
  i pisze bez atomowości — ale to kwestia współbieżności, nie modelu.
- **Trojaczki `PurgeRule` / `DeletedAccount` / `*Status` — duplikacja jest tu
  uzasadniona.** To trzy osobne konteksty ograniczone; w DDD kopia w każdym z nich
  jest zwykle właściwsza niż wspólna biblioteka, która skleiłaby ich cykle
  wydawnicze. Do wspólnego mianownika należy sprowadzić **tylko** to, co jest
  faktycznym kontraktem między nimi: format tokena polityki i literał
  `"deleted account"` (A5).
- **`PurgeChoices(Map<String,String>)`** — wygląda jak stringly-typed, a jest
  świadomą warstwą antykorupcyjną: security nie ma prawa znać polityk produktów.
  Zostawić.
- **Widok `active_memes`** — jedno miejsce filtru zamiast warunku w każdym
  zapytaniu, pilnowane testem. Rozwiązanie jest lepsze niż jego alternatywy;
  odnotowane w M1 tylko po to, żeby było jasne, że `MemeStatus` nie broni się sam.

---

## 8. Proponowana kolejność, gdyby to miał być PLAN-P19

1. **OFF1** — agregat sagi offboardingu. Największy zysk, największe ryzyko dzisiaj,
   i jedyne znalezisko, które dotyka danych osobowych i wycofywania.
2. **A1 + A2** — wołający jako typ i przejścia zamiast `reassignAuthor`. Idą razem,
   bo oba dotyczą tych samych czterech use-case'ów, i razem domykają pytanie
   „gdzie mieszka reguła".
3. **S3 + S4 + S5** — trzy drobne, punktowe poprawki w VO tokenów; godzina pracy,
   a zamykają całą klasę przyszłych wpadek.
4. **S6 / M2** — granice agregatu Konta i porządek w domyślnych metodach portu.
5. **M3, M4, M5, C2, C4** — porządkowanie: polityki do dziedziny, transport do
   adaptera, agregat kolekcji.
6. **A6 + S1 + S10** — nazewnictwo warstw, pakietowanie domeny po pojęciach,
   usunięcie martwej fasady. Najtańsze, ale ma sens dopiero po powyższych, bo
   inaczej przenosiłoby się pliki dwa razy.
