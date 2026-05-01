# Contribuire a localcloudnative-lab

Grazie per l'interesse in questo progetto. Le contribuzioni sono benvenute,
anche se il progetto nasce come laboratorio personale a scopo didattico.

---

## Tipi di contribuzione graditi

- **Segnalazioni di errori** nella documentazione o nei manifest.
- **Fix di bug** nel bootstrap o negli script.
- **Miglioramenti alla documentazione** (README, ADR, runbook).
- **Suggerimenti architetturali** tramite issue, con ragionamento esplicito
  su trade-off e alternative.

Non e' previsto un processo di contribuzione per l'aggiunta di nuovi
componenti applicativi (workloads): quelli dipendono da scelte di design
specifiche del progetto DCPP - Tifoserie Web, discusse con l'Architect
prima di qualsiasi implementazione.

---

## Come aprire una issue

Prima di aprire una pull request, apri una issue per discutere la modifica
proposta. Include:

- Il problema che vuoi risolvere o il miglioramento che vuoi introdurre.
- Il contesto (sistema operativo, versione degli strumenti, output di
  comandi rilevanti).
- La soluzione che hai in mente, se ce l'hai.

---

## Come inviare una pull request

1. Fai fork del repo e lavora su un branch dedicato (es. `fix/descrizione-breve`).
2. Mantieni le modifiche minime e coerenti con lo scope dichiarato.
3. Se la modifica tocca una decisione architetturale (struttura cartelle,
   tecnologia, naming convention), aggiorna o crea un ADR in `docs/adr/`.
4. Assicurati che i manifest YAML siano validi:
   ```bash
   kubectl apply --dry-run=client -f <file>
   # oppure per Kustomize:
   kubectl kustomize <path>
   ```
5. Aggiorna il README se la modifica impatta procedure operative.
6. Apri la PR con una descrizione chiara: cosa cambia, perche', come testare.

---

## Convenzioni

- **Lingua**: la documentazione e' in italiano; i commit message e i
  commenti nel codice sono in inglese.
- **Commit message**: formato convenzionale (`feat:`, `fix:`, `chore:`,
  `docs:`, `refactor:`), corpo in inglese, descrizione concisa.
- **YAML**: indentazione a 2 spazi, nessun tab.
- **ADR**: formato MADR, numerazione progressiva a quattro cifre, stato
  esplicito (`Proposed` / `Accepted` / `Deprecated` / `Superseded`).

---

## Codice di condotta

Questo progetto adotta il [Contributor Covenant 2.1](CODE_OF_CONDUCT.md).
Partecipare significa accettarne i termini.

---

## Domande

Per domande generali sul progetto, apri una issue con il tag `question`.
Per contatti diretti: `angelo.fiorillo+lcn-lab@gmail.com`.
