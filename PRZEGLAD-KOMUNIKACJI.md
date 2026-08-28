# Przegląd komunikacji UI ↔ backend i granic sieciowych portalu

- Data: 2026-08-15
- Zakres: `portal/` (memes-ui, collections-ui, ingress k3s, CORS, docker-compose)
  + `shared/microservice-security` w części dotyczącej ciasteczek i weryfikacji tokenu.
- Punkt wyjścia: pytanie „czy UI gada z jakimś service mesh — podobno Kubernetes
  dostarcza service mesh".
- Dokument siostrzany: `PRZEGLAD-DDD.md` (model dziedzinowy). Ten jest o granicach
  i ruchu sieciowym.

---

## 1. Sprostowanie: Kubernetes NIE dostarcza service mesha

To jest częste nieporozumienie i warto mieć je wyprostowane, bo na rozmowie
kwalifikacyjnej jest to pytanie-pułapka. Kubernetes daje cztery rzeczy, które z
daleka wyglądają jak mesh, i żadna z nich nim nie jest:

| Mechanizm k8s | Co naprawdę robi | Gdzie to widać u Ciebie |
|---|---|---|
| `Service` (ClusterIP) | Load balancing **L4** przez kube-proxy (iptables/IPVS). Round-robin po podach. Zero wiedzy o HTTP. | `SECURITY_URL: http://security:8080` |
| CoreDNS | Rozwiązuje nazwę serwisu na ClusterIP | `http://memes.portal.svc.cluster.local:8083` |
| `Ingress` | Samo **API**; ruch obsługuje dopiero kontroler | `k8s/base/ingress.yaml`, Traefik wbudowany w k3s |
| `NetworkPolicy` | Też samo API; egzekwuje je CNI | nie używane w tym projekcie |

**Service mesh** (Istio, Linkerd, Cilium Service Mesh) to **osobny dodatek**,
który się instaluje. Dokłada to, czego k8s nie ma: mTLS między serwisami,
retry/timeout/outlier detection na **L7**, traffic splitting pod canary i blue-green,
telemetrię per wywołanie. Robi to sidecarem obok każdego poda albo trybem
ambient/eBPF na węźle.

**Stan faktyczny w repo:** grep po `istio|linkerd|cilium|envoy|consul|sidecar|service-mesh`
w `portal/` i `shared/` daje **dwa trafienia, oba w plikach README i oba o czymś
innym**. Mesha nie ma i nic go nie udaje.

### 1a. Nawet gdyby mesh był, UI i tak by z nim nie rozmawiał

Mesh obsługuje ruch **east-west** — serwis do serwisu, wewnątrz klastra.
Przeglądarka jest **poza** klastrem i wchodzi ruchem **north-south**, czyli przez
ingress (albo przez Gateway API, jeśli mesh dostarcza własną bramę wejściową).

Czyli: odpowiedź na „czy UI gada z meshem" jest strukturalnie **nie**, niezależnie
od tego, czy mesh w klastrze istnieje. To ruch, którego mesh z definicji nie
dotyczy.

---

## 2. Jak to wygląda naprawdę

### 2a. Przeglądarka zna CZTERY backendy

```
                    ┌─────────────────────────────────────────┐
   przeglądarka ────┤ memes.portal.localhost:9080             │  bundle + API (same-origin)
        │           └─────────────────────────────────────────┘
        ├──── CORS ─► security.portal.localhost:9080            token, /me, cookie refresh
        ├──── CORS ─► comments.portal.localhost:9080            wątki pod memem
        └──── CORS ─► collections.portal.localhost:9080         ulubione
```

Ingress: **jeden `Ingress`, host per serwis**, na Traefiku wbudowanym w k3s
(`k8s/base/ingress.yaml`). Wewnątrz zostają image-encoder, Kafka, MinIO, Mailpit
i wszystkie Postgresy.

Adresy **nie są wpieczone w bundle** — i to jest dobra poprawka, dobrze opisana
w `api.ts`. Łańcuch wygląda tak:

```
window.__PORTAL_CONFIG__   ←  /ui-config.js  (UiConfigController, Cache-Control: no-store)
        ↓ gdy brak
import.meta.env.VITE_*     ←  podstawione przez Vite w czasie builda
        ↓ gdy brak
'http://localhost:8080'    ←  domyślka compose'a
```

Powód istnienia tego łańcucha jest zapisany w javadocu: bundle (a więc jar i
obraz kontenera) niósł w sobie **jeden** komplet adresów — compose'owych. Serwowany
z klastra kazał przeglądarce dzwonić na `localhost:8080`, czyli na laptop
dewelopera; galeria wstawała zdrowa, a nikt nie mógł się zalogować.

### 2b. Nie ma bramy ani BFF — kompozycję robi przeglądarka

To jest **główne ustalenie architektoniczne tego przeglądu**. Jedyną warstwą,
która wie, że portal składa się z czterech serwisów, jest kod JavaScriptu w
przeglądarce. Nie ma API gateway, nie ma backend-for-frontend, nie ma reverse
proxy zbierającego to pod jeden origin.

**Z jednym wyjątkiem, który sam sobie zaprzecza:** `collections-ui` **ma** nginxa
z `location /memes/ { proxy_pass ... }` (`nginx.conf.template:27-35`), który
proxuje galerię same-origin. Powód jest zapisany w `k8s/base/collections-ui.yaml`:
tylko dzięki temu widok ulubionych odróżnia „ten mem zniknął" od „galeria nie
odpowiedziała" — bo galeria nie wysyła nagłówków CORS. Czyli wzorzec bramy jest
w tym projekcie **już sprawdzony i uzasadniony**, tylko zastosowany raz, punktowo,
zamiast na wejściu.

### 2c. Ruch wewnątrz klastra (ten, którego dotyczyłby mesh)

| Z | Do | Czym | Adres |
|---|---|---|---|
| memes | security | HTTP `GET /me` na każdym zapisie | `http://security:8080` |
| memes | image-encoder | HTTP (WebP) | Service wewnętrzny |
| comments | memes | HTTP (`HttpMemeDirectory` — czy mem istnieje) | `http://memes:8083` |
| comments | security | HTTP, ale tylko po JWKS (weryfikacja offline) | `http://security:8080` |
| collections | security | HTTP, JWKS | `SECURITY_URL` |
| collections-ui (nginx) | memes | reverse proxy | `memes.portal.svc.cluster.local:8083` |
| wszyscy | Kafka | saga offboardingu, kaskada `MEME_DELETED` | `kafka:9092`, plaintext |
| security | idp | OAuth | `http://idp:8091` |

Wszystko to jedzie po **gołym HTTP przez ClusterIP**. Żadnego mTLS, żadnej
polityki na poziomie sieci.

---

## 3. Cena obecnego układu

### 3a. Cztery miejsca do ręcznej synchronizacji na każdy serwis

Dodanie serwisu, z którym rozmawia przeglądarka, wymaga zgodności czterech
niezależnych konfiguracji:

1. reguła w `k8s/base/ingress.yaml`,
2. allowlista CORS po stronie serwisu,
3. wpis w `/ui-config.js` (`UiConfigController`),
4. adres w bundlu (fallback `VITE_*`).

**I przejechałeś się na tym dwa razy — obie historie są zapisane w komentarzach
w repo, więc nie są hipotezą:**

- **`ingress.yaml:40-48`** — `COLLECTIONS_ALLOWED_ORIGINS` było **martwą
  konfiguracją**, dopóki nie powstała reguła `/collections` **przed** catch-allem.
  Każde wywołanie z przeglądarki lądowało na SPA fallbacku nginxa: 200 `text/html`
  na GET, 405 na PUT/DELETE, zero nagłówków CORS i **nic w logach user-collections**,
  bo żądanie tam nigdy nie dotarło.
- **`comments.yaml:58-65`** — bez `UI_ORIGIN` każde żądanie wątku odrzucane
  **przez przeglądarkę**. Pod dalej Ready, w logach cisza, strona po prostu nie
  pokazuje komentarzy.

To jest dokładnie ta klasa awarii, którą masz już opisaną przy CORS-ie po
migracji na Micronaut 5: **widoczna wyłącznie w konsoli przeglądarki, bo żądanie
nigdy nie wyszło.** Trzeci raz z rzędu ta sama figura — to już nie pech, to
własność architektury bez bramy.

### 3b. CORS w trzech idiomach, bez jednego miejsca do przeczytania

| Serwis | Framework | Gdzie polityka |
|---|---|---|
| user-collections | Helidon SE | ręcznie pisany `CorsFilter` + `CorsFilter.fromEnv(...)` |
| comments | Spring | `WebMvcConfigurer#corsForTheGalleryUi` w `CommentsConfig:149` |
| security | Micronaut | `application.yml`, `allow-credentials: true` |

Jedna polityka bezpieczeństwa, trzy implementacje, trzy formaty konfiguracji.
Nie da się odpowiedzieć na pytanie „kto może wołać co" inaczej niż czytając trzy
pliki w trzech językach konfiguracji. Brama zbiłaby to do zera — same-origin nie
potrzebuje CORS-u w ogóle.

### 3c. Ciasteczko: działa, ale na cienkiej nitce

Refresh token jedzie jako `HttpOnly; Secure; SameSite=Strict` z origin **security**
(`RefreshCookies.java:38`), a aplikacja stoi na origin **memes**. Działa to
dzisiaj, bo `SameSite` porównuje **site** (domenę rejestrowalną), nie **origin**:
`memes.portal.localhost` i `security.portal.localhost` mają wspólne
`portal.localhost`, więc są same-site mimo że są cross-origin. Analogicznie w
compose, gdzie różnią się tylko portem (a port dla same-site nie liczy się wcale).

**Czego to znaczy w praktyce:** ten układ przestanie działać w dniu, w którym
security trafi na inną domenę rejestrowalną (np. UI na `portal.example.com`,
a auth na `example-auth.net`). `Strict` po prostu przestanie wysyłać ciasteczko —
bez błędu, bez wpisu w logu, z odświeżeniem sesji kończącym się cichym 401.
Warto to mieć zapisane, zanim k3s przestanie być `*.localhost`.

---

## 4. Co mesh by przejął i gdzie te sprawy siedzą dziś

| Sprawa | Co daje mesh | Gdzie jest u Ciebie |
|---|---|---|
| mTLS serwis↔serwis | automatycznie, bez zmian w kodzie | brak — gołe HTTP, Kafka plaintext |
| Timeouty | polityka deklaratywna | ręcznie per klient: 2 s connect / 5 s read w `HttpSecurityAuthenticationGate` |
| Retry i budżet ponowień | polityka | `SagaRetryBudget`, `stopOnExhaustedRetry` — w kodzie aplikacji |
| Circuit breaking / outlier detection | tak | brak; zamiast tego fail-closed `catch (RestClientException) → Optional.empty()` |
| Telemetria per wywołanie | automatycznie z sidecara | `X-Correlation-Id` przenoszony ręcznie przez MDC, `CorrelationIdFilter`, `KafkaTracing`, agent OTEL |
| Traffic splitting (canary) | tak | brak — i nie jest potrzebne |

### 4a. Trzy pokolenia tego samego problemu (i gdzie w tym jest „Spring Microservices in Action")

Warto to mieć poukładane, bo książka, z której się uczyłeś, **nie uczy mesha** —
uczy podejścia bibliotecznego, które jest historycznym poprzednikiem mesha.

| | Gdzie żyje polityka | Reprezentant | Koszt |
|---|---|---|---|
| **Gen 1 — biblioteki w procesie** | w kodzie każdego serwisu | Spring Cloud / Netflix OSS: Eureka, Ribbon, Hystrix→Resilience4j, Zuul→Spring Cloud Gateway, Config Server, Sleuth+Zipkin | przywiązanie do języka i frameworka; każdy serwis implementuje to sam |
| **Gen 2 — sidecar mesh** | w sidecarze obok poda | Istio, Linkerd | control plane + kontener przy każdym podzie: pamięć, CPU, koordynacja upgrade'ów, trudniejszy debug |
| **Gen 3 — ambient / eBPF** | na węźle | Istio ambient, Cilium | powstało **dlatego**, że podatek sidecarowy okazał się realny |
| **Oś czwarta** | nigdzie — nie ma wywołania | offline JWT, zdarzenia, outbox | trzeba przeprojektować przepływ, nie tylko dołożyć warstwę |

Mesh **jest** zgodny ze sztuką. Ale „sztuka" w systemach rozproszonych jest
zawsze warunkowa: entuzjazm z lat 2019–2021 ostygł, Istio dorobiło tryb ambient
właśnie po to, by zdjąć koszt sidecara, a Linkerd świadomie został mały. Próg
opłacalności leży wyżej, niż wtedy sądzono — nie znaczy to, że mesh jest zły.

### 4b. Argument ZA meshem, którego nie wolno pominąć: ten majątek jest poliglotyczny

| Serwis | Framework |
|---|---|
| memes, comments | Spring Boot |
| user-collections, offboarding | Helidon SE |
| security | Micronaut |
| email | Quarkus |
| image | Python |

To jest **najmocniejszy** argument za meshem w tym projekcie, mocniejszy niż
liczba serwisów przemawiająca przeciw. Podejście Gen 1 (to z książki) wymagałoby
zaimplementowania tych samych spraw **cztery razy, w czterech idiomach** — i
dokładnie to widać: CORS w trzech implementacjach (§3b), timeouty ręcznie w
każdym kliencie, korelacja przenoszona z palca przez MDC. Spring Cloud działa w
Springu; na Helidonie i Quarkusie nie ma z niego nic (sprawdzone: **zero**
zależności `spring-cloud` w całym majątku).

Czyli wzorzec z książki jest tu **niestosowalny wprost**, a mesh rozwiązuje
właśnie ten problem. To trzeba uczciwie policzyć po stronie „za".

### Werdykt: dobrze, że mesha nie ma — ale nie z powodu liczby serwisów

Sam koszt operacyjny (control plane, sidecar przy każdym podzie, własny język
polityk, własne tryby awarii) to argument prawdziwy, ale słabszy niż
poliglotyzm z §4b, który ciągnie w drugą stronę. Właściwe uzasadnienie jest
inne i składa się z dwóch części:

**Po pierwsze — realizujesz trzecią drogę i ona tu działa.** Wspólne biblioteki w
kernelu (`offline-jwt`, `transactional-outbox`, `adjustable-clock`, `constraint`)
to filozofia Gen 1 przełożona na poliglotyzm **ograniczony do JVM**. Cztery
frameworki, jedna platforma: `offline-jwt` wpina się i w Spring Boota, i w
Helidona, i w Micronauta. To jest dokładnie ten sam zysk, po który idzie się do
mesha, uzyskany bez control plane'u. **Warunek brzegowy warto znać: ta droga
kończy się w dniu, w którym dojdzie serwis w Go albo w Node.** Wtedy mesh
zaczyna wygrywać, bo `microservice-image` w Pythonie już dziś jest poza zasięgiem
tych bibliotek.

**Po drugie — największy problem rozwiązałeś usunięciem wywołania, nie jego
opakowaniem.** Mesh z nieudanego `GET /me` robi nieudane `GET /me` z retry,
timeoutem i ładną metryką. Weryfikacja offline JWT sprawia, że tego wywołania
nie ma wcale. To jest mocniejsza odpowiedź i warto ją tak formułować.

**Kiedy mesh zacząłby mieć sens:** serwis poza JVM w ścieżce krytycznej,
kilkanaście+ serwisów, wymóg mTLS z audytu, canary releases, albo zespoły na tyle
rozdzielone, że polityki sieciowe muszą wyjść poza kod aplikacji. Dziś nie
zachodzi żaden — ale pierwszy z nich jest bliżej, niż wygląda.

### 4c. Czego książka uczy, a czego naprawdę brakuje: BRAMA

Jedyny element z „Spring Microservices in Action", którego brak w tym projekcie
faktycznie boli, to **API Gateway** (u Carnella: Zuul, w nowszym wydaniu Spring
Cloud Gateway). To jest K3 z §5.

Warto zauważyć, gdzie leży pomyłka w intuicji „potrzebuję mesha": **mesh stoi w
east-west, brama w north-south.** Problemy, które faktycznie masz — cztery originy,
CORS w trzech idiomach, czteromiejscowa synchronizacja adresów, krucha nitka
`SameSite` — są **w całości** north-south. Mesh nie tknąłby ani jednego z nich.
Brama kasuje wszystkie cztery.

---

## 5. Do poprawienia

### K1 — [NISKA, ale wizerunkowa] `README.md` memes nazywa image-encoder „sidecarem"

`microservice-memes/README.md:27` — „WebP is encoded by a sidecar service".
W nomenklaturze Kubernetesa **sidecar to kontener w tym samym podzie**, dzielący
sieć i cykl życia. Image-encoder ma własny Deployment i własny Service
(`k8s/base/image-encoder.yaml`), czyli jest zwykłym osobnym serwisem.

Na README, który pełni funkcję wizytówki, to jest dokładnie to słowo, w które
wejdzie rozmówca — i wejdzie słusznie. Wystarczy „a companion service" albo
„a separate encoder service".

### K2 — [ŚREDNIA] memes trzyma security na twardej, synchronicznej ścieżce zapisu

memes weryfikuje token **introspekcją** — `GET /me` do security przy **każdym
zapisie** (`HttpSecurityAuthenticationGate`, włączony domyślką
`matchIfMissing = true`). comments i collections robią to **offline** przez JWKS.

Rozjazd jest **świadomy i udokumentowany** (ADR 0005 „two integration styles on
purpose", komentarz w `docker-compose.yml:159-161`: „memes keeps introspection —
instant revocation awareness"), więc nie jest to defekt. Ale konsekwencja jest
realna i warto ją umieć nazwać: **security jest twardą zależnością runtime ścieżki
zapisu memów**. Padnie security — nie wgrasz mema (401, fail-closed), choć
komentarz dodasz.

Ciekawostka do wykorzystania: memes **ma już gotowy** `JwtSecurityAuthenticationGate`,
w dodatku z naprawionym MFA floor (kiedyś ta kopia go zgubiła). Przełączenie to
jedna zmienna środowiskowa `SECURITY_VERIFY=offline`. Czyli kompromis
„natychmiastowa świadomość unieważnienia ↔ niezależność od security" jest w tym
systemie **przełącznikiem**, nie przepisywaniem — i to jest dobra odpowiedź na
rozmowie.

### K3 — [ŚREDNIA] Rozważyć bramę / BFF na wejściu

Nie jako refaktor „bo ładniej", tylko dlatego, że skasowałaby naraz:
CORS w trzech idiomach (§3b), czteromiejscową synchronizację adresów (§3a),
kruchość SameSite (§3c) i konieczność, by przeglądarka znała topologię backendu.
Wzorzec jest już w projekcie sprawdzony — nginx przed `collections-ui` robi
dokładnie to dla jednej ścieżki (§2b).

Koszt: jeden dodatkowy komponent na ścieżce żądania i decyzja, czy brama to sam
routing (Traefik z regułami per ścieżka, jeden host) czy prawdziwy BFF
(agregacja odpowiedzi). Wariant tańszy — **jeden host, routing po ścieżkach na
istniejącym Traefiku** — załatwia trzy z czterech problemów bez pisania nowego
serwisu.

---

## 6. Pytania, które z tego padną na rozmowie

Warto mieć przygotowane, bo materiał jest mocny:

1. *„Kubernetes daje service mesh, prawda?"* — nie; daje L4 (`Service`/kube-proxy),
   DNS i **API** Ingressa. Mesh to dodatek (Istio/Linkerd/Cilium) dokładający L7,
   mTLS i telemetrię.
2. *„To jak UI gada z serwisami?"* — bezpośrednio z czterema originami, przez CORS,
   z adresami wstrzykiwanymi w runtime; kompozycję robi przeglądarka. Bramy nie ma
   i wiem, co bym za nią kupił.
3. *„Co jak padnie security?"* — comments i collections działają dalej (weryfikacja
   offline po JWKS), memes odmawia zapisów, fail-closed. To przełącznik, nie
   architektura.
4. *„Jak wykryjesz awarię CORS-u?"* — nijak z serwera; to jedyna klasa awarii, w
   której pod jest Ready, log pusty, a aplikacja nie działa. Stąd `CorsOriginsTest`
   i e2e w przeglądarce.
5. *„Czemu nie mesh?"* — pięć serwisów, koszt operacyjny większy od zysku, a
   problem odwołań rozwiązany mocniej: offline JWT usuwa wywołanie zamiast je
   opakowywać.
