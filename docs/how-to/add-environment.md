# Come aggiungere un nuovo ambiente

Questo runbook spiega come attivare un secondo ambiente (es. `stage`, `experimental`) sfruttando la struttura Kustomize `base + overlays/<env>` gia' predisposta per i componenti di piattaforma.

## Quando farlo

Aggiungere un ambiente ha senso quando hai bisogno di:

- testare modifiche rischiose senza compromettere l'ambiente "stable" che usi per gli esperimenti correnti;
- sperimentare con varianti di un componente in parallelo (es. due versioni diverse di un modello AI/SLM, due dataset GIS diversi);
- simulare il pattern enterprise di "promotion via Git" (dev → stage → prod) per finalita' didattiche.

Se l'esigenza e' transitoria (un esperimento di poche ore), conviene quasi sempre usare l'ambiente esistente con un branch Git temporaneo invece di creare un overlay nuovo.

## Decisioni preliminari da prendere

Prima di aggiungere l'ambiente, decidi:

1. **Stesso cluster con namespace dedicati, o cluster k3d separato?**
   - Stesso cluster: piu' leggero (un solo nodo da reggere), ma componenti pesanti come Keycloak o un modello AI raddoppiano il consumo di risorse.
   - Cluster separato: piu' realistico (esercita anche multi-cluster Argo CD), ma triplica i requisiti di RAM.
2. **Quali componenti vanno duplicati?**
   Spesso non tutti. Esempio: Keycloak puo' restare unico (provider di identita' condiviso), MongoDB puo' restare unico, mentre il backend AI viene duplicato per testare modelli diversi. Decidi caso per caso.
3. **Strategia di pinning per il nuovo ambiente.**
   L'ambiente `dev` punta a `HEAD`. Il nuovo ambiente potrebbe puntare a un branch dedicato (es. `release/stage`), a un tag (es. `v1.0.0`), o restare anch'esso su `HEAD` se vuoi solo isolamento di runtime.

## Procedura: stesso cluster, namespace dedicati

Esempio: aggiungere un ambiente `stage` per Keycloak.

1. Crea l'overlay:
   ```
   platform/keycloak/overlays/stage/
   ├── kustomization.yaml
   └── values-stage.yaml    # se usi helmCharts
   ```
   Il `kustomization.yaml` parte da una copia di `overlays/dev/` e modifica il `namespace` (es. `platform-keycloak-stage`).

2. Crea una nuova Application Argo CD `gitops/applications/keycloak-stage-app.yaml` ricalcata su `keycloak-app.yaml`:
   - `metadata.name: keycloak-stage`
   - `spec.source.path: platform/keycloak/overlays/stage`
   - `spec.destination.namespace: platform-keycloak-stage`
   - `spec.source.targetRevision`: scegli secondo la decisione di pinning sopra

3. Commit, push. La root Application notera' la nuova Application figlia e la creera' nel cluster.

4. Ripeti per gli altri componenti che vuoi duplicare.

## Procedura: cluster k3d separato

1. Crea il nuovo cluster: `k3d cluster create --config cluster/k3d-cluster-stage.yaml` (file da creare partendo da `cluster/k3d-cluster.yaml` e cambiando il `name` e le porte mappate).

2. Aggiungi il cluster alle destination di Argo CD:
   ```bash
   argocd cluster add k3d-lcn-lab-stage --name lcn-lab-stage
   ```
   (richiede CLI `argocd` autenticata; in alternativa via UI Argo CD: Settings → Clusters → Add).

3. Nella Application Argo CD del nuovo ambiente, imposta `spec.destination.server` all'URL dell'API server del cluster `stage` (visibile in `kubectl config view`), invece di `https://kubernetes.default.svc`.

4. Tutto il resto come nella procedura precedente.

## Cosa NON dimenticare

Checklist quando attivi un nuovo ambiente:

- [ ] **Segreti**: ogni ambiente ha bisogno dei suoi segreti (password admin Keycloak, credenziali MongoDB, ecc.). NON riusare quelli di `dev`. Vedi ADR sulla gestione segreti per il pattern adottato.
- [ ] **Risorse hardware**: verifica che il Mac regga il carico aggiuntivo. Aprendo Argo CD UI controlla che non ci siano pod in `Pending` per `OutOfMemory` sul nodo.
- [ ] **Naming consistente**: usa il prefisso `platform-<componente>-<ambiente>` per i namespace (es. `platform-keycloak-stage`).
- [ ] **Aggiorna `docs/architecture.md`** se la nuova topologia ne modifica significativamente il diagramma.
- [ ] **Documenta la motivazione**: aggiungi un breve commento nella Application Argo CD che spiega *perche'* esiste questo ambiente. Senza, tra sei mesi non lo ricorderai.
