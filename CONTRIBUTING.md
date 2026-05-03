# Contributing to localcloudnative-lab

Thanks for your interest in this project. Contributions are welcome,
even though the project started as a personal learning lab.

---

## Welcome contributions

- **Bug reports** in the documentation or in the manifests.
- **Bug fixes** in the bootstrap scripts or in the code.
- **Documentation improvements** (README, ADRs, runbooks).
- **Architectural suggestions** via issues, with explicit reasoning
  about trade-offs and alternatives considered.

There is no contribution process for adding new application
components (workloads): those depend on design choices specific to
the originating reference project, discussed with the Architect
before any implementation.

---

## How to open an issue

Before opening a pull request, open an issue to discuss the proposed
change. Include:

- The problem you want to fix or the improvement you want to introduce.
- Context (operating system, tool versions, output of relevant
  commands).
- The solution you have in mind, if any.

---

## How to submit a pull request

1. Fork the repository and work on a dedicated branch (e.g.,
   `fix/short-description`).
2. Keep changes minimal and consistent with the declared scope.
3. If the change touches an architectural decision (folder structure,
   technology, naming convention), update or create an ADR in
   `docs/adr/`.
4. Make sure the YAML manifests are valid:
   ```bash
   kubectl apply --dry-run=client -f <file>
   # or for Kustomize:
   kubectl kustomize <path>
   ```
5. Update the README if the change impacts operational procedures.
6. Open the PR with a clear description: what changes, why, how to
   test.

---

## Conventions

- **Language**: documentation is in English; commit messages and
  code comments are also in English.
- **Commit messages**: conventional format (`feat:`, `fix:`,
  `chore:`, `docs:`, `refactor:`), concise description.
- **YAML**: 2-space indentation, no tabs.
- **ADRs**: MADR format, progressive 4-digit numbering, explicit
  status (`Proposed` / `Accepted` / `Deprecated` / `Superseded`).

---

## Code of Conduct

This project adopts the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md).
Participating means accepting its terms.

---

## Questions

For general questions about the project, open an issue with the
`question` tag. For direct contact: `afiorillo@gmail.com`.
