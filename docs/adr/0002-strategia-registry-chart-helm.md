# ADR-002 — Strategia di gestione registry per i chart Helm di piattaforma

## Status

Accepted — ratificato in conversazione architetturale del 1 maggio 2026,
durante la pianificazione di esecuzione dello Step 3 della Fase 3 (deploy
di MongoDB come primo componente di piattaforma popolato).

## Context

L'ADR-001 D8 ha stabilito che i componenti di piattaforma (`platform/<componente>/`)
sono gestiti via Kustomize con Helm come generator (`helmCharts`). All'epoca
di stesura dell'ADR-001 (1 maggio 2026, prima parte della giornata), il
"chart Helm di riferimento" implicito per molti componenti era quello di
Bitnami (MongoDB, PostgreSQL, Keycloak, Redis e altri), per ragioni storiche:
i chart Bitnami sono stati per oltre un decennio lo standard de facto della
community Kubernetes per il deploy di applicazioni open source in ambito
enterprise.

Durante la fase di esecuzione dello Step 3, e' emersa una situazione che
richiede di precisare ed estendere D8 con una decisione trasversale dedicata.

### La deprecazione del catalogo Bitnami pubblico (2025-2026)

A partire dal 28 agosto 2025, e con effetto piu' incisivo dal 29 settembre 2025,
Broadcom (proprietario di Bitnami a seguito dell'acquisizione di VMware) ha
riorganizzato il catalogo pubblico Bitnami:

- Le immagini container versionate ospitate su `docker.io/bitnami/<app>` sono
  state spostate in un repository archiviato `docker.io/bitnamilegacy/`.
  Le immagini archiviate non ricevono piu' aggiornamenti ne' patch di
  sicurezza.
- I chart Helm OCI ospitati su `docker.io/bitnamicharts/` continuano a
  esistere ma non ricevono piu' aggiornamenti, e per default referenziano
  immagini su un registry che e' ora `bitnamilegacy`.
- Il prodotto commerciale "Bitnami Secure Images" e' il successore ufficiale,
  con costo di sottoscrizione enterprise (riferimenti pubblici parlano di
  cifre nell'ordine di decine di migliaia di dollari/anno) e quindi
  inaccessibile per un lab personale didattico.
- Sealed Secrets, charts-syncer e minideb sono esplicitamente esclusi dalla
  deprecazione: continuano a essere pubblicati su `docker.io/bitnami` come
  in passato. Questa eccezione spiega perche' lo Step 2 della Fase 3 (Sealed
  Secrets) non e' stato impattato.

### Implicazione concreta

Il pattern stabilito in ADR-001 D8 (`helmCharts` → chart Bitnami) puo'
ancora essere applicato tecnicamente, ma le immagini dei chart "vivi" tirano
silenziosamente da un registry archiviato. Senza una decisione esplicita,
costruiremmo il lab su una base che e' gia' formalmente deprecata in
partenza.

## Decision drivers

- **Valore didattico del lab**: chi clona il repo deve ottenere un ambiente
  funzionante, e deve capire le scelte fatte (incluso il "perche'" delle
  scelte legate alla deprecazione).
- **Costo zero**: il lab e' un progetto personale open-source. Soluzioni che
  richiedano sottoscrizioni commerciali sono fuori scope.
- **Semplicita' del pattern**: D8 prevede `helmCharts` di Kustomize. Soluzioni
  che richiedano cambi di paradigma (es. Operator pattern) introducono
  complessita' sproporzionata.
- **Orizzonte temporale realistico del lab**: 12-18 mesi di vita utile come
  riferimento attivo. Soluzioni "future-proof a 5 anni" sono sovradimensionate.
- **Onesta' nella documentazione**: meglio una scelta non ottimale ma
  documentata e con criteri di re-valutazione, che una scelta migliore ma
  taciuta nei dettagli.

## Considered options

Sono state valutate cinque alternative.

### Alternativa A — Chart Bitnami con override del registry su `bitnamilegacy`

Mantenere il chart Bitnami come previsto da ADR-001 D8, ma in `values-common.yaml`
sovrascrivere `image.registry` (e i registry delle eventuali immagini
collaterali del chart, es. exporter, init container) per puntare
esplicitamente a `docker.io/bitnamilegacy`.

**Pro**:
- Zero impatto sul pattern Kustomize+Helm gia' stabilito.
- I chart Bitnami restano tecnicamente eccellenti: anni di iterazioni
  community-tested, set ricco di parametri, documentazione abbondante.
- Pattern di override del registry gia' codificato in `values.yaml` di tutti
  i chart Bitnami: cambio di una riga.
- Funziona oggi, e ragionevolmente per i prossimi 12-18 mesi.

**Contro**:
- Stiamo costruendo su un registry esplicitamente etichettato come archive,
  senza garanzie di sopravvivenza di lungo periodo.
- L'idea di partire con qualcosa di "gia' legacy" e' esteticamente
  sgradevole, anche se pragmaticamente ragionevole.

### Alternativa B — Chart Chainguard `iamguarded` come drop-in replacement

Chainguard ha forkato i chart Bitnami principali (incluso MongoDB) e li
mantiene attivamente con immagini Chainguard hardened. Sono dichiarati
drop-in replacement.

**Pro**:
- Pattern moderno, attivamente mantenuto.
- Eccellente postura di sicurezza (immagini minimal, ricostruite quotidianamente,
  attestazione di provenienza, zero-CVE).
- Drop-in compatibility con i values dei chart Bitnami.

**Contro decisivi**:
- I chart `iamguarded` sono distribuiti **esclusivamente** tramite il registry
  privato Chainguard (`cgr.dev/$ORGANIZATION/iamguarded-charts/<chart>`) e
  richiedono autenticazione con un'organizzazione Chainguard a pagamento.
- Il free tier "Starter" di Chainguard offre solo cinque immagini gratuite
  scelte dall'utente, senza accesso ai chart `iamguarded`.
- Per un lab open-source che vuole essere clonabile da chiunque senza
  iscrizione commerciale, e' tecnicamente impraticabile.

L'alternativa e' stata inizialmente proposta come raccomandazione in
conversazione architetturale, e successivamente ritirata dopo verifica del
modello commerciale di Chainguard. L'episodio e' stato riportato onestamente
nelle note di metodo del progetto.

### Alternativa C — MongoDB Community Operator

Per MongoDB esiste un Operator ufficiale (`mongodb/mongodb-kubernetes-operator`)
che gestisce un Custom Resource `MongoDBCommunity`. Nessuna dipendenza da
Bitnami.

**Pro**:
- Indipendenza totale da vendor Bitnami/Broadcom.
- Pattern Operator e' canonico per database in Kubernetes moderno.
- Manutenzione attiva da parte di MongoDB Inc.

**Contro**:
- Significativamente piu' complesso del pattern chart-based: richiede di
  capire e introdurre il pattern Operator nel lab.
- Sproporzionato per un lab single-instance: l'Operator e' progettato per
  scenari multi-replica complessi.
- Sposta il focus didattico dal pattern GitOps al pattern Operator, che non
  e' l'oggetto principale del lab.
- Richiede di rifare la stessa scelta per gli altri componenti (Keycloak,
  Apisix), ognuno con il proprio Operator (o equivalente), moltiplicando la
  complessita'.

### Alternativa D — Chart community indipendenti

Esistono chart community per MongoDB (es. `groundhog2k/mongodb`), single-purpose
e mantenuti da volontari.

**Pro**:
- Zero dipendenze commerciali.
- Semplicita': fanno una cosa, la fanno bene.

**Contro decisivi**:
- Maintainability di lungo periodo non garantita: progetti volontari possono
  perdere manutenzione senza preavviso.
- Quality control variabile: nessun processo di test/CI come Bitnami o
  Chainguard.
- Frammentazione: ogni componente avrebbe un chart di un autore diverso,
  con convenzioni e values schema differenti.

### Alternativa E — Manifest puri Kustomize

Scrivere a mano `Deployment`, `Service`, `StatefulSet` MongoDB senza usare
chart Helm. Per un single-node dev MongoDB e' fattibile in ~50 righe di YAML.

**Pro**:
- Zero dipendenze esterne.
- Controllo totale, leggibilita' totale.
- Didatticamente educativo.

**Contro**:
- Rompe il pattern stabilito in ADR-001 D8 (Kustomize con Helm generator).
- Non scala: fattibile per un MongoDB minimale, sproporzionato per Keycloak
  o Apisix che hanno chart upstream con decine di risorse.
- Crea inconsistenza tra componenti: alcuni con chart Helm, altri con
  manifest puri. Difficile da spiegare a chi legge il repo.
- Non sfrutta il lavoro della community sui chart upstream.

## Decision

**Alternativa A — Chart Bitnami con override del registry su `bitnamilegacy`**.

In ogni `platform/<componente>/base/values-common.yaml` di componenti che
provengono dall'ecosistema Bitnami, va impostato il registry override a
`docker.io/bitnamilegacy`. Esempio per MongoDB:

```yaml
image:
  registry: docker.io/bitnamilegacy
  repository: mongodb
  # tag: gestito dal chart, allineato all'appVersion di chart Bitnami
```

Per chart con immagini collaterali (es. exporter, volume permissions, init
container), va sovrascritto il registry di ognuna. Il chart Bitnami documenta
questi punti di estensione nei propri `values.yaml`.

Questa decisione si applica a **tutti i componenti di piattaforma che
proverranno dall'ecosistema Bitnami**, non solo a MongoDB. Nello specifico,
e' atteso che si applichi a Keycloak (Step 4 di Fase 3) se andra' avanti
con il chart Bitnami `keycloak`. Apisix (Step 5) e' su un altro ecosistema
(progetto Apache con chart proprio) e non e' impattato. Sealed Secrets
(gia' deployato in Step 2) e' nell'eccezione esplicita di Bitnami e non
richiede override.

## Consequences

### Positive

- Il pattern Kustomize+Helm di ADR-001 D8 resta integro.
- Il setup funziona out-of-the-box per chiunque cloni il repo, senza
  iscrizioni commerciali.
- L'episodio della deprecazione Bitnami diventa esso stesso materiale
  didattico: il repo mostra come si gestisce in pratica un cambio
  di registry in un progetto cloud-native.

### Negative

- Le immagini deployate sono tecnicamente "archiviate": non riceveranno
  patch di sicurezza pubblicate dopo il 29 settembre 2025. Per un lab
  didattico questo e' accettabile; per un eventuale uso production-like
  sarebbe inaccettabile.
- Esiste un rischio di "sparizione" del registry `bitnamilegacy` con
  preavviso non garantito. Broadcom non ha pubblicato impegni espliciti
  sulla sua sopravvivenza di lungo periodo.
- Il lab eredita una "bomba a orologeria" silenziosa: un giorno futuro
  imprecisato, le sync di Argo CD potrebbero iniziare a fallire con
  `ImagePullBackOff` se il registry sparisce.

### Neutral

- L'override del registry e' una modifica di una/tre righe per componente:
  costo di rifattorizzazione futuro contenuto.
- Il pattern di override e' lo stesso che si userebbe per qualunque mirror
  privato (es. un Harbor in air-gap come quello DCPP), quindi e' un
  esercizio coerente con scenari enterprise.

## Mitigations and re-evaluation

Per mitigare i rischi, si adottano le seguenti misure:

1. **Pinning esplicito di versione del chart**: ogni `helmCharts` referenzia
   una versione specifica (es. `version: 18.6.31`), mai `latest`. Questo
   evita aggiornamenti automatici in scenari di sync ripetuti.

2. **Voce trasversale nel BACKLOG**: e' aggiunta una voce di "monitoraggio
   sopravvivenza `bitnamilegacy`". L'utente e' invitato a verificare ogni
   3-6 mesi se il registry e' ancora disponibile e se Broadcom ha
   annunciato date di smantellamento.

3. **Criterio di re-valutazione**: questa decisione viene riconsiderata se
   si verifica almeno una delle seguenti condizioni:
   - Broadcom annuncia una data di smantellamento di `bitnamilegacy`.
   - Una alternativa praticabile (es. un fork community attivo dei chart
     Bitnami con immagini gratuite) emerge come standard di fatto.
   - Il lab evolve verso uno scope production-like che non tolera immagini
     senza patch di sicurezza.
   In tal caso, si scrivera' un ADR successivo (ADR-00X) che superseda
   questo, documentando la nuova rotta.

## Riferimenti

- Annuncio ufficiale Broadcom della deprecazione Bitnami:
  https://github.com/bitnami/charts/issues/35164
- Eccezione esplicita per Sealed Secrets, charts-syncer, minideb:
  https://github.com/bitnami/containers/issues/83267
- Documentazione del repository Bitnami Legacy:
  https://hub.docker.com/u/bitnamilegacy
- ADR-001 D8 (decisione originale su Kustomize + Helm generator):
  [`0001-strategia-gitops.md`](0001-strategia-gitops.md)

## Storia

| Data | Stato | Note |
|---|---|---|
| 2026-05-01 | Accepted | Stesura iniziale, ratifica della scelta tra cinque alternative durante la sessione architetturale di Step 3 |
