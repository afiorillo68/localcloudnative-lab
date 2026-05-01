# Architectural Decision Records (ADR)

Questa cartella contiene gli ADR (Architectural Decision Records) del
progetto `localcloudnative-lab`. Un ADR documenta una decisione
architetturale rilevante: il contesto in cui e' stata presa, le
alternative considerate, la scelta finale, e le sue conseguenze.

Il formato adottato e' [MADR](https://adr.github.io/madr/) (Markdown
Architectural Decision Records), una variante moderna e discorsiva
del formato classico introdotto da Michael Nygard.

## Convenzioni

- **Numerazione progressiva**: ogni ADR ha un numero a quattro cifre
  (`0001`, `0002`, ...) seguito da uno slug breve descrittivo.
- **Stati possibili**: `Proposed`, `Accepted`, `Deprecated`,
  `Superseded by ADR-XXXX`.
- **Immutabilita' della storia**: gli ADR esistenti non vengono
  cancellati ne' riscritti. Quando una decisione cambia, si crea un
  nuovo ADR che marca il precedente come `Superseded`.
- **Granularita'**: un ADR puo' coprire una singola decisione o un
  gruppo di decisioni interdipendenti. Il primo ADR di questo repo
  (`0001`) e' un esempio di ADR omnibus su otto decisioni
  strettamente legate.

## Indice

| ID | Titolo | Stato | Data |
|---|---|---|---|
| [0001](0001-strategia-gitops.md) | Strategia GitOps per il laboratorio | Accepted | 2026-05-01 |
| [0002](0002-strategia-registry-chart-helm.md) | Strategia di gestione registry per i chart Helm di piattaforma | Accepted | 2026-05-01 |
| [0003](0003-eccezione-mongodb-arm64.md) | Eccezione platform-aware per MongoDB e introduzione del driver di compatibilita' arm64 | Accepted | 2026-05-01 |

> **Nota su decision driver evolutivi**: ADR-003 ha introdotto il
> decision driver "compatibilita' arm64", che si aggiunge a quelli
> definiti in ADR-001 e si applica a ogni decisione successiva
> coinvolgente chart, immagini container, o componenti di piattaforma.
> Questo e' un esempio di come gli ADR possono evolvere il sistema di
> decision drivers del progetto, oltre a documentare singole scelte.

## Quando aggiungere un nuovo ADR

Aggiungi un ADR quando:

- prendi una decisione architetturale che ha conseguenze di lungo
  periodo sul progetto;
- cambi una decisione precedente (in tal caso il nuovo ADR marca il
  precedente come `Superseded`);
- rendi esplicita una decisione che era implicita (es. "abbiamo
  sempre fatto cosi' ma non era documentato").

Non serve un ADR per scelte tattiche o di implementazione che non
hanno impatto strutturale (es. la scelta di un nome di variabile,
la formattazione di un file).

## Backlog

Le decisioni identificate ma non ancora prese sono raccolte in
[`BACKLOG.md`](BACKLOG.md). Quando una decisione del backlog viene
ratificata, viene rimossa da li' e formalizzata in un nuovo ADR.
