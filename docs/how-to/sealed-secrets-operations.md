# Sealed Secrets — Procedure operative

Runbook per le operazioni ricorrenti sul controller Sealed Secrets installato
in `platform-sealed-secrets`. Riferimento architetturale: ADR-001 D7.

## Prerequisiti

- Controller Sealed Secrets attivo nel cluster (verificare con
  `kubectl -n platform-sealed-secrets get pods` — atteso un pod
  `sealed-secrets-controller-*` in stato `Running`).
- CLI `kubeseal` installata sul Mac:
  ```bash
  brew install kubeseal
  ```
  Verifica: `kubeseal --version`.
- Ambiente kubectl puntato al cluster `k3d-lcn-lab`.

## 1. Cifrare un nuovo segreto

Pattern: si parte da un Secret Kubernetes "in chiaro" (mai committato), lo
si cifra con `kubeseal`, si committa il `SealedSecret` risultante.

```bash
# 1. Crea il Secret in chiaro localmente (NON applicarlo al cluster)
kubectl create secret generic mio-segreto \
  --from-literal=password='valore-segreto' \
  --namespace=platform-mio-componente \
  --dry-run=client -o yaml > /tmp/mio-segreto.yaml

# 2. Cifralo con kubeseal
kubeseal \
  --controller-namespace=platform-sealed-secrets \
  --controller-name=sealed-secrets-controller \
  --format=yaml \
  < /tmp/mio-segreto.yaml \
  > platform/mio-componente/base/mio-segreto-sealed.yaml

# 3. Cancella la versione in chiaro
rm /tmp/mio-segreto.yaml

# 4. Aggiungi mio-segreto-sealed.yaml a base/kustomization.yaml come resource
# 5. Commit + push: Argo CD applica il SealedSecret, il controller lo
#    decifra e crea il Secret reale.
```

Nota sul namespace: un SealedSecret cifrato per il namespace X non puo'
essere decifrato in un namespace Y (e' una protezione del controller). Il
namespace nel Secret originale deve corrispondere a quello dove verra'
applicato.

## 2. Estrarre la chiave master per backup

Da fare una volta sola, subito dopo l'installazione iniziale del
controller, e ogni volta che la chiave viene ruotata.

```bash
# Esporta tutti i Secret etichettati come chiavi attive del controller
kubectl -n platform-sealed-secrets get secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-master-key.yaml
```

Il file risultante contiene la chiave privata RSA in formato base64. Non
committarlo nel repo: e' la chiave che permette di decifrare tutti i
SealedSecret cifrati per questo cluster.

Procedura di archiviazione:

1. **Bitwarden (primary)**:
   - Crea un nuovo elemento di tipo "Secure Note" con titolo
     `lcn-lab — Sealed Secrets master key`.
   - Incolla il contenuto di `sealed-secrets-master-key.yaml` nel campo
     "Notes".
   - Aggiungi nei "Custom fields" la data di estrazione e l'identificativo
     del cluster (`k3d-lcn-lab`).

2. **Keychain Mac (ridondanza)**:
   - Apri "Accesso Portachiavi" / Keychain Access.
   - Crea un nuovo "Secure Note" con titolo
     `lcn-lab — Sealed Secrets master key (backup)`.
   - Incolla il contenuto del file.

3. Cancella il file da disco:
   ```bash
   shred -u sealed-secrets-master-key.yaml  # Linux
   rm -P sealed-secrets-master-key.yaml      # macOS (overwrite + remove)
   ```

## 3. Ripristinare la chiave master su un cluster nuovo

Scenario: il cluster `k3d-lcn-lab` e' stato distrutto e ricreato. Vogliamo
riusare i SealedSecret gia' committati nel repo.

1. Ricrea il cluster k3d e applica il bootstrap fino al punto in cui Argo CD
   e' funzionante (vedi [README.md](../../README.md) sezione Fase 1+2).

2. Prima di lasciare che Argo CD installi il controller Sealed Secrets,
   crea il namespace e applica la chiave master backuppata:
   ```bash
   kubectl create namespace platform-sealed-secrets
   kubectl apply -f /percorso/a/sealed-secrets-master-key.yaml \
     -n platform-sealed-secrets
   ```
   (Il file e' quello recuperato dal Bitwarden o Keychain.)

3. Lascia che Argo CD installi il controller normalmente (sync della
   Application `sealed-secrets`). Il controller, all'avvio, riconosce il
   Secret esistente come "chiave attiva" invece di generarne una nuova.

4. Verifica:
   ```bash
   kubectl -n platform-sealed-secrets logs deployment/sealed-secrets-controller
   ```
   — dovresti vedere log che indicano l'uso della chiave esistente, non
   la generazione di una nuova.

5. I SealedSecret esistenti nel repo sono ora decifrabili.

## 4. Ruotare la chiave master (on-demand)

Scenario: sospetta compromissione, oppure rotazione preventiva di sicurezza.

1. Forza la generazione di una nuova chiave nel controller:
   ```bash
   kubectl -n platform-sealed-secrets delete secret \
     -l sealedsecrets.bitnami.com/sealed-secrets-key=active
   kubectl -n platform-sealed-secrets rollout restart \
     deployment/sealed-secrets-controller
   ```
   Il controller, al riavvio, genera una nuova coppia di chiavi. La vecchia
   chiave non viene cancellata da Kubernetes: rimane come Secret etichettato
   "compromised" e continua a poter decifrare i SealedSecret cifrati prima
   della rotazione.

2. Estrai e backuppa la nuova chiave master (vedi sezione 2).

3. Ricifra i SealedSecret esistenti con la nuova chiave pubblica. Per
   ogni SealedSecret nel repo:
   ```bash
   kubeseal \
     --controller-namespace=platform-sealed-secrets \
     --controller-name=sealed-secrets-controller \
     --re-encrypt \
     --format=yaml \
     < vecchio-sealed.yaml > nuovo-sealed.yaml
   ```
   Sostituisci nel repo, committa.

4. Quando tutti i SealedSecret sono stati ri-cifrati, puoi cancellare la
   vecchia chiave dal cluster:
   ```bash
   kubectl -n platform-sealed-secrets delete secret \
     -l sealedsecrets.bitnami.com/sealed-secrets-key=compromised
   ```

## Troubleshooting

### `kubeseal` non trova il controller

Sintomo: `error: cannot fetch certificate: ...`

Causa probabile: la CLI usa il default `controller-namespace=kube-system`
invece del nostro `platform-sealed-secrets`. Soluzione: passa esplicitamente
le flag `--controller-namespace` e `--controller-name` come negli esempi.

Per non doverle scrivere ogni volta, aggiungi al tuo `~/.zshrc` o
`~/.bashrc`:
```bash
alias kubeseal-lcn='kubeseal --controller-namespace=platform-sealed-secrets --controller-name=sealed-secrets-controller'
```

### Un SealedSecret resta in stato "errore"

Sintomo: nel log del controller, messaggi tipo
`failed to unseal: no key could decrypt secret`.

Causa probabile: il SealedSecret e' stato cifrato per un cluster con una
chiave diversa (es. dopo una rotazione non ancora ricifrata, o dopo un
ripristino fallito della chiave). Soluzioni:

- Se hai backup della vecchia chiave, applicala (sezione 3).
- Altrimenti, ricifra il segreto da zero con la chiave attuale.

## 5. Generazione SealedSecret per MongoDB (Step 3b)

Procedura per generare e committare i SealedSecret necessari al primo
deploy di MongoDB con manifest puri (ADR-003). Da eseguire **una sola
volta** dopo che la struttura `platform/mongodb/` e' in stato
manifest-puri (Step 3 completato, Application ancora in attesa).

I manifest puri si aspettano:
- Secret `mongodb-root-credentials`: campi `password` e `replica-set-key`
- Secret `mongodb-app-credentials`: campo `password`

### Prerequisiti

- CLI `kubeseal` installata sul Mac (vedi sezione "Prerequisiti" del
  runbook).
- Cluster `k3d-lcn-lab` attivo, controller Sealed Secrets in stato
  Running in `platform-sealed-secrets`.
- Aver scelto due password robuste per `root` e `lcnapp`
  (suggerito: generatore del password manager, lunghezza 24+).

### Passo 1 — Genera il Secret per le credenziali root

```bash
# Sostituisci <ROOT_PASSWORD> con la password scelta per l'utente root.
kubectl create secret generic mongodb-root-credentials \
  --from-literal=password='<ROOT_PASSWORD>' \
  --from-literal=replica-set-key="$(openssl rand -base64 756 | tr -d '\n')" \
  --namespace=platform-mongodb \
  --dry-run=client -o yaml > /tmp/mongodb-root-credentials.yaml

kubeseal \
  --controller-namespace=platform-sealed-secrets \
  --controller-name=sealed-secrets-controller \
  --format=yaml \
  < /tmp/mongodb-root-credentials.yaml \
  > platform/mongodb/base/mongodb-root-credentials-sealed.yaml

rm /tmp/mongodb-root-credentials.yaml
```

`replica-set-key` e' la chiave condivisa usata dal replica set rs0 per
l'autenticazione interna tra nodi (--keyFile). Generata casualmente con
`openssl rand -base64 756` (lunghezza raccomandata da MongoDB Inc.).
Con un solo membro il keyFile non e' strettamente necessario per la
comunicazione inter-nodo, ma e' richiesto dall'opzione `--auth` +
`--replSet` in combinazione. Generata casualmente, mai riusata.

### Passo 2 — Genera il Secret per le credenziali applicative

```bash
# Sostituisci <APP_PASSWORD> con la password scelta per l'utente lcnapp.
kubectl create secret generic mongodb-app-credentials \
  --from-literal=password='<APP_PASSWORD>' \
  --namespace=platform-mongodb \
  --dry-run=client -o yaml > /tmp/mongodb-app-credentials.yaml

kubeseal \
  --controller-namespace=platform-sealed-secrets \
  --controller-name=sealed-secrets-controller \
  --format=yaml \
  < /tmp/mongodb-app-credentials.yaml \
  > platform/mongodb/base/mongodb-app-credentials-sealed.yaml

rm /tmp/mongodb-app-credentials.yaml
```

### Passo 3 — Commit e attesa sync

I file `mongodb-root-credentials-sealed.yaml` e
`mongodb-app-credentials-sealed.yaml` sono gia' elencati in
`platform/mongodb/base/kustomization.yaml`. Basta committarli:

```bash
git add platform/mongodb/base/mongodb-root-credentials-sealed.yaml \
        platform/mongodb/base/mongodb-app-credentials-sealed.yaml
git commit -m "feat(mongodb): add SealedSecret credenziali root e applicative"
git push
```

Argo CD rileva il nuovo commit (entro ~3 minuti, o forzando sync via
`make argocd-ui`). Il controller Sealed Secrets crea i Secret reali;
lo StatefulSet scala a 1 pod; il Job PostSync `mongodb-rs-initiate`
inizializza il replica set rs0 e crea l'utente `lcnapp` nel db `lcn`.

### Passo 4 — Verifica

Tempo atteso: 3-5 minuti dal sync (download immagine `mongo:8.0` la
prima volta + boot replica set + esecuzione Job).

```bash
# Pod in stato Running
kubectl -n platform-mongodb get pods
# atteso: mongodb-0 Running READY 1/1, job-pod Completed

# Stato replica set
kubectl -n platform-mongodb exec mongodb-0 -- \
  mongosh --quiet \
  --username root --password '<ROOT_PASSWORD>' \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.stateStr))"
# atteso: PRIMARY

# Utente applicativo raggiungibile
kubectl -n platform-mongodb exec mongodb-0 -- \
  mongosh "mongodb://lcnapp:<APP_PASSWORD>@localhost:27017/lcn?replicaSet=rs0" \
  --quiet --eval "db.runCommand({connectionStatus: 1}).authInfo.authenticatedUsers"
# atteso: [{ user: 'lcnapp', db: 'lcn' }]
```

Connessione applicativa per workload futuri:
```
mongodb://lcnapp:<APP_PASSWORD>@mongodb.platform-mongodb.svc.cluster.local:27017/lcn?replicaSet=rs0
```

### Troubleshooting

**Pod in `CreateContainerConfigError`**: mismatch sui campi del Secret.
Verifica che i SealedSecret siano stati cifrati con i campi `password`
e `replica-set-key` (non i vecchi `mongodb-root-password`,
`mongodb-replica-set-key`). In caso di dubbio, ricifra da zero.

**Job `mongodb-rs-initiate` in `Error` / `BackoffLimitExceeded`**: guarda
i log con `kubectl -n platform-mongodb logs job/mongodb-rs-initiate`.
Causali tipiche: pod mongodb-0 non ancora Ready al momento del Job
(il Job ha `backoffLimit: 6`, di solito si recupera da solo), oppure
password errata nel Secret (verifica con `kubectl get secret
mongodb-root-credentials -n platform-mongodb -o jsonpath='{.data.password}'
| base64 -d`).

**Replica set non si inizializza**: verifica che il keyFile sia stato
copiato correttamente nell'initContainer e che i permessi siano 400:
```bash
kubectl -n platform-mongodb exec mongodb-0 -- ls -la /data/keyfile
# atteso: -r-------- 1 mongodb mongodb ... /data/keyfile
```
