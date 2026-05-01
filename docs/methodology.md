# Metodologia di lavoro: Architect + Engineer + Decisore

Questo documento descrive il pattern operativo adottato nello sviluppo
di `localcloudnative-lab`. Non e' una metodologia formale ne' una
"best practice" universale: e' un modo di lavorare con strumenti di AI
generativa che si e' rivelato efficace su questo progetto specifico, e
che vale la pena documentare per chi volesse provare un approccio simile.

Il documento e' diviso in due parti:

1. **Il pattern in astratto**, applicabile ad altri progetti.
2. **Come abbiamo applicato il pattern in questo progetto**, con esempi
   concreti tratti dalla cronologia di sviluppo.

---

## Parte 1 — Il pattern in astratto

### Tre ruoli, una persona, due strumenti

Il pattern distingue tre ruoli funzionali distinti:

- **Architect**: ragiona ad alto livello su decisioni che hanno
  conseguenze di lungo periodo. Bilancia trade-off, contesta scelte
  affrettate, propone alternative, scrive documentazione architetturale.
  Non scrive codice, non lancia comandi.
- **Engineer**: esegue. Scrive file di configurazione, esegue comandi
  shell, debug iterativo, refactoring meccanici, gestione del repo.
  Conosce gli strumenti a fondo, ma non prende decisioni di design.
- **Decisore**: l'unico che decide. Riceve input dall'Architect,
  delega esecuzione all'Engineer, controlla che il lavoro fatto
  corrisponda all'intenzione.

Una sola persona umana copre il ruolo di Decisore. I ruoli di Architect
ed Engineer sono delegati a due strumenti AI distinti, configurati per
ottimizzare lo specifico ruolo:

- **Architect → modello "alto" in interfaccia conversazionale** (nel
  nostro caso, Claude Opus in chat su [claude.ai](http://claude.ai)).
- **Engineer → modello "operativo" in interfaccia agentica con accesso
  al filesystem** (nel nostro caso, Claude Sonnet in Claude Code).

La separazione strumentale non e' un dettaglio: e' la chiave del pattern.
Un solo strumento che fa entrambe le cose tende a "scivolare" tra i due
ruoli in modo non controllato.

### Le tre regole operative

Il pattern funziona se vengono rispettate tre regole minime:

#### Regola 1 — Il Decisore e' l'unico che decide

Architect ed Engineer sono advisor ed executor. Possono proporre
soluzioni, sollevare obiezioni, segnalare rischi. Non possono decidere
in autonomia su questioni che hanno conseguenze architetturali.

Quando Architect ed Engineer divergono sulla soluzione, **il Decisore
sceglie e si assume la responsabilita' della scelta**. Non e' un atto
formale: e' la pratica concreta di leggere entrambe le posizioni,
ragionare, e dichiarare la decisione esplicitamente prima che venga
eseguita.

#### Regola 2 — I prompt all'Engineer sono blindati per scope

L'Engineer in modalita' agentica ha la tendenza naturale a "chiudere il
loop": se intravede una continuazione ovvia del lavoro, la esegue
spontaneamente. Questo e' utile per task semplici e disastroso per
refactoring strutturali dove ogni decisione "implicita" e' una decisione
non ratificata.

Per questo, i prompt destinati all'Engineer per task non triviali devono
essere **blindati**:

- Lista numerata di passaggi da eseguire.
- Divieti espliciti ("NON fare X, NON modificare Y").
- Verifica obbligatoria post-esecuzione, con criterio di stop in caso
  di scostamento dall'atteso.

Esempio di prompt blindato:

> Decisione architetturale presa qui: rinomineremo `apps/` in
> `gitops/applications/`. Esegui questi passaggi in **un solo commit
> atomico**:
>
> 1. `git mv apps/ gitops/applications/`
> 2. In `root-app.yaml`: aggiorna `spec.source.path` da `apps` a
>    `gitops/applications`.
> 3. Aggiorna ogni occorrenza testuale di `apps/` nel README.
> 4. Commit message: `refactor: apps/ -> gitops/applications/`.
>
> NON toccare nient'altro. NON aggiungere o modificare Application.
>
> Dopo il commit:
>
> 5. Verifica esplicitamente che `kubectl -n argocd get applications`
>    mostri ancora 5 Application Synced.
> 6. Se qualcosa va storto, fermati e segnalalo. Non correggere
>    imperativamente.

L'inverso del prompt blindato — un prompt narrativo come "rinomina la
cartella e sistema il resto" — e' un invito all'Engineer a interpretare,
e quindi a sconfinare.

#### Regola 3 — La conversazione architetturale e' un investimento separato

Le decisioni di design valgono il loro tempo. Provare a prenderle
"durante" l'esecuzione, mescolate con i comandi shell e i diff di file,
porta quasi sempre a scelte affrettate o non documentate.

Il pattern raccomanda di **separare in modo netto** i momenti di design
dai momenti di esecuzione:

- Le decisioni si discutono con l'Architect, in conversazione, fino a
  ratifica esplicita.
- Solo dopo la ratifica, il Decisore passa un prompt all'Engineer.
- L'Engineer esegue, riporta, eventualmente segnala anomalie.
- Se emergono nuove decisioni in fase di esecuzione, si torna
  all'Architect per discuterle, non si delega all'Engineer.

Il costo apparente di questo pattern e' il context-switching tra
strumenti. Il beneficio reale e' che ogni decisione architetturale e'
ratificata consapevolmente e documentabile.

### Quando il pattern non si applica

Non tutti i task richiedono questo livello di formalizzazione. Il
pattern e' giustificato quando:

- Le decisioni hanno conseguenze di lungo periodo (struttura cartelle,
  scelte di tecnologia, naming convention).
- Il progetto e' destinato a essere mantenuto, condiviso, pubblicato.
- Esistono trade-off non banali da bilanciare.

Per task tattici (fix di un bug, scrittura di un test, generazione di
boilerplate) basta interagire direttamente con l'Engineer.

### Il valore della documentazione asincrona

Una conseguenza pratica importante: tutto cio' che viene deciso con
l'Architect deve essere **scritto da qualche parte nel repo**. Tipicamente:

- Architectural Decision Records (ADR) per le decisioni di design.
- README e runbook per le procedure operative.
- Questo tipo di documento meta per il processo di lavoro.

L'Architect non ha memoria persistente tra sessioni: ogni nuova
conversazione parte da zero. La documentazione nel repo e' la **memoria
condivisa di lungo periodo** del progetto. E' anche cio' che permette a
un terzo lettore — o a te stesso fra sei mesi — di capire perche' il
codice e' fatto cosi' senza dover ricostruire da capo il ragionamento.

---

## Parte 2 — Come abbiamo applicato il pattern in questo progetto

Questa sezione racconta episodi concreti di sviluppo di
`localcloudnative-lab`, con riferimenti puntuali a quando il pattern ha
funzionato bene, quando si e' rotto, e cosa abbiamo imparato.

### Genesi del progetto

Il progetto e' iniziato come idea informale: *"e' fattibile installare
un cloud-native stack su un Mac M4 per fare prototipazione end-to-end?"*
La conversazione iniziale con l'Architect ha:

- Confermato la fattibilita' tecnica.
- Identificato lo stack di riferimento (k3d invece di OpenShift Local,
  OrbStack invece di Docker Desktop).
- Scaffoldato la struttura iniziale del repo (Fase 1 — definizione
  cluster k3d).

A questo punto si e' presentata la prima decisione metodologica: continuare
in chat con l'Architect, oppure passare all'Engineer (Code) per
l'esecuzione concreta sul Mac. La scelta e' stata Code, ed e' stata
quella corretta: per un task che richiede decine di iterazioni
"modifica file → applica → osserva → correggi", l'Engineer agentico con
accesso al filesystem e' molto piu' efficiente del copia-incolla
manuale dalla chat.

### Il primo episodio in cui il pattern si e' rotto

Dopo Fase 1 e Fase 2 (bootstrap di Argo CD), il Decisore ha chiesto
all'Engineer di procedere "anche con il setup dei tre applicativi"
(Apisix, Keycloak, MongoDB), saltando la conversazione architetturale
con l'Architect che era stata pianificata.

L'Engineer ha eseguito correttamente ma ha preso autonomamente diverse
decisioni di design implicite:

- Pattern app-of-apps con `directory` recursive (vs ApplicationSet).
- Mono-repo con tutto in un solo posto.
- Una Application Argo CD per componente, namespace omonimo al
  componente.
- `targetRevision: HEAD` senza pinning.
- Argo CD self-managed.

Le scelte erano ragionevoli, ma erano scelte. Il Decisore se n'e'
accorto solo dopo, vedendo lo screenshot della UI di Argo CD con cinque
Application gia' create.

A questo punto ci sono state tre opzioni:

- **Strada A**: accettare il fatto compiuto, ratificare a posteriori.
- **Strada B**: rollback, fare la conversazione architetturale,
  ricostruire.
- **Strada C**: accettare la struttura attuale ma fare la
  conversazione architetturale **adesso**, prima di proseguire alla
  fase successiva.

Il Decisore ha scelto la Strada C, ed e' stata la scelta corretta:
costo basso (mezz'ora di chat), beneficio alto (otto decisioni
ratificate consapevolmente in un ADR-001 omnibus).

**Lezione appresa**: il pattern non si rompe gravemente se si recupera
in tempo. Il segnale d'allarme e' il momento in cui ti accorgi che
l'Engineer ha preso decisioni che non avevi ratificato. Quando questo
accade, fermarsi e ratificare a posteriori e' molto piu' economico che
proseguire e accumulare debito decisionale.

### Il secondo episodio: la patch che non funzionava

Durante il bootstrap di Argo CD, l'Engineer aveva pianificato di
applicare una patch al ConfigMap `argocd-cm` per disabilitare TLS in
modalita' insecure. Il Decisore ha verificato sul cluster e ha scoperto
che la patch non era effettivamente applicata: il ConfigMap era vuoto.

L'Architect, contattato per diagnosi, ha identificato due cause
possibili:

- La patch usava il selettore sbagliato (`argocd-cm` invece di
  `argocd-cmd-params-cm`, dove vive realmente `server.insecure`).
- Strategic merge patch su ConfigMap senza sezione `data:` puo' fallire
  silenziosamente.

A questo punto, invece di rincorrere il fix Kustomize, l'Architect ha
proposto di **rinunciare alla patch insecure** del tutto: in produzione
non sarebbe mai stata abilitata, e con port-forward in HTTPS standard
funzionava lo stesso.

**Lezione appresa**: l'Architect non e' solo per le decisioni "grandi".
A volte serve per ridimensionare un problema operativo che l'Engineer
sta affrontando ostinatamente. La domanda giusta non era "come faccio
funzionare la patch?", era "mi serve davvero la patch?".

### Il pattern dei prompt blindati

Dopo il primo episodio, il Decisore ha iniziato a strutturare i prompt
all'Engineer in modo molto piu' rigoroso. Esempio reale del prompt per
la rinomina di `apps/` in `gitops/applications/`:

- Lista numerata di sei passaggi precisi.
- Divieti espliciti ("NON modificare nient'altro, NON aggiungere o
  modificare Application").
- Verifica obbligatoria con criterio di stop ("se qualcosa va storto in
  verifica, fermati e segnalalo").

Dal momento in cui questo pattern e' stato adottato in modo
sistematico, **non c'e' stato piu' un solo episodio di sconfinamento**.
L'Engineer ha eseguito esattamente quello che era richiesto, ne' piu'
ne' meno.

Si potrebbe pensare che questo limiti la creativita' dell'Engineer.
In realta' lo libera: l'Engineer puo' concentrare la sua attenzione
sull'esecuzione corretta, senza dover anche "indovinare" lo scope. Per
task creativi (es. proporre una soluzione a un problema aperto), il
prompt blindato non si applica e l'Engineer torna a essere libero.

### La sessione architetturale

A meta' Fase 2, il Decisore ha investito una sessione strutturata con
l'Architect per ratificare otto decisioni di strategia GitOps. Il
formato della sessione:

1. L'Architect presenta una decisione alla volta, con trade-off espliciti
   (tabella comparativa quando utile), alternative considerate, e una
   raccomandazione motivata.
2. Il Decisore risponde con una scelta esplicita ("si", "no", "voglio
   approfondire").
3. Si passa alla decisione successiva.

Otto decisioni in circa quaranta minuti di conversazione. Le decisioni
sono state poi formalizzate in un singolo ADR omnibus (ADR-001), nel
formato MADR.

**Lezione appresa**: la conversazione architetturale strutturata e'
significativamente piu' veloce della conversazione "libera". Il Decisore
non deve rincorrere argomenti; ogni round e' un input mirato e una
risposta secca. Trade-off: richiede che l'Architect sia preparato a
strutturare il discorso, e che il Decisore sia disposto a rispondere
in tempo reale senza rimuginare per ore.

### Cosa succede in sessioni separate

L'Architect non ha memoria persistente tra sessioni di chat. Questo
limite e' diventato evidente in vari momenti del progetto: ogni nuova
conversazione richiede un breve "ripristino del contesto" tramite il
README, l'ADR, e i file recenti del repo.

Il pattern adottato per gestire questo:

- Il **README** e' la fonte di verita' principale per la struttura del
  progetto.
- Gli **ADR** sono la fonte di verita' per le decisioni architetturali
  pregresse.
- I **runbook in `docs/how-to/`** sono la fonte di verita' per le
  procedure operative (es. "come aggiungere un ambiente").

Quando una nuova sessione di chat parte, basta che il Decisore alleghi
il README e gli ADR rilevanti per avere l'Architect "sincronizzato".
La memoria di lungo periodo vive nel repo, non nello strumento.

L'Engineer (Code) ha invece accesso diretto al filesystem, quindi puo'
leggere il repo da solo. Il suo "contesto persistente" e' implicito.

---

## Conclusioni

Il pattern Architect + Engineer + Decisore non e' un'invenzione
originale: e' il modello operativo classico di un team software, dove
un Solutions Architect fornisce direzione, un developer esegue, e un
product owner / tech lead decide. La novita', se c'e', e' aver
formalizzato come questo modello si traduca quando i ruoli di
Architect ed Engineer sono coperti da strumenti AI.

Vale la pena ribadire che il pattern non e' "necessario": progetti piu'
piccoli, prototipi monouso, o task tattici si fanno benissimo
interagendo direttamente con un solo strumento. Il pattern paga in
contesti dove:

- Le decisioni hanno conseguenze di lungo periodo.
- Il progetto verra' condiviso con altri.
- La qualita' del processo decisionale e' parte del valore consegnato.

Per chi voglia replicare questo approccio su un proprio progetto, il
suggerimento e' di partire piccolo: applicare le tre regole operative
su una singola decisione architetturale, vedere come va, e progredire.
La formalizzazione del pattern che vedete qui e' il risultato di una
giornata di lavoro su un progetto concreto, non un manuale studiato a
priori.

---

## Riferimenti

- Architectural Decision Records di questo progetto: [`docs/adr/`](adr/)
- README principale del progetto: [`../README.md`](../README.md)
- Runbook operativi: [`how-to/`](how-to/)
- Su MADR (Markdown Architectural Decision Records): https://adr.github.io/madr/
