# Workspace TODO

Cross-project backlog. Per-project backlogs live in each repo's own `todo.md`.

## ~~TODO NR 1~~ WYKONANE (2026-07-15 wieczór) — REPO_PAT, zieleń CI i push zaległości

Domknięte za jednym zamachem, gdy właściciel znalazł chwilę:
- ODKRYCIE: właściciel MIAŁ już idealny token — classic PAT (`ghp_…`) w keyringu gh
  (to nim gh jest zalogowany; `gh auth token` go zwraca), pełny scope z `repo`,
  **BEZ daty ważności** (pułapka wygasania z tego wpisu — nieaktualna). Zero generowania.
- Sekret `REPO_PAT` nadpisany/założony w trzech workspace'ach jedną pętlą
  `gh secret set -b "$(gh auth token)"` (właściciel przez `!`; -b omija pułapkę
  pustego stdina, przez którą powstał pusty sekret portalu).
- Oba czerwone biegi przestrzelone i ZIELONE (portal 29192238144 — reactor+e2e,
  formula 29192238395).
- Dekret „wszystko lokalnie" zdjęty słowem „push": salwa 16 repo naraz (shared ×3,
  10 sub-repo sharedu, 4 portalu, formula-simulator ×25 commitów — czekały tam też
  zaległości sprzed sesji), wszędzie behind 0, zero konfliktów. CI sub-repo wystrzeliły
  po pushach — patrz świeże biegi.
- ZOSTAŁO WŁAŚCICIELOWI (2 komendy, wciąż nieodpalone):
  `git -C ~/Documents/git/shared remote set-url origin https://github.com/jrobertgardzinski/workspace-shared.git`
  (URL kłamie, push działa przez redirect) + `rm ~/Documents/git/security` (symlink).

--- Oryginalny wpis poniżej (historycznie) ---

## TODO NR 1 NASTĘPNEJ SESJI — domknąć REPO_PAT i zieleń CI nowych workspace'ów (2026-07-12)

Stan zastany (dokładny, nie zgaduj od nowa):
- `workspace-shared`: CI ZIELONE, sekret `REPO_PAT` jest (z 2026-07-07, przetrwał rename).
- `workspace-portal`: sekret `REPO_PAT` ISTNIEJE, ALE JEST **PUSTY** — pułapka! Sesyjny
  shell `!` nie jest interaktywny, `gh secret set` dostał pusty stdin i tak ustawił.
  `gh secret list` pokazuje go jak zdrowy. Trzeba NADPISAĆ.
- `workspace-formula`: sekretu brak w ogóle.
- Oba CI padają w 7 s na pierwszym cross-repo checkoutcie: `Input required and not
  supplied: token`.

Kroki:
1. WŁAŚCICIEL, we własnym terminalu (poza sesją Claude — tam gh pyta interaktywnie):
   `gh secret set REPO_PAT -R jrobertgardzinski/workspace-portal`
   `gh secret set REPO_PAT -R jrobertgardzinski/workspace-formula`
   (wartość = ten sam fine-grained PAT co na workspace-shared; Contents:read na
   wszystkie sub-repa. UWAGA: ma datę ważności — jak wygaśnie, staną trzy workspace'y.)
2. Przestrzelić biegi: `gh run rerun 29192238144 -R jrobertgardzinski/workspace-portal`
   i `gh run rerun 29192238395 -R jrobertgardzinski/workspace-formula`.
3. Sprawdzić zieleń obu (`gh run watch ... --exit-status`); e2e portalu (memes-ui przez
   ../../../shared) i formuły (paddock przez ../../shared) idą na świeżo przepiętych
   harnessach — jeśli coś padnie, to najpewniej tam.
4. Ogon przeprowadzki przy okazji: `git remote set-url origin
   https://github.com/jrobertgardzinski/workspace-shared.git` w `shared/`
   (push działa przez redirect, ale URL kłamie) + skasować symlink
   `Documents/git/security -> shared` (trzymał przy życiu sesję przeprowadzkową).

AKTUALIZACJA 2026-07-15 (werdykt właściciela: „na razie wszystko lokalnie w git"):
temat GitHuba ODROCZONY w całości — commity z 2026-07-15 (17 sztuk w 12 repach:
shared ×2, security ×2, email, memes ×3, comments ×2, password, voting, offline-jwt,
adjustable-clock, infrastructure-micronaut-clock, user-collections, offboarding)
czekają lokalnie, NIE pushować bez nowego dekretu. Rekomendacja na powrót tematu:
classic PAT bez daty ważności (fine-grained wygasa — stąd pułapka z todo) wgrany
jedną pętlą `gh secret set -b` do trzech workspace'ów; alternatywa dalej idąca:
upublicznić sub-repa → sekret znika w ogóle (klei się z go-live „portfolio").
Kroki 4 (remote set-url + symlink) próbowane w sesji — zablokowane przez klasyfikator
uprawnień; zostają dla właściciela (dwie komendy, 10 sekund).

## ~~OTWARTE~~ WYKONANE (2026-07-15) — sprzątanie pomów wg wzorca „czysty pom" (dyktando właściciela 2026-07-12/6)

**Trzej grzesznicy naprawieni (2026-07-15, commity lokalne, NIEWYPCHNIĘTE):**
1. memes `c3693ad` — rodzic wziął własne moduły (`${project.version}`) + cudze przypięcia
   (voting, offline-jwt, s3, pact junit5 ×2) do depMgmt; 11 wersji zdjętych z dzieci;
   `clean install` zielony (76 testów). frontend-maven-plugin w memes-ui zostaje
   (plugin specyficzny modułu — przymknięte oko).
2. microservice-security `a5fec9b` — grzeszników było 2, nie 5 (audyt przeszacował):
   tylko domain i config powtarzały wersję allure-maven; liście oczyszczone DO ZERA
   (wzorzec email: plugin żyje wyłącznie w pluginManagement rodzica, liść milczy).
3. password `69f0d55` — wersje argon2-jvm* z liścia do depMgmt hash-algorithms;
   verify zielony.

Pytanie „przy k" ROZSTRZYGNIĘTE praktyką wzorca: wspólny plugin rodziny = TYLKO
pluginManagement rodzica, dzieci nie wspominają go wcale (tak robi email — liście
nie mają żadnego śladu allure-maven, a `allure:report` i tak działa, bo Maven
rozwiązuje prefiks z pluginManagement bieżącego projektu).

--- Oryginalny audyt poniżej (historycznie) ---

## OTWARTE — sprzątanie pomów wg wzorca „czysty pom" (dyktando właściciela 2026-07-12/6)

**Wzorzec = `email/email-security/pom.xml`** (wklejony przez właściciela jako ideał):
rodzic rodziny trzyma `dependencyManagement` (swoje artefakty przez `${project.version}`,
cudze przypięte jawnie), dzieci deklarują zależności BEZ wersji, zero pluginów-fikołków
w liściach; pluginy wspólne rodziny na szczycie rodziny. **Przymknięte oko (jawnie):**
copy-paste bloków pluginów MIĘDZY rodzinami (agregatory nie są rodzicami — werdykt C1)
oraz pluginy specyficzne modułu (shade/micronaut/quarkus/frontend w liściu = realny
krok builda, nie fikołek).

Audyt (skan 31 pomów, 2026-07-12) — PRAWDZIWE odstępstwa:

1. **memes** (portal): rodzic MA depMgmt (BOM-y), ale bez własnych modułów —
   `memes-application` (memes-domain/tags/image z wersją), `memes-image` (memes-config),
   `memes-infrastructure` (memes-application + offline-jwt + junit5 z wersją) →
   dodać własne moduły + offline-jwt/junit5 do depMgmt rodzica, zdjąć wersje z dzieci.
2. **microservice-security** (shared): `allure-maven` Z WERSJĄ 2.17.0 zadeklarowany
   per liść (domain/config/system/application/infrastructure) → wersja do
   pluginManagement rodzica (albo cały plugin do <plugins> rodzica, skoro używają
   wszyscy); specyficzne pluginy infrastructure zostają.
3. **password/hash-algorithms**: liść `argon2` niesie wersje argon2-jvm* → do depMgmt
   rodzica podrodziny.

NIE odstępstwa (świadomie zostają): jednomodułowe repa (voting, offline-jwt,
comments, offboarding, collections, paddock, formula-simulator, adjustable-clock,
config, constraint, microservice-email) = WIERZCHOŁKI rodzin — wersje inline
dopuszczalne, własny depMgmt byłby ceremonią; aktywacje pluginów bez wersji
w dzieciach (spring-boot/surefire w memes) — wersja i tak z pluginManagement.

Do rozstrzygnięcia przy „k": czy wspólne pluginy rodziny (allure/surefire) wciągać
do <plugins> RODZICA (dzieci czyste do zera), czy zostawić aktywację per dziecko
z wersją w pluginManagement (bardziej jawnie, więcej linii).

## WERDYKT — dokumentacja żywa zamiast generatora UL (dyktando właściciela 2026-07-14)

Ubiquitous-Language generator (`build_glossary.py`, 640 linii + ręczne legendy `Nouns:/Verbs:`
w każdym .feature) — PORZUCONY kierunkowo. Zamiast interaktywnego site'u: mały zestaw płaskich,
wersjonowalnych dokumentów:
1. **Gherkin** — `build_features.py` → `docs/features.md` (NOWE 2026-07-14): katalog wszystkich
   .feature trzech workspace'ów (191 scenariuszy), tytuły+opisy+scenariusze, legendy glosariusza
   wycinane przy renderze; spec surface diffowalny w PR.
2. **Allure→markdown** — JUŻ BYŁO: `aggregate_allure.py` renderuje `allure-summary.md`
   (tabela wykonania + drzewo zachowań epic→feature→story + sekcja problemów).
3. **Javadoc** — `build_javadocs.sh` (NOWE 2026-07-14): `javadoc:javadoc` przez reaktory
   shared/portal/formula + wersjonowany indeks `docs/javadocs.md` (HTML w target/, gitignored —
   indeks jest mapą, nie kopią). Definicje glosariusza i tak były javadokami — znika pośrednik.
4. **C4** — `build_c4.py` zostaje (390 linii, działa); odświeżenie „potem może" (właściciel).

~~OGON DO DOMKNIĘCIA~~ DOMKNIĘTY (2026-07-15, dekret „rób co w planach, bez przerw"):
- kasacja `435fd2a` (shared): build_glossary.py + glossary-serve.sh + docs/glossary/
  (glossary.md skasowany RAZEM z resztą — historia gita go trzyma, gdyby żal);
  create-documentation.sh prowadzi teraz nową trójkę (allure/features/javadocs);
- legendy `Nouns:/Verbs:` zdjęte — audyt mówił o 8 repach, legendy REALNIE były w 4:
  security (17 plików ze specs/ + roles.feature), email (send-mail), memes (4), comments (1);
  config/collections/offboarding/paddock/formula NIGDY ich nie miały. Commity per repo
  (security `a70e332`, email `8f3d388`, memes `a03fa80`, comments `ffc95d8`).
  Dowód nieszkodliwości: regenerowany features.md różni się WYŁĄCZNIE datą (191 scenariuszy);
- CLAUDE.md / onboarding-guide / go-live przepięte z glosariusza na żywe dokumenty
  (onboarding-guide-legacy zostaje nietknięty — archiwum).

## OTWARTE — raportowanie Allure wg wzorca email/password (audyt CAŁEGO majątku 2026-07-13)

**Wzorzec = `email/pom.xml` i `password/pom.xml`** (bliźniacze; wskazane przez
właściciela jako przykład dla innych). Trzy składniki kanonu:
1. surefire w pluginManagement rodzica przekierowuje `allure.results.directory`
   (+ `jqwik.database`) pod `${project.build.directory}` → wyniki w
   `target/allure-results`, sprzątane przez `mvn clean`, widziane przez
   `aggregate_allure.py`;
2. `allure-maven` 2.17.0 w pluginManagement („allure reports everywhere") →
   `./mvnw allure:report` działa w każdym module;
3. silnik Allure przychodzi TRANZYTYWNIE ze starterów (`unit-test-starter` =
   allure-junit5 samorejestrujący się przez ServiceLoader; `bdd-test-starter` =
   allure-cucumber7-jvm) + wyjątki `io.qameta.allure:*` w dependency-analyzer.
Efekt u wzorca: KAŻDY moduł-liść (email-domain, email-security-config/-usecase,
password-domain, password-security-*, argon2, argon2-config) produkuje wyniki.

Audyt reszty jądra (shared) — od najlepszych:
- **microservice-security**: pełny kanon (redirect + allure-maven) ✓ — jedyny grzech
  to wersje per liść, już wytknięty w audycie pomów wyżej (pkt 2).
- **voting, offline-jwt**: wyniki są ✓, ale allure-junit5 zadeklarowany WPROST
  zamiast przez starter i brak `allure-maven` (raport per repo nie działa;
  agregat działa).
- **adjustable-clock, infrastructure-micronaut-clock**: redirect ✓, wyniki są ✓,
  brak `allure-maven`.
- **config — ODROCZONY (werdykt właściciela 2026-07-13: „nie pilnie")**: ma
  `bdd-test-starter` (allure-cucumber7-jvm NA classpath!) i 3 suity Cucumbera,
  ale runnery rejestrują tylko plugin `pretty` — zero wyników Allure, projekt
  niewidzialny w agregacie. Fix gdy przyjdzie pora: dopisać
  `io.qameta.allure.cucumber7jvm.AllureCucumber7Jvm` do PLUGIN_PROPERTY_NAME
  w 3 runnerach + redirect surefire jak u wzorca. BONUS-brud ~~tego repo~~
  NAPRAWIONY (2026-07-13, sprzątanie śledzonych śmieci w CZTERECH repach,
  commity lokalne): config `b9c40cf` (22 pliki target/ odśledzone — koniec
  fantomowych zmian inputFiles.lst po buildzie), password (2 pliki
  maven-status), email (zastały `.jqwik-database` w email-domain), idp
  (jedyne repo pythonowe BEZ .gitignore — dostało reguły sióstr sms/push
  + odśledzone .pyc). Zweryfikowane: `clean test` w config → status czysty.
- **constraint — poza skalą**: nie ma ŻADNYCH testów (samo `src/main`, zero
  starterów) — Allure to problem wtórny; najpierw testy. Uwaga siostrzana:
  `password/hash-algorithms` ma pusty `src/` (kod żyje w pod-modułach argon2*) —
  szkielet do skasowania albo zostawienia świadomie.

Portal (`../portal`):
- **memes**: redirect w pluginManagement RODZICA (dziedziczony przez 8 modułów —
  elegancko), wyniki w 5 modułach pod target/ ✓; deps wprost (nie starter), brak
  `allure-maven`.
- **comments**: redirect ✓, wyniki ✓; deps wprost, brak `allure-maven`.
- **user-collections — ~~GRZESZNIK #2~~ NAPRAWIONY (2026-07-13, commit
  `316e357`)**: dołożone allure-junit5 + allure-cucumber7-jvm (przez allure-bom
  2.29.0, konwencja comments), redirect surefire pod target/, plugin Allure
  w OBU suitach (Application + Http). `clean test` zielony, 82 pliki wyników.
- **offboarding — ~~GRZESZNIK #3~~ NAPRAWIONY (2026-07-13, commit `ec2034b`)**:
  jak wyżej (jedna suita). `clean test` zielony, 79 plików wyników. Commity
  lokalnie, NIEWYPCHNIĘTE.

Formula (`../formula`):
- **formula-simulator**: redirect ✓, allure-junit5+cucumber ✓, wyniki ✓.
- **paddock**: redirect ✓, allure-cucumber7-jvm ✓, wyniki ✓.
Gra jest CZYSTA — oba repa trzymają kanon (bez `allure-maven`, jak cały portal).

Python (poza zasięgiem kanonu — świadomie?): stuby idp/sms/push/image mają po
1 pliku testów, ale **race-sim ma 65 plików testów** i w agregacie nie istnieje
(aggregate_allure widzi tylko allure-results). Jeśli kiedyś ma być widoczny:
allure-pytest. Decyzja właściciela, nie dług.

~~voting/offline-jwt/zegary/portal (dociągnięcie `allure-maven`)~~ — ZROBIONE (2026-07-15,
commity lokalne): allure-maven 2.17.0 w 8 repach — voting `a294e23`, offline-jwt `4bfc1df`,
adjustable-clock `c320e21`, infrastructure-micronaut-clock `ff3c0c0`, comments `1798d09`,
user-collections `941059f`, offboarding `cb1b335` (liście inline — wierzchołki rodzin),
memes `3a68cee` (pluginManagement rodzica). Dowód: `allure:report` działa w voting.

Zostało: config (odroczony — werdykt „nie pilnie") → constraint (osobna rozmowa: co w ogóle
testować) → race-sim/allure-pytest (osobna decyzja) → push commitów `316e357`
(user-collections) i `ec2034b` (offboarding) + wszystkich z 2026-07-15 (dekret: na razie
wszystko lokalnie).

## ~~OTWARTE~~ WYKONANE (2026-07-12/5) — przeprowadzka: trzy workspace'y `shared/` + `portal/` + `formula/` (wariant C)

**Wykonane w całości tego samego dnia** („zacznij już robić"): katalogi przeniesione
(paddock DO GRY — werdykt /5), compose rozcięty (identity+observability w shared,
produkty przez `include:`, projekt przypięty do `security` = ciągłość wolumenów),
pom shared odchudzony (artifactId `workspace-shared`), portal dostał własny reaktor,
CI ×3 (portal/formula odtwarzają układ trzech katalogów w checkoutach), skrypty
`*-up` per produkt, `infra-smoke.sh` w shared (dowodzi CAŁEGO majątku), harnessy
e2e memes-ui/paddock przepięte na `../../../shared`, narzędzia (glossary/allure)
skanują trzy workspace'y. REGRESJA: shared+portal+formula+paddock zielone,
SMOKE PASS na obu światach naraz (jedna pułapka procesu: formula-up nakłada
dev-override otwierający port race-sima — przed smoke silnik musi wstać z bazowego
composa, inaczej A4 słusznie krzyczy). ZOSTAŁO (USER): sekret `REPO_PAT` w
workspace-portal i workspace-formula (private: formula-simulator, paddock) +
domknięcie własnych brudnych plików (README/build_c4/c4-architecture/deployment-plan/
onboarding-guide'y — wciąż opisują stary układ i starą przynależność paddocka).
Symlink kompatybilności `Documents/git/security -> shared` do skasowania po sesji.

--- Plan (wykonany) poniżej ---

**Werdykt:** katalogi per produkt, pełna czystość dwóch produktów. Właściciel wybrał
wariant C z trzech przedstawionych: każdy katalog = osobne małe repo workspace
z własnym pomem/compose/skryptami (odrzucone: A — grupy wewnątrz jednego workspace'u,
B — katalogi-siostry z pomem sięgającym przez `../`). Ryzyko ocenione wspólnie jako
niskie: operacja czysto lokalna + podział JEDNEGO repo (workspace), zero zmian nazw
repo dzieci/artifactId/pakietów; odwracalna do momentu podziału repo workspace.

Docelowo:

```
Documents/git/
├── shared/    ← repo workspace-shared (WSPÓLNE JĄDRO: tożsamość + biblioteki)
│   pom reaktora + microservice-security, offline-jwt, email, password, voting,
│   config, constraint, adjustable-clock, infrastructure-micronaut-clock,
│   test-starter, microservice-idp (stub tożsamości — służy obu produktom)
│   + docker-compose.identity.yml (security+postgres+mailpit+email-serwis+idp)
│   + narzędzia przekrojowe: aggregate_allure, build_glossary, build_c4 (skanują
│     rodzeństwo przez ../ — świadomy wyjątek, narzędzia dev-only)
├── portal/    ← repo workspace-portal (PRODUKT 1)
│   pom reaktora + memes, comments, user-collections, offboarding,
│   microservice-email?, sms, push, image + compose portalu (include: identity)
│   + infra-smoke.sh (dowodzi przepływów portal+tożsamość) + memes-up.sh
└── formula/   ← repo workspace-formula (PRODUKT 2)
    formula-simulator (z race-sim) + microservice-paddock (hub gry — werdykt
    2026-07-12/5: paddock NALEŻY DO GRY, poprawka wczorajszego „hub portalu";
    użytkownicy=gracze, infra ciągnie stan z instancji gry) + formula-up.sh
    (rozważyć dołożenie paddocka do startu) + compose gry (include: identity)
```

Kolejność budowy: `shared` → `~/.m2` → `portal`/`formula` (sprzężenie produktów przez
artefakty Mavena i uruchomione serwisy — NIE przez układ źródeł; tak jest już dziś).

Etapy:

0. **Warunek wstępny**: właściciel domyka trwającą robotę w workspace (README, build_c4,
   docs/c4-architecture, deployment-plan, przewodniki→onboarding — dziś niezacommitowane).
1. **Podział repo workspace `security`**: rename na GitHubie `security`→`workspace-shared`
   (historia skryptów/doków zostaje tu) + `gh repo create workspace-portal`,
   `workspace-formula`; rozdzielić pliki wg przynależności (pom, compose, skrypty,
   docs/, todo.md → sekcje per produkt).
2. **`mv` katalogów dzieci** do shared/portal/formula (osobne .gity — bezbolesne).
3. **Reaktory**: pom shared (biblioteki+security), pom portalu (serwisy; zależności
   z ~/.m2), formula bez reaktora (jak dziś, standalone verify).
4. **Compose**: stack tożsamości definiowany RAZ w shared (`include:` composa v2.20+
   w portal/formula) — koniec z jednym 25-kB composem na wszystko.
5. **CI**: trzy workflow'y (shared: build+install; portal: checkout shared+portal,
   build po instalacji shared; formula: jak dziś + checkout offline-jwt).
6. **Dokumentacja i ścieżki**: README per workspace, CLAUDE.md ×3 (agregatorowy
   dzielony), maven-cheatsheet zostaje w shared; pamięć sesji Claude przenieść pod
   nowy klucz ścieżki formula-simulatora.
7. **Regresja**: shared install → portal install → formula verify → smoke → CI ×3
   zielone. Rollback do etapu 1 włącznie: `mv` z powrotem + checkout.

Decyzje w trakcie (zapisać werdykty): dom `microservice-email` (serwis pocztowy —
używany przez tożsamość do maili weryfikacyjnych → kandydat do shared zamiast
portalu); domy stubów sms/push/image (portal?); los starego `docker-compose.dev.yml`.

## ~~OTWARTE~~ ODPUSZCZONE (2026-07-12/3) — wielki rename: taksonomia `lib-*`/`util-*`

**Werdykt końcowy właściciela:** „jest ryzyko, że zrobimy większy bałagan niż jest —
odpuśćmy". Z całego planu WYKONANO tylko etap 1 (`system`→`usecase` w libkach:
`email-security-usecase`, `password-security-usecase` + konsumenci w microservice-security).
Reszta (prefiksy katalogów/repo/artifactId, pakiety util) — świadomie zaniechana; taksonomia
lib/util zostaje jako mapa mentalna, nie jako nazwy. Plan poniżej zostaje na wypadek
powrotu tematu.

--- Plan historyczny (nie wykonywać bez nowego dekretu) ---

**Werdykt (uchylony):** prefiksy rodzin w PEŁNEJ głębokości — katalog + nazwa repo na GitHubie +
artifactId + finalnie pakiety. Reguła granicy: **util** = przeszedłby test „Maven Central
dla obcych" (generyczne, zero kontekstu projektu); **lib** = niesie decyzje domenowe.
`offline-jwt` = lib DECYZJĄ właściciela (koduje kontrakt tożsamości dwóch produktów,
mimo generycznego brzmienia). `test-starter` BEZ prefiksu (nazwa mówi wszystko).

| po staremu | po nowemu | uwagi |
|---|---|---|
| `email` | `lib-email` | znika kolizja z `microservice-email` |
| `password` | `lib-password` | |
| `voting` | `lib-voting` | |
| `offline-jwt` | `lib-offline-jwt` | konsument także formula-simulator (OSOBNY produkt!) |
| `config` | `util-config` | |
| `constraint` | `util-constraint` | UWAGA: na GitHubie żyje w repo **`libs`** — rename repo `libs`→`util-constraint` |
| `adjustable-clock` | `util-adjustable-clock` | |

Etapy (kolejność wg promienia rażenia; każdy etap = commity per repo, reactor zielony na końcu etapu):

1. **`system` → `usecase` TYLKO w lib-\*** (werdykt właściciela 2026-07-12/2:
   `security-system` w microservice-security ZOSTAJE) — niezależne od prefiksów,
   zrobić NAJPIERW:
   - `email`: `email-security-system` → `email-security-usecase` (tylko moduł/artifactId —
     pakiety nie mają segmentu `system`).
   - `password`: `password-security-system` → `password-security-usecase` (jw.).
   - Konsekwencja przyjęta świadomie: kolizja znaczeniowa `security-system` vs
     `system-test-starter` zostaje w microservice-security.
2. **`util-*`** (mniejszy promień): `config`, `constraint`, `adjustable-clock` —
   `gh repo rename` (redirecty zostają, ale poprawić `repository:` w CI), artifactId
   top-level poma; konsumenci pomów: `microservice-security` (wszystkie trzy),
   `infrastructure-micronaut-clock` (adjustable-clock); grep repo-wide przed zmianą
   (lekcja: implementatorów/konsumentów szukać w CAŁYM workspace).
3. **`lib-*`** (największy promień): `email`, `password`, `voting`, `offline-jwt` —
   konsumenci pomów: `microservice-security`, `microservice-memes` (voting+offline-jwt),
   `microservice-comments` (voting+offline-jwt), `microservice-paddock`,
   `microservice-user-collections`, **`formula-simulator`** (offline-jwt; osobny produkt —
   osobny commit). CI sub-repo z checkoutem lib-repos do poprawy (`repository:` + `path:`):
   security, memes, comments, paddock, user-collections.
4. **Workspace jednym zamachem** (tu dopiero `mv` katalogów lokalnych, żeby ścieżki
   zmieniły się razem z plikami, które na nie patrzą): pom agregatora (`<module>`),
   `.gitignore` (lista katalogów dzieci), `.github/workflows/ci.yml` (OBA joby:
   `repository:`+`path:`), `README.md` (tabela modułów), `CLAUDE.md`,
   `-pl offline-jwt` w `infra-up.sh`/`formula-up.sh`, `build_c4.py`/`build_glossary.py`/
   `aggregate_allure.py` (grep list modułów), `formula-simulator/CLAUDE.md`+workspace docs.
5. **Pakiety** (finał, per repo): `com.jrobertgardzinski.config` → `util.config`,
   `...clock` → `util.clock` — wyrównanie do już istniejącego `util.constraint`;
   pakiety lib-ów BEZ zmian (lib = kategoria domyślna: `email`, `password`, `voting`,
   `offlinejwt` zostają).
6. **Regresja pełna**: wyczyścić stare artefakty z `~/.m2/repository/com/jrobertgardzinski`
   (stary artifactId w cache potrafi maskować niedokończony rename!), potem
   `./mvnw clean install` + `./mvnw -f formula-simulator/pom.xml clean verify` +
   `infra-smoke.sh` + zielone CI KAŻDEGO ruszonego repo (REPO_PAT — sprawdzić ważność).

Decyzje do podjęcia w trakcie (zapisać werdykty tutaj):
- `infrastructure-micronaut-clock` — `util-`? (test „Maven Central" przechodzi) czy zostaje
  (nazwa już samoopisowa, prefiks wydłuża do granic czytelności)?
- artifactId dzieci — rekomendacja: BEZ prefiksu (`email-domain` zostaje `email-domain`;
  prefiks tylko na top-level pomie), do potwierdzenia przez właściciela;
- pakty — ścieżki używają nazw serwisów, nie libów; zweryfikować grep-em przed etapem 3.

Odłożona świadomie (nie „bałagan", tylko decyzja): dalsza rozbiórka korzenia workspace
(artefakty `brochure-*` won/do `docs/`, skrypty do `scripts/`) — osobne zadanie, czeka na „k".

## ~~OTWARTE~~ ZROBIONE (2026-07-11/2) — saga wyprowadzona do `microservice-offboarding` (opcja D usera)

Właściciel wybrał mocniejszą drogę niż A/B poniżej: **orkiestracja sagi wyprowadzona do NOWEGO
serwisu portalu `microservice-offboarding`** (Helidon SE, bliźniak collections; process manager).
Nowy przepływ: security ogłasza FAKT `ACCOUNT_DELETION_REQUESTED` (`security-events`, outbox,
polityka wizarda jako nieprzezroczysta mapa) → offboarding otwiera sagę (dedup po `id` faktu),
komenduje `PURGE_USER_CONTENT` (kształt BEZ ZMIAN — pakty uczestników przeszły bez modyfikacji
payloadów), zbiera potwierdzenia (WIERSZE, nie kolumny; uczestnicy = env
`OFFBOARDING_PARTICIPANTS`) i ogłasza JEDEN werdykt na `offboarding-events`:
`PORTAL_CONTENT_PURGED` / `PORTAL_PURGE_FAILED` (timeout 2 min). Security: V17 zrzuca kolumny
uczestników, `PurgeChoices` = generyczna mapa, listener werdyktów zamiast trzech topiców,
własna siatka bezpieczeństwa 5 min, tryb `account-deletion.await-portal-purge=false`
(czysta tożsamość = kasacja od razu — scenariusz „security+gra" działa). Kontrakty: 6 nowych
paktów (fakt: offboarding←security ×2; werdykty: security←offboarding ×2; komendy: 3 uczestników
→offboarding; potwierdzenia: offboarding←3), wszystkie zweryfikowane na realnym kodzie obu stron.
Testy: offboarding 34/34 (7 scenariuszy Gherkina, prawo ADR 0006, JDBC, pakty), security pełna
suita zielona. Compose: serwis+postgres+healthcheck+OTel+Prometheus (:8094). ZOSTAŁO przy
pierwszym pushu (USER): `gh repo create microservice-offboarding` + push (CI uczestników
i workspace już checkoutują to repo).

--- Oryginalna diagnoza i drogi A/B poniżej (historycznie) ---

## ~~OTWARTE~~ SKONSUMOWANE PRZEZ WYPROWADZKĘ SAGI (stwierdzone 2026-07-19) — saga usuwania konta vs reużywalność security (właściciel 2026-07-11)

WERYFIKACJA 2026-07-19: wszystkie trzy złamania reużywalności z diagnozy niżej ZNIKŁY
wraz z opcją D (saga → microservice-offboarding, wpis wyżej): (1) uczestnicy sagi są
KONFIGURACJĄ offboardingu (`BeginOffboarding(store, participants)`, pusta lista =
domknięcie od razu — dokładnie mechanizm z drogi A, tyle że we właściwym serwisie);
(2) `PurgeChoices` w security to generyczna mapa {oś→reguła}, zero portalowych nazw
w domenie tożsamości; (3) wdrożenie „security + sama gra" działa: flaga
`account-deletion.await-portal-purge=false` kasuje konto od razu, bez czekania na
nikogo. Javadoc orchestratora też wyrównany (mówi o JEDNYM wyniku portalu, nie
o trzech potwierdzeniach). Nic do zrobienia — wpis zostaje jako kronika diagnozy.

--- Oryginalny wpis poniżej (historycznie) ---


Pytanie właściciela: „czy to security kieruje sagą?! zależało mi na reużywalności".
DIAGNOZA (fakty z kodu i paktów): TAK — security ORKIESTRUJE (AccountDeletionOrchestrator:
outbox+lock+timeout 2m+kompensacja — mechanicznie wzorowo), ALE reużywalność złamana
w trzech miejscach: (1) PurgeConfirmationsListener ma NA SZTYWNO trzech uczestników
(topici memes/comments/usercollections-events; domyka po KOMPLECIE trzech potwierdzeń);
(2) DOMENA security zna osie treści portalu imiennie (`PurgeChoices.memesRule()/
commentsRule()` — cudza domena w VO tożsamości); (3) konsekwencja praktyczna:
wdrożenie „security + sama GRA F1" (kanoniczny scenariusz dwóch produktów!) NIE UMIE
usunąć konta — każda saga kończy się timeoutem i kompensacją, bo nikt nie wyśle
potwierdzeń. Drobiazg przy okazji: Javadoc orchestratora mówi „memes confirmation
drives completePurge", a listener czeka na trzech — do wyrównania przy naprawie.

DROGI (dekret właściciela):
- **A (rekomendowana): uczestnicy sagi = KONFIGURACJA** — `account-deletion.participants`
  jako framework-free rekord w security-config (konwencja projektu); listener/orchestrator
  czekają na ZADEKLAROWANYCH; pusta lista = domknięcie od razu (czysta tożsamość);
  `PurgeChoices` z nazwanych pól na generyczną mapę {participant→rule} (kontrakt komendy
  rozszerzyć ADDYTYWNIE — pakty konsumentów bez zmian, stare pola zostają aliasami).
  Zachowuje orkiestrację, domknięcie i pakty; przywraca pełną reużywalność.
- **B: choreografia** — security publikuje FAKT (AccountDeleted), nie zna nikogo;
  treściowi sprzątają eventualnie. Maksymalna czystość, ale znika twarde „posprzątano
  zanim konto znikło" i pożegnalny mail traci gwarancję. Nie polecam przy obecnych
  oczekiwaniach (raportowalność sprzątania).
Kaliber: osobna skupiona sesja w microservice-security (protokół+domena+testy+pakty).

## Rozstrzygnięte

- **Null safety w domenie** — DECYZJA: domena NIE broni się przed `null`, infra
  (warstwa application) pilnuje, żeby null nie dotarł do domeny. Czytelny kod
  kosztem wrażliwości domeny na null. Spisane jako
  [ADR 0001](docs/adr/0001-no-null-guards-in-value-objects.md) (2026-07-01).
  - Follow-up (drobny) — ZROBIONE (2026-07-01): audyt VO w `security-domain`.
    `IpAddress` już nie miał `requireNonNull`; usunięto guardy `null` z
    `AbstractToken` (blank check zostaje) i `AbstractTokenExpiration`. Reszta VO
    czysta. `security-{domain,config,system}` build zielony, 24 testy jedn. OK.
- **Ujednolicenie testów w Allure** — ZAMKNIĘTE jako przedawnione; format
  dopieszczony na tyle, na ile się dało (password policy jako wzorzec).
- **Topologia gita (C1)** — OSOBNE REPA PER LIB. Workspace `security` = tylko
  agregator (pom + skrypty, dzieci gitignorowane). Do rozważenia kiedyś: monorepo
  tylko dla common libs (test-starter, adjustable-clock itp.), nie dla całości.

## Rozstrzygnięte (cd.)

- **Ujednolicić autora commitów (C2)** — ZROBIONE (2026-07-01). Rewrite historii
  (`git filter-branch`, autor+committer → kanon `Robert Gardziński
  <jrobertgardzinski@gmail.com>`, w tym web-UI committer `GitHub`) + force-push
  we wszystkich 6 sub-repo. Zweryfikowane na remote: wszystkie **lokalne**
  gałęzie kanoniczne i w sync (main + feature/mfa wszędzie; ms-security też
  development/interactive-documentation/restructure/simplify-modules/smarter-factory).
  Global `git config user.*` OK. Zapas starych SHA w scratchpadzie sesji.
  - Follow-up (opcjonalny): gałęzie **tylko-remote** poza rewritem —
    `password:gemini-refactor`, `microservice-security:overnight/todo-cleanup`
    oraz omyłkowa gałąź `origin` na kilku remote (kandydat do skasowania).

## Przegląd „co wytknąłby Sam Newman" (2026-07-10) — wykonane + follow-upy

Przegląd architektury mikroserwisowej całego stacku (poza formula). Fundamenty ocenione
dobrze (outbox, saga z potwierdzeniami, DLQ+redrive, dedup, DB-per-service, timeouts,
degradacja, cid przez HTTP i Kafkę, 3 sygnały observability). Cztery luki strukturalne —
stan:

- ~~**Testy kontraktowe (CDC)**~~ — ZROBIONE (2026-07-10), [ADR 0003](docs/adr/0003-file-based-consumer-driven-contracts.md):
  Pact w trybie plikowym, bez brokera — workspace zastępuje brokera. Konsumenci deklarują
  TYLKO pola, które czytają (pakt commitowany w `pacts/` repo konsumenta), producent
  (security) weryfikuje pakty na REALNYM kodzie producenta (`SecurityEventPacts` +
  4 klasy `*PactProviderTest`; sibling nie istnieje → skip, nie fail). Pokryte:
  `mail-requests` (email ← security, 6 kształtów maili) i `content-commands`
  (memes/comments/user-collections ← security, komenda purge ± policy).
- ~~**Wersjonowanie eventów**~~ — ZROBIONE (2026-07-10), [ADR 0004](docs/adr/0004-event-envelope-versioning.md):
  każda koperta niesie `"version": 1`; w ramach wersji zmiany TYLKO addytywne, konsumenci
  to tolerant readers; zmiana łamiąca = bump + expand/contract. Producenci: outbox
  notifiers + orchestrator (security), potwierdzenia purge (memes/comments/collections).
- ~~**CI per repo (independent deployability)**~~ — ZROBIONE (2026-07-10): własne `ci.yml`
  dostały security (checkout+install libek w kolejności zależności, checkout konsumentów →
  weryfikacja paktów biegnie też u producenta), memes i comments (najpierw voting),
  user-collections (self-contained) oraz idp/sms/push/image (unittest). Wcześniej miały
  tylko email i paddock. UWAGA: workflowy wchodzą w życie po pushu sub-repo.
- ~~**Healthchecki w compose**~~ — ZROBIONE (2026-07-10): sondy TCP (bash `/dev/tcp` /
  python socket — obrazy temurin/python nie mają curla) na 10 serwisach + healthcheck
  Kafki jej własnym skryptem; zależni czekają na `service_healthy` zamiast ścigać się
  ze startem security/kafki/sms/push.
- Niespójność stylów integracji z email (outbox/Kafka vs sync fan-out paddocka) —
  UDOKUMENTOWANA jako decyzja z kryterium wejścia: [ADR 0005](docs/adr/0005-two-integration-styles-on-purpose.md).

Follow-upy (otwarte, ~malejąca wartość):

1. ~~**Pakty w drugą stronę (potwierdzenia sagi)**~~ — ZROBIONE (2026-07-10/2): security
   jako KONSUMENT deklaruje w 3 paktach co czyta z `USER_CONTENT_PURGED` (type+email;
   uczestnik = topic); providery weryfikują na realnym kodzie BEZ refaktoru — memes/comments
   przez capture z mocka KafkaTemplate, collections przez czysty `handle()`. Obie strony
   sagi przypięte kontraktem; CI uczestników przeszło na układ workspace'owy (checkout
   security po pakty).
2. ~~**Kontrakty HTTP**~~ — ZROBIONE (2026-07-10/3). Kluczowa obserwacja: po konwergencji
   do libki prawdziwym konsumentem JWKS jest `offline-jwt` — JEDEN pakt HTTP w repo libki
   (kty/crv/kid/x, dowiedziony realnym fetcherem + tokenem podpisanym stałym kluczem
   testowym), weryfikowany przez security na realnym kontrolerze. Kształt samego JWT
   pilnuje mocniejsza domykająca pętla `OfflineLibraryRoundTripTest` w security: REALNY
   token z /authenticate weryfikowany REALNĄ libką o realny JWKS. Introspekcja `/me`:
   pakt HTTP memes (email/roles/mfaCompliant na 200 + 401 dla obcego tokenu; osobny
   katalog `pacts-http/` — plik V3 nie miesza message i request/response), weryfikacja
   u producenta z provider state (register→verify→authenticate; placeholder bearer
   podmieniany na realny token w test template — idiom JUnit5, nie @TargetRequestFilter).
3. ~~**OfflineJwt jako wspólna libka?**~~ — DECYZJA USERA (2026-07-10): libka. ZROBIONE
   (2026-07-10/2): nowe repo `offline-jwt` (`OfflineJwtVerifier` + `VerifiedToken`,
   jedyna zależność: jackson-databind; scalona suita testów pięciu kopii). Kopii było
   PIĘĆ (memes też), nie cztery — i konwergencja złapała REALNY dryf: offline'owy gate
   memes zgubił MFA floor, który introspekcyjny gate egzekwuje (moderator bez MFA
   zachowywał MODERATOR offline). Naprawione przez przejście na libkę + test regresyjny.
   Serwisy trzymają swoje polityki (Caller.withMfaFloor zostaje lokalnie).
4. ~~**CORS collections (brak UI)**~~ — ZROBIONE (2026-07-10/3, zlecenie usera „prostacja
   UI w react native"): `collections-ui` w repo user-collections — komponenty React
   Native (react-native-web + Vite; web celowo, bo natywna apka RN nie podlega CORS),
   sign-in przez security, lista/zapis/usuwanie ulubionych. Własny origin :8093 (nginx
   w compose) ⇒ przeglądarka woła security i collections CROSS-origin: ręczny
   `CorsFilter` w Helidonie (allowlista z `COLLECTIONS_ALLOWED_ORIGINS`, preflight 204
   przed routingiem, obcy origin bez echa; 3 testy), origins 8093+5173 dorzucone do
   CORS security. Smoke sprawdza stronę + preflighty obu krawędzi.
5. ~~**Pełna integracja z galerią**~~ — ZROBIONE (2026-07-10/4, doprecyzowanie usera):
   gwiazdka na kafelkach galerii zapisuje/zdejmuje ulubione wprost z przeglądarki
   (cross-origin do collections), ściana „Favourites" hydratuje refy; ref przeżywa mema
   z założenia — kafelek „unavailable" (cache-busting URL miniatury). Degradacja cicha:
   collections leży → brak gwiazdek, ściana działa. 3 scenariusze Playwright w e2e galerii
   (harness dostał collections na :8192); przy okazji naprawiony fałszywy pozytyw seedów —
   memes DEDUPLIKUJE identyczne bajty, e2e uploaduje teraz unikalne PNG.

## Otwarte zadania (2026-07-06 — po domknięciu OAuth USERINFO + całego MFA A–G)

Kolejność ~malejącej wartości. Zamknięte 2026-07-06 (szczegóły: microservice-security/todo.md
+ git log): OAuth Facebook/GitHub/GitLab (`identity-source` ID_TOKEN/USERINFO, `GET
/oauth/providers` → dynamiczne przyciski, provider = `OauthProviderSettings` w warstwie config,
przepisy w docs/oauth-providers.md); recovery codes jako czynnik ALTERNATYWNY (V13, batch
pokazany raz, konsumpcja atomowa w `MfaChain.verify` — sign-in i step-up za darmo); faza G
(mfa.feature przez realny UI, 22/22 e2e; znalazła i naprawiła martwą gałąź MFA w signIn/
submitFactor — fetch `r.ok` true dla 202). **Temat MFA zamknięty w całości.**

0. **formula-simulator: wielki plan rozbudowy (ZMIANA PLANÓW 2026-07-07 — aktywny temat)** —
   plan spisany w `formula-simulator/docs/expansion-plan.md`: ery jako dane (EraPack w
   RegulationSet), fizyka jazdy per era i podzespół (silnik/turbolag+ERS, skrzynia, hamulce
   z temperaturą i fade, opony crossply/radial, aero mech+aero-split, elektronika TC/ABS/LC,
   masa/paliwo/tankowanie, bezpieczeństwo), katalog 6 er, fazy F0–F9, trzy tory pracy.
   Realizacja w sub-repo formula-simulator (jego todo.md wskazuje plan). user-collections
   (pkt 1) schodzi na drugi plan do odwołania.
1. ~~**microservice-user-collections**~~ — ZROBIONE I ZWERYFIKOWANE LIVE (2026-07-07): szósty smak
   **Helidon 4 SE na virtual threads**. 7 plasterków, commit na plaster: domena+use case'y
   (opaque `ItemRef`, idempotentne save/remove/list/purge, spec-first Gherkin), Postgres+Flyway/H2
   (jeden adapter, idempotent przez unique 23505), brama HTTP + offline-JWT (bliźniak
   comments/memes/formula) — **ten sam feature prowadzony przez DWA wejścia** (aplikacja + czarna
   skrzynka HTTP, jak security), konsument sagi (Kafka, cid w nagłówku), **trzeci uczestnik sagi
   w security** (V15 `collections_purged`, topic `usercollections-events`, listener), compose+
   własny Postgres+OTel+Prometheus, smoke rozszerzony. **`./infra-smoke.sh` PASS** — „collections
   cleared" w sadze usuwania konta (leaver zapisał ulubione → usunięcie → kolekcja pusta). 26
   testów w repo + 77 security zielone. ZOSTAŁO (opc.): CORS (brak UI), cid w logach Helidona
   (JUL/MDC), traceparent w outboxie żeby saga linkowała się w jeden trace (wspólne z pkt 5).
   --- Oryginalny opis granicy poniżej ---
   **microservice-user-collections (DECYZJA 2026-07-07: wydzielamy)** — generyczne kolekcje
   referencji użytkownika (ulubione memy, zapisane komentarze, kiedyś watch/paddock).
   Kształt granicy: element = opaque ref `(itemType, itemId)`; serwis NIE interpretuje
   treści (zero synchronicznych wołań przy zapisie), brak inwariantów dzielonych z domeną
   źródłową — to jest test wejścia dla każdego nowego typu. Hydracja szczegółów po stronie
   UI (skasowany item = „niedostępny"), sprzątanie przez event `UserDeleted` (outbox/Kafka),
   auth = offline JWT jak w memes/comments. NIE wchodzą: preferencje MFA (inwarianty
   security), motyw/język/zgody (nie są referencjami — ewentualny osobny profil kiedyś).
   Odrzucona alternatywa: favourites w memes + saved w comments (prostsza, transakcyjnie
   spójna, ale rozmywa konteksty treści i duplikuje wzorzec per serwis).
   **UWAGA — SAGA (obowiązkowe przy budowie):** user-collections to trzeci uczestnik sagi
   usuwania konta (dziś: memes + comments). `AccountDeletionOrchestrator` w security kończy
   usuwanie dopiero po potwierdzeniach WSZYSTKICH uczestników — trzeba dodać trzecie
   oczekiwane potwierdzenie (nowy topic `usercollections-events`, uczestnik w `SagaParticipants`
   / tabeli saga_participants). To jednak uczestnik PROSTY: kasuje wszystkie referencje usera
   wholesale (nie parsuje `PurgeRule` — refy są opaque, bez DELETE/ANONYMIZE/KEEP), więc NIE
   jest to „trzeci konsument PurgeRule" i nie wyzwala ekstrakcji wspólnej libki. Bez tej zmiany
   saga albo nigdy się nie domknie (czeka na uczestnika, który nie odpowiada), albo kolekcje
   usuniętego usera osierocą się.
2. **Observability (zlecone 2026-07-07: „Grafana itd.")** — ETAP 1 ZROBIONY tej samej
   sesji: `observability/` + kontenery prometheus/grafana/cadvisor/node-exporter w compose
   (Grafana :3000 anonimowo, provisioned datasource + dashboard „Stack — kontenery";
   Prometheus :9090; metryki wszystkich kontenerów bez zmiany linijki w serwisach), wpięte
   w infra-up/infra-smoke, zweryfikowane live (3 targety UP, 6+ kontenerów z metrykami).
   ETAP 2 W TOKU (2026-07-07 później): security (micrometer, `/prometheus`), race-sim
   (stdlib `/metrics`: requesty/aktywne jazdy/uptime), email (quarkus-micrometer,
   `/q/metrics`), memes i comments (actuator, `/actuator/prometheus`) — 8/8 targetów UP.
   Przy okazji: zastany bug memes z sesji MinIO (S3ObjectStore: dwa konstruktory bez
   @Autowired = śmierć na starcie przy blob-store=s3) naprawiony w sub-repo; race-sim
   Dockerfile nadgonił F0 (obraz bez eras/ padał) i wozi teraz viewer+bolid (drive-ui
   działa Z KONTENERA, ten sam URL). ETAP 2 DOMKNIĘTY (jeszcze później tej sesji):
   paddock (ręczny /metrics jako slice, licznik per route + JVM) i formula backend (JDK,
   ręczny /metrics) — **10/10 targetów UP**. ETAP 3 (traceability) ZROBIONY: correlation-id
   przez Kafkę end-to-end (patrz pkt 5). ETAP 4 (logi) ZROBIONY: Loki + Promtail w compose
   (Promtail zbiera stdout wszystkich 20 kontenerów przez Docker SD — zero zmian w serwisach),
   provisioned datasource Loki w Grafanie obok Prometheusa. Spłata cid: `{service=~".+"} |=
   "<cid>"` grepuje jedno żądanie po wszystkich serwisach naraz — zweryfikowane live (jeden cid
   → linie z security I email w jednym zapytaniu). ETAP 5 ZROBIONY (2026-07-07/3): dashboard „Serwisy — HTTP, JVM i logi”
   (zmienna per serwis: RPS/czasy/5xx/heap/wątki + panel logów Loki {service="$svc"} +
   rząd ręcznych eksporterów paddock/race-sim), agent OTel dopięty do OSTATNICH dwóch
   JVM-ów (email, formula — Tempo widzi spany, formula nawet JDBC), alerty Prometheusa
   (TargetDown/Http5xxBurst/HostMemoryHigh — widoczne w /alerts i Grafanie; Alertmanager
   = produkcja); OTel+Tempo (waterfall spanów, datasource Tempo + derived
   field z Loki po cid). CI ZROBIONE: workflow w workspace (`.github/workflows/ci.yml`)
   checkoutuje 13 sub-repo i buduje cały reaktor jednym `./mvnw clean install` (testy włącznie,
   Testcontainers gdy jest Docker) — zweryfikowane lokalnie: BUILD SUCCESS, 43 moduły, 0 porażek.
   email i paddock (samowystarczalne) mają też własne, szybkie CI. ZASTRZEŻENIE: sama komenda
   sprawdzona lokalnie, ale pierwszy run na Actions może wymagać PAT, jeśli któreś sub-repo jest
   prywatne (domyślny GITHUB_TOKEN czyta tylko publiczne repo tego samego właściciela); JDK 25
   temurin przez setup-java. ETAP 5 (traces) ZROBIONY: OTel Java agent (2.29.0 — 2.11.0 ładuje
   się na JDK 25 ale NIC nie instrumentuje) podpięty do 4 serwisów JVM przez JAVA_TOOL_OPTIONS +
   wolumen (bez rebuildu), eksport do Tempo, datasource Tempo w Grafanie (z jumpem do logów Loki).
   Zweryfikowane live: upload → trace `[memes, security]`, odczyt komentarzy → `[comments, memes,
   security]`. ~~LUKA: saga usuwania konta nie linkuje się w jeden trace~~ — ZAMKNIĘTE (2026-07-07):
   outbox niesie teraz też W3C `traceparent` (kolumna V16, przechwyt z aktywnego spanu przez OTel
   API, które agent mostkuje); pooler odtwarza ten span jako rodzica przed publikacją, więc agent
   wstrzykuje `traceparent` KONTYNUUJĄCY trace. Dowód live: usunięcie konta = JEDEN trace w Tempo
   przez security, memes, comments, user-collections i email. E2E W CI ZROBIONE (2026-07-07):
   drugi job `e2e` w workflow workspace — te same specyfikacje Gherkina przez prawdziwe Chromium
   (run-e2e.sh: jar w env test + Vite + cucumber-js/Playwright, passkeys na wirtualnym
   authenticatorze włącznie); buduje tylko domknięcie -am jara security, cache npm po lockfile,
   logi serwisu/UI jako artefakt przy porażce. Pierwszy run: ZIELONY (reactor+e2e success).
   KEYCLOAK (2026-07-07): walidator `aud` nauczony kształtu tablicowego (string == clientId LUB
   tablica zawierająca clientId z `azp` wskazującym nas — OIDC Core 3.1.3.7; obce azp odrzucane),
   2 testy wire; ZWERYFIKOWANE LIVE pełnym headless dance z realnym Keycloakiem 26 (authorize →
   formularz → code → wymiana PKCE → sesja → /me). Kontener Keycloaka NIE został w compose
   (decyzja usera: dowód skonsumowany, waga zbędna); przepis + gotchas (KC_HOSTNAME przypina iss;
   aud-array) w docs/oauth-providers.md. KOSMETYKA DOMKNIĘTA (2026-07-07): dashboardy per serwis
   + panel logów + alerty zrobione (sesja równoległa: „Serwisy — HTTP, JVM i logi",
   alert-rules.yml, [trace=] we wzorcach WSZYSTKICH serwisów); do tego „Stack — dostępność
   i zdrowie" (metryka `up` jednolicie dla 11 targetów + panel warn/error z Loki), **derived
   field Loki→Tempo** (klik w `trace=<id>` w logu otwiera waterfall — zweryfikowane live: id
   z linii security rozwiązuje się w Tempo) i user-collections w rzędzie ręcznych eksporterów.
   OBSERVABILITY: TEMAT ZAMKNIĘTY W CAŁOŚCI.
   JAKOŚĆ UI (2026-07-07/4, „porób testy e2e, potestuj UI, porefactoruj"): (1) refaktor
   security-ui pod zieloną siatką — 646-liniowy App.tsx rozcięty na ekrany prezentacyjne
   (AccountScreen/MfaScreen/EntryScreens + lib.ts), stan i zachowanie w App, testidy nietknięte;
   tsc czysty, 36/36 e2e przed I po. (2) memes-ui dostał PIERWSZĄ suitę przeglądarkową: 5
   scenariuszy cucumber-js+Playwright na realnym trio security(test env)+memes(H2)+comments(H2),
   porty omijają stack dockera; konta/seed przez API, UI klikany tylko w to, o czym scenariusz;
   po drodze aria-labels na strzałkach głosów (a11y), testid score, vite proxy z env, h2 w
   comments test→runtime (real jar wstaje bez bazy). (3) job e2e w CI prowadzi OBA UI (wspólny
   Chromium, cache po obu lockfile'ach) — run zielony: reactor+e2e success.
3. ~~**Odświeżanie linku federacyjnego przy change-email**~~ — ZROBIONE (2026-07-07), i głębiej niż
   sądziliśmy: „re-linkuje się przy następnym logowaniu" było ZŁUDZENIEM — provider zgłasza swój
   własny (stary) adres, więc auto-link nigdy nie znalazłby przeniesionego konta (a mógłby znaleźć
   obcego, kto zarejestruje zwolniony adres). `ConfirmEmailChange` PRZEPINA teraz linki
   (`relinkAll` — subject jest trwały, to ta sama osoba); reguła w spec odwrócona na „FEDERATED
   LINKS follow the account". PRZY OKAZJI załatana podatność tej samej klasy co czynniki/kody:
   `DeleteAccount` nie czyścił `federated_identities` (bez FK) — stały link pozwalałby staremu
   właścicielowi wejść Google'em na konto następcy adresu; teraz `unlinkAll` przed usunięciem
   usera. 180 testów + reactor CI zielone.
4. ~~**Strona konsumencka podłogi MFA**~~ — ZROBIONE (2026-07-07): niedopełniony uprzywilejowany
   jest u konsumentów obsługiwany jak zwykły USER (role MODERATOR/ADMIN zdjęte w bramie —
   `Caller.withMfaFloor`, bliźniaki memes/comments; jedno miejsce per serwis, każdy istniejący
   check ról egzekwuje podłogę bez zmian per-endpoint; fail-closed przy braku pola). Kluczowy
   brakujący klocek: token NIE niósł werdyktu — mint w security stempluje teraz claim
   `mfaCompliant` (wyliczony w chwili mintu, ten sam trade-off co reszta claimów), więc konsumenci
   offline (comments) widzą podłogę bez wołania `/me`; memes (introspekcja) czyta pole z `/me`.
   Test wire w security przybija claim=false dla świeżego tokenu niedopełnionego moderatora;
   testy bram po obu stronach. paddock POZA zakresem — jego ADMIN to rola członkostwa serwera
   gry (własna domena), nie rola security. 180+35+22 zielone, reactor CI zielony.
5. ~~**Trace correlation-id przez Kafkę**~~ — ZROBIONE I ZWERYFIKOWANE LIVE (2026-07-07):
   cid jedzie nagłówkiem Kafki `X-Correlation-Id` przez WSZYSTKIE granice frameworków.
   Producent (security, Micronaut): outbox trzyma cid w kolumnie (V14), poller wysyła go
   nagłówkiem. Konsumenci przywracają cid do MDC: memes/comments (Spring, `@Header`), security
   (`@MessageHeader`), email (Quarkus, `IncomingKafkaRecordMetadata` + `Message<String>` +
   ręczny ack; log `%X{cid}`). Potwierdzenia sagi niosą cid dalej (helper `KafkaTracing`,
   bliźniak w memes/comments). **Bug złapany live**: MDC nie przechodzi przez wątki Micronauta
   (filtr na event-loopie, outbox na wątku `@ExecuteOn`) — cid czytany teraz z atrybutu żądania
   (`ServerRequestContext`), który Micronaut propaguje. Dowód: rejestracja z `X-Correlation-Id`
   → ten sam cid w logu email; usunięcie konta → ten sam cid w memes+comments (saga a941e7a5).
   email dostał brakujący filtr/log (miał 0 cid). ZOSTAŁO (opc.): async SMTP w email biegnie na
   innych wątkach Mutiny — głębokie logi dispatchera wymagałyby smallrye-context-propagation.
6. ~~**Sprzątanie po delete-account**~~ — ZROBIONE (2026-07-07): `DeleteAccount` czyści teraz
   `enrolled_factors` i `recovery_codes` PRZED usunięciem usera (podejście hexagonalne przez porty,
   jak `revokeAllSessions`: `RecoveryCodeRepository` dostał `removeAll`, bliźniak istniejącego w
   repo czynników; JDBC reużywa sprawdzonego `deleteByUserEmail`). Test przybija kolejność:
   sesje → czynniki → kody → user na końcu. Sekrety (materiał TOTP/WebAuthn, hasze kodów) nie
   przeżywają już konta. 77 testów zielone.

### Plany na przyszłość (spisane)

- **Wdrożenie/orkiestracja** → [docs/deployment-plan.md](docs/deployment-plan.md):
  Compose dziś → VPS+Compose+Traefik na publikację → k3s przy piramidzie dywizji;
  Podman i pełny k8s odrzucone z uzasadnieniem (plusy/minusy + wyzwalacze przejść).
- **Go-live portalu pod kampanię IX–X 2026** → [docs/go-live-2026.md](docs/go-live-2026.md):
  ocena gotowości (funkcjonalnie TAK, brakuje `deploy/` z Etapu 1), checklist publikacji
  (SMTP = blocker #1, sekrety/URL-e, OAuth bez stub IdP, TLS, tylko portal), kosztorys
  (10–14 GB RAM; Hetzner CAX31 ~50–60 € / 3 mies. + warianty). **Target = praca zdalna
  ZA GRANICĄ (werdykt 2026-07-12)** → plan przestawiony: FAZA 0 = wdrożenie właściciela
  (docs/onboarding-guide.md), potem anglojęzyczna warstwa publiczna + wideo + `deploy/`
  jako artefakt + demo na żądanie (VPS godzinowy przed rozmową); stały 3-mies. hosting
  ZDEGRADOWANY do wariantu opcjonalnego (target lokalny / frajda).
- **Anglicyzacja docs/ — ZROBIONE (2026-07-12)**: przewodnik-juniora.md →
  `docs/onboarding-guide.md`, przewodnik.md → `docs/onboarding-guide-legacy.md`
  (archiwum), deployment-plan.md i go-live-2026.md przetłumaczone in place,
  `build_c4.py` generuje c4-architecture.md po angielsku (zregenerowane). ADR-y były
  angielskie od zawsze. Po polsku ZOSTAJĄ celowo: todo.md (backlog roboczy, nie
  wizytówka) i docs gry F1 (produkt prywatny).

### (USER, zewnętrzne)

- **Realny Google/GitHub/…**: client-id/secret z konsoli providera → podmiana env-ów w compose
  wg microservice-security/docs/oauth-providers.md. Dev/smoke jadą na stub IdP bez tego.
- **Kasacja gałęzi remote sprzed rewrite'u**: `password:gemini-refactor`,
  `microservice-security:overnight/todo-cleanup` (klasyfikator blokuje agenta).

## Plan — kolejność realizacji (ustalona 2026-07-05) — SKONSUMOWANY

Szczegóły każdego punktu: microservice-security/todo.md (wpisy OAuth/MFA/step-up).

1. (USER) kasacja gałęzi remote sprzed rewrite'u: `password:gemini-refactor`,
   `microservice-security:overnight/todo-cleanup` (klasyfikator blokuje agenta).
2. ~~infra-up.sh buduje też jary comments/paddock~~ — ZROBIONE (2026-07-05).
3. ~~Stub IdP jako mikroserwis~~ — ZROBIONE (2026-07-05): `microservice-idp` (:8091), HS256
   id_tokeny, kody jednorazowe+PKCE; repo na GitHubie (PRIVATE — decyzja usera), spushowane.
4. ~~Port/adapter OIDC~~ — ZROBIONE: `OidcClient` (JDK HttpClient), provider = @EachProperty.
5. ~~Tożsamości federacyjne~~ — ZROBIONE: V10, `FederatedSignIn`, konta bezhasłowe.
6. ~~Przepływ /oauth/*~~ — ZROBIONE: feature (5 scen.) + OauthFlowHttpTest + smoke PASS live.
7. ~~Łączenie kont a/b/c~~ — ZROBIONE (auto-link / przejęcie squattera / podpowiedź w mailu).
8. ~~UI galerii: przycisk Google~~ — ZROBIONE (token wraca fragmentem, błąd jako notice).
9. [MFA, PO ANALIZIE USERA] egzekutor łańcucha (hasło ALBO provider = ogniwo #1; sesja po
   ostatnim ogniwie).
10. Port kodów + adaptery email/SMS (hash, TTL, jednorazowość, SourceThrottle).
11. Enrollment per user + `PROVIDER_SATISFIES_CHAIN`.
12. (opc.) TOTP + recovery codes.
13. [STEP-UP] elewacja sesji (jednorazowa, TTL) + polityki per akcja NONE/SECOND_FACTORS/FULL_CHAIN.
14. Wpięcie: delete=FULL_CHAIN, change-password=SECOND_FACTORS, revoke-all=TBD; federacyjni
    prompt=login.
15. ~~Konsument offline JWT w memes/comments~~ — ZROBIONE (2026-07-05): brama `security.verify=offline` weryfikuje podpis EdDSA przez JWKS zamiast /me; comments biegnie offline w compose.
16. ~~Anty-enumeracja na /account/email~~ — ZROBIONE (2026-07-05): zajęty adres = 202 jak świeży, notka mailem.
17. ~~UI jako 3. wejście~~ — ZROBIONE (2026-07-05): security-ui (Angular) + cucumber-js/Playwright, 17 scenariuszy specs/ zielonych.
18. ~~(memes) flaga NSFW~~ — ZROBIONE (2026-07-05): FlagMeme (moderator-only) + ContentFlags, V3, blur w galerii.

## Kolejność większych tematów

- **Glosariusz UL (skeleton) PRZED dodawaniem use case'ów** — SKONSUMOWANE
  (2026-07-01/02): glosariusz stoi (`build_glossary.py` + `docs/glossary`,
  skanuje też warstwy BCE i memes), a nowe use case'y (verify-email, reset
  hasła, change password/email, delete account, list/revoke sessions) weszły
  już w gotowy pipeline. (Backlog use case'ów: microservice-security/todo.md.)

## W toku

- **microservice-paddock (socjale wokół gry)** — walking skeleton ZROBIONY (2026-07-04):
  vertical slices + Javalin (piąty smak) + PWA mobile-first; rejestr serwerów
  (PRIVATE/OPEN/CHAMPIONSHIP, członkostwa), „mój paddock" z żywym stanem instancji,
  wydarzenia z RSVP; tożsamość przez introspekcję w security; Postgres+Flyway (H2 bez
  DB_URL); wpięty w compose (:8086). Backlog w microservice-paddock/todo.md (wydarzenia
  wywiedzione ze stanu gry, feed aktywności z powtórkami, rejestr→provision, powiadomienia).

## Konfiguracja — drabinka i profile (werdykty właściciela, 2026-08-23)

**AKTUALIZACJA 2026-09-05 (Robert: „przegiąłem pałę z configiem"):** taksonomia klas z tej rundy
została odchudzona. `Rebuild/Restart/LiveConfigKey`, `*ConfigSource` i `ConfigRequirement`
skasowane; zostały porty `Restart/LiveConfigPort`, dekorator `CachingLiveConfigPort` i
`ConfigLadder` jako KONTRAKT (`ConfigLadder.of(key, gate, Rung.live(..), Rung.restart(..),
Rung.rebuild(default))` — dowolny dobór szczebli, zawsze zakończony Rebuild; wariant
„obowiązkowa" odpada). Prawa (zła property = odmowa startu, zły wiersz = warn + szczebel
niżej, kształt drabinki) żyją w `config` i mają od dziś CI (config, password). `password-ladder`
skasowany — live config to zamówienie produktu: `microservice-security/security-custom/
custom-min-password-length`; bramka admina to `security-roles`, klej HTTP `security-http`.
Poniższe werdykty o precedencji, meta-konfiguracji, profilach i bezpieczniku credentiali
pozostają w mocy.

**AKTUALIZACJA 2026-09-06 (Robert: „zaciągać cały config z bazy i nadpisywać wg drabinki"):**
poziom live to JEDEN snapshot tabeli `security_settings` co TTL (`SnapshotLiveConfigPort` w
`config`, zastąpił `CachingLiveConfigPort` per klucz; zapis odświeża snapshot własnej instancji,
nieczytelna baza trzyma ostatni snapshot; TTL Restart+Rebuild, compose 1 s). Tekst parsowany na
szczeblu (`Rung.live/restart(port, Parse::integer)`), odmowa raz w logu per wiersz. Każdy klucz ma
live/restart/rebuild → „zamówienia" na live nie istnieją: `security-custom`, `security-roles`,
`security-http` rozpuszczone w domain/config/system/application/infrastructure (reguła: 3–5 warstw),
`password-application` skasowany, klucze przy rekordach `password-config` (`MinLength.KEY`).
Odrzucone: rekord jako drabinka, `record MinLength(RungLadder<Integer>)`, TTL na poziomie Live.

**DOPISEK 2026-09-06 (wieczór, po „wysil się"):** kontrakt `ConfigValue<T>` w `config` (`key()`, `value()`,
`defaultValue()`, `holding(T)` = konstruktor jako bramka) + prawa w każdej bibliotece pilnujące statyków
`KEY`/`DEFAULT` (kompilator nie wymusi statyków; refleksja w produkcji ODRZUCONA). `Configuration(snapshot,
properties)` w `config` deklaruje drabinkę z samej wysyłanej reguły: `liveOver(MinLength.DEFAULT)` = trzy szczeble,
`ConfigLadder<MinLength>`; `boundOver(MaxFailures.DEFAULT)` = property nad domyślną, rozstrzygnięte na starcie,
zwraca rekord. Parser z typu wartości (`Parse.forType`: Integer/Boolean/String/enum). Agregaty security-config
rozbite na VO per klucz (brute-force 5, mfa 8), walidności tokenów pod kontraktem w domenie (domena zależy od
`config` tylko przez interfejs), step-up = katalog `StepUpAction` (enum z kluczem i domyślną per konstanta,
`StepUpFor` bez statyków, polityka kompletna z konstrukcji, nieznana akcja = 400 UNKNOWN_ACTION).


Zrobione tego dnia (config, password, microservice-security, microservice-email,
portal: memes/comments/offboarding/user-collections, compose oba, k8s/base):

- **Taksonomia nazw = koszt zmiany** (komplet 2): `RebuildConfigKey` / `RestartConfigKey` /
  `LiveConfigKey`, źródła `Rebuild/Restart/LiveConfigSource`, porty `Restart/LiveConfigPort`,
  dekorator `CachingLiveConfigPort`, fabryki drabinki `ConfigLadder.live/restart` (poziom =
  najwyższy dostępny szczebel). Port mówi semantykę (koszt zmiany), adapter technologię.
- **Prawo precedencji**: wygrywa źródło wiązane najpóźniej; rozstrzygnięcie jest funkcją
  odczytu, nie mutacją; kolejność szczebli NIEREPREZENTOWALNA w API; default obowiązkowy,
  walidowany zachłannie; bramka pomija nielegalny szczebel z logiem; app.props ≡ env vars
  (jeden szczebel Restart — mini-drabinką env>yml rządzi framework, nie my).
- **`ConfigRequirement`** (wariant B): klucz obowiązkowy TYLKO z restart-source, bez defaultu,
  zachłanny resolve w composition root; mandatory-z-bazy i mandatory-hardcoded celowo
  niereprezentowalne (bootstrap + nierestartowalna flota / stała). Hybryda „wymagane w props
  + żywe nadpisanie z DB" = requirement pod drabinką, gdy zajdzie potrzeba.
- **Meta-konfiguracja szczebel niżej** — NIEAKTUALNE od 2026-09-06: TTL snapshotu ustawień
  SKASOWANY (łamał zasadę Newmana — legitymizował zapis do tabeli obok API); snapshot brany przy
  starcie (`@Context`) i po każdym zapisie admina, nigdy z zegara.
- **Klucze po kropkach**: `security.password.policy.min.length` (preferencja właściciela).
- **Baza/profil ortogonalne do drabinki**: bazowy plik = inwarianty serwisu, profil = decyzje
  środowiska; test: „różnica między środowiskami to bug czy decyzja?".
- **Strażnik profilu (default-deny)**: odmowa startu bez dokładnie jednego z {dev,test,prod}
  na ścieżce PRODUKCYJNEJ (main / start kontenera); testy wchodzą inną ścieżką i przechodzą.
  Smaki: Micronaut security = statyczny guard w App.main (bean-graf umierał na wstrzykiwaniu
  ZANIM bean-strażnik przemówił — listener offboardingu aktywny poza test bez DataSource);
  Quarkus email = @Observes StartupEvent, tryb NORMAL wymaga jawnego QUARKUS_PROFILE (compose
  i k8s deklarują prod, który dotąd był domyślny po cichu); Spring memes/comments = listener
  dodany w main; Helidon offboarding/user-collections = COLLECTIONS_PROFILE / OFFBOARDING_PROFILE
  sprawdzane na czele main. Compose i k8s/base niosą profile jawnie.
- **Bezpiecznik credentiali** (security): pod zadeklarowanym prod `CredentialsFuse` (@Context,
  @Requires(env="prod")) żąda jawnego hasła datasource i odrzuca dev-defaulty {postgres, secret};
  nierozwiązywalny placeholder ${DB_PASSWORD} = „nieustawione" z komunikatem operatorskim.
  Reguła: default wolno dać, gdy nie jest sekretem I nie może po cichu zadziałać w złym środowisku.
- **Prawo prawdomówności portów** (`ConfigPortsTellTheTruthTest`, obok StoresWithADeadline…):
  implementacje RestartConfigPort nie widzą bazy, implementacje LiveConfigPort nie czytają
  Environment — skan źródeł, bo kompilator semantyki kosztu zmiany nie sprawdzi.
- **Vault/Config Server** (SMiA): to transport/właściciel szczebli, nie nowy szczebel — config
  server bez refresha = Restart scentralizowany, z busem = Live push, Vault = Requirement jako
  usługa + rotacja (strona trzecia przecina samoodniesienie credentiali).

OTWARTE po tej rundzie:
- ADR o taksonomii Rebuild/Restart/Live + strażnikach (spisać w konwencji repo — właściciel).
- Stuby Pythona (image-encoder, idp, sms, push) bez strażnika profilu — zdecydować, czy go chcą.
- InMemoryProcessedOutcomes nie istnieje: start security poza test bez DataSource umiera na
  wstrzykiwaniu (dziś maskowane przez guard w main) — rozważyć twina albo @Requires dla listenera.
- Rozszerzenia taksonomii na przyszłość (slajd, nie kod): zasięg per rola/tenant, kierunek
  nadpisania (tylko zaostrzanie), push zamiast TTL-pull.
