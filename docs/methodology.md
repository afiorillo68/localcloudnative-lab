# Working Methodology: Architect + Engineer + Decision-maker

This document describes the operating pattern adopted while building
`localcloudnative-lab`. It is not a formal methodology nor a universal
"best practice": it is a way of working with generative AI tools that
proved effective on this specific project, and that is worth documenting
for anyone who wants to try a similar approach.

The document has two parts:

1. **The pattern in the abstract**, applicable to other projects.
2. **How we applied the pattern in this project**, with concrete
   episodes drawn from the development history.

---

## Part 1 — The pattern in the abstract

### Three roles, one person, two tools

The pattern distinguishes three functional roles:

- **Architect**: reasons at a high level about decisions with
  long-term consequences. Balances trade-offs, challenges hasty
  choices, proposes alternatives, writes architectural documentation.
  Does not write code, does not run commands.
- **Engineer**: executes. Writes configuration files, runs shell
  commands, performs iterative debugging, mechanical refactors,
  repository operations. Knows the tools deeply, but does not make
  design decisions.
- **Decision-maker**: the only one who decides. Receives input from
  the Architect, delegates execution to the Engineer, verifies that
  the work matches the intent.

A single human covers the Decision-maker role. The Architect and
Engineer roles are delegated to two distinct AI tools, configured to
optimize the specific role:

- **Architect → "high" model in a conversational interface** (in our
  case, Claude Opus in chat on [claude.ai](http://claude.ai)).
- **Engineer → "operational" model in an agentic interface with
  filesystem access** (in our case, Claude Sonnet in Claude Code).

The tool separation is not a detail: it is the key to the pattern. A
single tool that does both tends to "drift" between the two roles in
uncontrolled ways.

### The four operating rules

The pattern works if four minimum rules are respected.

#### Rule 1 — The Decision-maker is the only one who decides

Architect and Engineer are advisor and executor. They can propose
solutions, raise objections, flag risks. They cannot decide
autonomously on questions that have architectural consequences.

When Architect and Engineer diverge on a solution, **the
Decision-maker chooses and takes responsibility for the choice**.
This is not a formal act: it is the concrete practice of reading
both positions, reasoning, and explicitly declaring the decision
before it is executed.

A corollary worth stating explicitly: **the Architect is not
infallible either**. Treating the Architect as an oracle whose
recommendations bypass scrutiny defeats the pattern. The Architect
will sometimes recommend solutions based on incomplete information,
unverified assumptions, or outdated context. The Decision-maker's job
includes verifying the Architect's reasoning, especially when the
recommendation depends on facts the Architect could plausibly be
wrong about (commercial terms of a third-party tool, current
maintenance status of a project, platform-specific constraints). When
in doubt, ask for sources or run a quick verification before ratifying.

#### Rule 2 — Prompts to the Engineer are scope-locked

The Engineer in agentic mode has a natural tendency to "close the
loop": if it sees an obvious continuation of the work, it executes
it spontaneously. This is useful for simple tasks and disastrous for
structural refactors where every "implicit" decision is an
unratified decision.

For this reason, prompts intended for the Engineer on non-trivial
tasks must be **scope-locked**:

- Numbered list of steps to execute.
- Explicit prohibitions ("DO NOT do X, DO NOT modify Y").
- Mandatory post-execution verification, with a stop criterion if the
  outcome diverges from expected.

Example of a scope-locked prompt:

> Architectural decision made here: we will rename `apps/` to
> `gitops/applications/`. Execute these steps in **a single atomic
> commit**:
>
> 1. `git mv apps/ gitops/applications/`
> 2. In `root-app.yaml`: update `spec.source.path` from `apps` to
>    `gitops/applications`.
> 3. Update every textual occurrence of `apps/` in the README.
> 4. Commit message: `refactor: apps/ -> gitops/applications/`.
>
> DO NOT touch anything else. DO NOT add or modify Applications.
>
> After the commit:
>
> 5. Explicitly verify that `kubectl -n argocd get applications`
>    still shows 5 Applications Synced.
> 6. If something goes wrong, stop and report. Do not correct
>    imperatively.

The opposite of a scope-locked prompt — a narrative one like "rename
the folder and fix the rest" — is an invitation to the Engineer to
interpret, and therefore to overreach.

A useful additional clause for scope-locked prompts: **"if you add
resources or make choices not explicitly requested, list them in the
task summary so they can be ratified."** This lets the Engineer make
locally sensible technical choices (e.g., adding an init container to
solve a permission problem) while keeping those choices visible to
the Decision-maker for ratification.

#### Rule 3 — Distinguish "design decisions" from "technical choices"

A subtle but important distinction emerged from running the pattern:
not all the choices the Engineer makes during execution are equally
suspect. There are two kinds.

**Design decisions** — choices about *what* should be built and
*why*. These have downstream consequences on architecture,
maintainability, and team understanding. Example: deciding whether
to use a Helm chart or write pure manifests; deciding whether to add
an init container to handle file permissions. These belong to the
Architect, with ratification by the Decision-maker.

**Technical choices** — choices about *how* to implement a decision
that has already been made. These are local, mechanical, and can be
made by the Engineer with reasonable confidence. Example: which
specific image tag to use for an init container; which shell flags
to set in a script. These don't need ratification, but they do need
to be technically correct.

The trap is that the Engineer is generally good at design decisions
(when given the right context) but occasionally wrong on technical
choices that require platform-specific or version-specific knowledge.
A scope-locked prompt should distinguish: ratify the design intent
explicitly, leave technical choices to the Engineer, but require
verification of the technical outcome.

#### Rule 4 — The architectural conversation is a separate investment

Design decisions are worth their time. Trying to make them "during"
execution, mixed with shell commands and file diffs, almost always
leads to hasty or undocumented choices.

The pattern recommends **separating cleanly** the design moments
from the execution moments:

- Decisions are discussed with the Architect, in conversation, until
  explicit ratification.
- Only after ratification, the Decision-maker passes a prompt to the
  Engineer.
- The Engineer executes, reports, optionally flags anomalies.
- If new decisions emerge during execution, return to the Architect
  to discuss them, do not delegate to the Engineer.

The apparent cost of this pattern is context-switching between
tools. The real benefit is that every architectural decision is
ratified consciously and documentable.

### Verification is the Decision-maker's responsibility

A critical point that took us several painful episodes to internalize:
**the Engineer signals "done" based on exit code, not based on
end-to-end correctness**. A bash script with `set -e` exits with
status 0 if the last command succeeded, even if a previous command
silently did the wrong thing. A Job that completes with exit 0 may
have skipped its actual work due to an idempotency bug.

This means runbooks and verification commands cannot stop at
infrastructure-level checks ("the pod is Running", "the Job is
Complete"). They must include **end-to-end verification of the
applicative outcome** ("does the database actually exist?", "can the
application user actually authenticate?").

Two practical implications:

- Runbooks should always include a final verification step that
  exercises the system as the eventual user would.
- After the Engineer reports "done", the Decision-maker should run
  the end-to-end check before considering the task closed. Trust but
  verify, especially when the Engineer's success report is
  enthusiastic.

### When the pattern does not apply

Not all tasks require this level of formalization. The pattern is
justified when:

- Decisions have long-term consequences (folder structure,
  technology choices, naming conventions).
- The project is meant to be maintained, shared, published.
- Non-trivial trade-offs need to be balanced.

For tactical tasks (fixing a bug, writing a test, generating
boilerplate) it is fine to interact directly with the Engineer.

### The value of asynchronous documentation

A practical consequence: everything decided with the Architect must
be **written somewhere in the repo**. Typically:

- Architectural Decision Records (ADRs) for design decisions.
- README and runbooks for operational procedures.
- This kind of meta-document for the work process itself.

The Architect has no persistent memory between sessions: every new
conversation starts from zero. The documentation in the repo is the
**shared long-term memory** of the project. It is also what allows a
third reader — or yourself in six months — to understand why the
code looks the way it does without having to reconstruct the
reasoning from scratch.

---

## Part 2 — How we applied the pattern in this project

This section recounts concrete episodes from the development of
`localcloudnative-lab`, with specific references to when the pattern
worked well, when it broke, and what we learned.

### Project genesis

The project started as an informal idea: *"is it feasible to install
a cloud-native stack on a Mac M4 for end-to-end prototyping?"* The
initial conversation with the Architect:

- Confirmed technical feasibility.
- Identified the reference stack (k3d instead of OpenShift Local,
  OrbStack instead of Docker Desktop).
- Scaffolded the initial repo structure (Phase 1 — k3d cluster
  definition).

At this point the first methodological decision arose: continue in
chat with the Architect, or move to the Engineer (Code) for concrete
execution on the Mac. The choice was Code, and it was the correct
one: for tasks requiring dozens of "modify file → apply → observe →
correct" iterations, the agentic Engineer with filesystem access is
much more efficient than copy-pasting from the chat.

### Episode 1 — When the pattern first broke

After Phase 1 and Phase 2 (Argo CD bootstrap), the Decision-maker
asked the Engineer to "also proceed with setting up the three
applications" (Apisix, Keycloak, MongoDB), skipping the architectural
conversation with the Architect that had been planned.

The Engineer executed correctly but made several implicit design
decisions on its own:

- App-of-apps pattern with `directory` recursive (vs ApplicationSet).
- Mono-repo with everything in one place.
- One Argo CD Application per component, namespace named after the
  component.
- `targetRevision: HEAD` without pinning.
- Self-managed Argo CD.

The choices were reasonable, but they were choices. The
Decision-maker only noticed afterward, looking at a screenshot of
the Argo CD UI showing five Applications already created.

Three options at that point:

- **Path A**: accept the fait accompli, ratify after the fact.
- **Path B**: roll back, hold the architectural conversation,
  reconstruct.
- **Path C**: accept the current structure but hold the
  architectural conversation **now**, before proceeding to the next
  phase.

The Decision-maker chose Path C, and it was the right call: low cost
(half an hour of chat), high benefit (eight decisions consciously
ratified in an omnibus ADR-001).

**Lesson learned**: the pattern does not break catastrophically if
recovered in time. The warning signal is the moment you realize the
Engineer has made decisions you didn't ratify. When that happens,
stopping and ratifying after the fact is far cheaper than continuing
and accumulating decision debt.

### Episode 2 — The patch that didn't work

During Argo CD bootstrap, the Engineer planned to apply a patch to
the `argocd-cm` ConfigMap to disable TLS in insecure mode. The
Decision-maker checked the cluster and discovered the patch was not
actually applied: the ConfigMap was empty.

The Architect, consulted for diagnosis, identified two possible
causes:

- The patch used the wrong selector (`argocd-cm` instead of
  `argocd-cmd-params-cm`, where `server.insecure` actually lives).
- Strategic merge patches on ConfigMaps without a `data:` section
  can fail silently.

At this point, instead of chasing the Kustomize fix, the Architect
proposed to **drop the insecure patch entirely**: in production it
would never be enabled, and standard HTTPS port-forward worked just
as well.

**Lesson learned**: the Architect is not only for "big" decisions.
Sometimes it is needed to right-size an operational problem the
Engineer is stubbornly chasing. The right question wasn't "how do I
make the patch work?", it was "do I actually need the patch?".

### Episode 3 — The blinded prompt pattern

After Episode 1, the Decision-maker started structuring prompts to
the Engineer much more rigorously. Real example: the prompt for
renaming `apps/` to `gitops/applications/`:

- Numbered list of six precise steps.
- Explicit prohibitions ("DO NOT modify anything else, DO NOT add or
  modify Applications").
- Mandatory verification with stop criterion ("if anything goes wrong
  in verification, stop and report").

From the moment this pattern was adopted systematically, **there was
not a single overreach episode**. The Engineer executed exactly what
was requested, neither more nor less.

One might think this limits the Engineer's creativity. In practice
it frees it: the Engineer can focus its attention on correct
execution, without also having to "guess" the scope. For creative
tasks (e.g., proposing a solution to an open problem), the
scope-locked prompt does not apply and the Engineer is free again.

### Episode 4 — The structured architectural session

Mid-Phase 2, the Decision-maker invested a structured session with
the Architect to ratify eight GitOps strategy decisions. Session
format:

1. The Architect presents one decision at a time, with explicit
   trade-offs (comparison table when useful), considered
   alternatives, and a motivated recommendation.
2. The Decision-maker responds with an explicit choice ("yes",
   "no", "want to dig deeper").
3. Move to the next decision.

Eight decisions in about forty minutes of conversation. The
decisions were then formalized in a single omnibus ADR (ADR-001),
in MADR format.

**Lesson learned**: the structured architectural conversation is
significantly faster than the "free" conversation. The
Decision-maker doesn't have to chase arguments; each round is a
focused input and a curt response. Trade-off: it requires the
Architect to be prepared to structure the discourse, and the
Decision-maker to be willing to respond in real time without
brooding for hours.

### Episode 5 — When the Architect was wrong

During Phase 3 (the first platform component to populate, MongoDB),
the Architect repeatedly recommended solutions that didn't survive
contact with reality:

- **Chainguard charts as drop-in Bitnami replacement**: recommended
  before verifying the commercial model. The Chainguard `iamguarded`
  charts require a paid Chainguard subscription. Withdrawn after
  user pushback.
- **arm64 compatibility was sidelined**: the chart-based path was
  ratified without verifying that the Bitnami-ecosystem images had
  arm64 manifests. They didn't. Three iterations of choosing a
  different chart followed before the constraint became visible.
- **Cleanup labels that didn't match**: a cleanup command using
  `-l app.kubernetes.io/instance=mongodb` was specified in a prompt,
  but the Bitnami chart had used different labels. The cleanup did
  nothing, and old StatefulSets persisted invisibly into the next
  attempt.

These were not single-event errors but a pattern: the Architect
operated as if "all charts work everywhere", without actively
verifying platform constraints. The Decision-maker eventually had to
introduce a new permanent decision driver — "arm64 compatibility
verified before ratification" — formalized in ADR-003.

**Lesson learned**: trust the Architect on architectural reasoning,
verify on factual claims (commercial terms, version availability,
platform constraints). When in doubt, ask the Architect to web-search
or to flag the assumption, rather than ratifying on the basis of
"the Architect said so". This is the practical meaning of "the
Architect is not infallible" stated in Rule 1.

### Episode 6 — Design decision vs technical choice

During the same Phase 3 sessions, the Engineer added an init
container to handle MongoDB keyFile permissions. This was a
**design decision** (do we need an init container at all?) that the
Engineer made on its own without ratification. The decision was
correct: MongoDB has strict permission requirements on the keyFile
that are easier to handle via init container than via Secret default
modes.

However, the Engineer's **technical choice** — using `mongo:8.0` as
the init container image — was wrong. The full MongoDB image has a
hardened rootfs that prevents Kubernetes from mounting the service
account token; the init container failed with `read-only file
system`. The fix was to use `busybox:1.36` instead, a minimal image
with a standard rootfs.

This episode crystallized Rule 3 ("design decisions vs technical
choices"). The Engineer's design judgment was good; its technical
choice failed because it required platform-specific knowledge the
Engineer lacked. The right verification step would have been: "the
Engineer added an init container — design intent looks fine, but
does the chosen image actually work in this environment?".

**Lesson learned**: when the Engineer makes an unrequested
architectural choice, evaluate the design separately from the
implementation. Often the design is sound and only the technical
detail needs correction.

### Episode 7 — Exit code zero is not success

Late in Phase 3, the Engineer reported that the MongoDB application
user `lcnapp` had been created. The bootstrap Job logs said:

```
==> Verify/create application user 'lcnapp'...
User lcnapp already exists, skip.
```

A few minutes later, the Decision-maker ran an end-to-end check:

```
db.adminCommand('usersInfo', {forAllDBs: true})
→ users: [{ user: 'root', db: 'admin' }]
```

Only `root` existed. The application user had never been created.
The Job's idempotency check was buggy: it returned "already exists"
even when the user didn't exist. The Job exited with status 0, the
Engineer reported success, but the system was broken in a way that
would only surface later when an actual application tried to
authenticate.

**Lesson learned**: a Job completing with exit 0 is necessary but
not sufficient. End-to-end verification (does the user exist? can
it authenticate? does the database respond as expected?) belongs in
the runbook and must be run by the Decision-maker, not skipped
because the Engineer "looked happy".

This led to Rule "Verification is the Decision-maker's
responsibility" being added to Part 1. It also led to retroactively
strengthening every operational runbook in the repo: the final
verification step must exercise the system, not just inspect its
control plane.

### Episode 8 — Symptoms vs causes in agent loops

In one debugging session, the Engineer entered a loop: it kept
running `kubectl get pods` and reporting "MongoDB still in
CrashLoopBackOff", trying various restarts. What it didn't notice
was that the **error itself had changed nature** between iterations.
Initially the pod failed with one error; after a fix, it failed with
a different error; after another fix, with a third. The Engineer
saw "pod not Ready" each time and treated it as the same symptom.

The Decision-maker had to step in, intervene with manual diagnostic
commands, and feed the result back: "look at the events, the error
now is different from before, you're chasing the wrong cause."

**Lesson learned**: agentic tools tend to optimize for the symptom
they last observed. They do not naturally re-validate diagnoses
between iterations. A useful clause for scope-locked prompts is:
"if after N retry cycles the system is still in an error state,
**stop and report the current error explicitly**, do not assume it's
the same problem you've been working on."

### Episode 9 — Cosmetic drift vs substantive drift

After all the imperative interventions during the MongoDB
troubleshooting (`kubectl delete pod --force`, manual SSA patches,
forced syncs), the Argo CD Application ended up in a permanent
`OutOfSync` state even though everything was working. Diagnosing the
drift via UI revealed it was **cosmetic**: Kubernetes API server
auto-populates `apiVersion: v1` and `kind: PersistentVolumeClaim`
fields in `volumeClaimTemplates`, while the Git manifest specified
them in shorthand form.

Two kinds of drift can occur in GitOps:

- **Substantive drift**: real differences caused by imperative
  interventions, manual edits, or unratified Engineer choices.
  These need to be reconciled by either updating Git or updating the
  cluster, with conscious decision.
- **Cosmetic drift**: differences caused by the Kubernetes API
  server auto-completing default fields. These can be eliminated by
  making the Git manifest match the runtime form, or by configuring
  Argo CD to ignore specific fields.

The fix here was the first option: a two-line change to the Git
manifest, and the Application returned to `Synced`.

**Lesson learned**: not all drift is the same. Diagnose before
reacting. A "force sync with prune" applied to cosmetic drift
without diagnosis is not dangerous, but a "force sync with prune"
applied to substantive drift can destroy real configuration. The
right reflex is: open the diff, look at it, then decide.

### Episode 10 — Operational hygiene around credentials

A minor but real lesson from late-night debugging sessions: the
Decision-maker more than once pasted real production passwords into
the chat with the Architect when reporting troubleshooting output.
The cluster being local-only mitigated the risk, but the habit is
poor. Credentials, even for personal lab clusters, should be
redacted from any text that lands in conversational AI logs.

A practical mitigation: scope-locked prompts to the Engineer should
include a clause "do not paste sensitive values (passwords, tokens,
keys) in your output reports". When operating manually, the
Decision-maker should adopt the same discipline.

**Lesson learned**: this is not about whether the specific
credential was sensitive. It's about building habits that scale to
contexts where the credential matters.

---

## What stays in repo memory between sessions

The Architect has no persistent memory between chat sessions. This
limit became evident at various points in the project: every new
conversation requires brief "context restoration" via README, ADRs,
and recent repo files.

The pattern adopted to manage this:

- The **README** is the primary source of truth for project
  structure.
- The **ADRs** are the source of truth for past architectural
  decisions.
- The **runbooks in `docs/how-to/`** are the source of truth for
  operational procedures (e.g., "how to add an environment").
- This **methodology document** is the source of truth for the work
  process itself.

When a new chat session starts, the Decision-maker just attaches the
README and the relevant ADRs to bring the Architect "in sync".
Long-term memory lives in the repo, not in the tool.

The Engineer (Code) has direct filesystem access, so it reads the
repo on its own. Its "persistent context" is implicit.

---

## Conclusions

The Architect + Engineer + Decision-maker pattern is not an original
invention: it is the classical operating model of a software team,
where a Solutions Architect provides direction, a developer
executes, and a product owner / tech lead decides. The novelty, if
any, is in formalizing how this model translates when the Architect
and Engineer roles are covered by AI tools.

It is worth restating that the pattern is not "necessary": smaller
projects, throwaway prototypes, or tactical tasks are perfectly
served by interacting with a single tool directly. The pattern pays
off in contexts where:

- Decisions have long-term consequences.
- The project will be shared with others.
- The quality of the decision process is part of the value delivered.

For anyone who wants to replicate this approach on their own
project, the suggestion is to start small: apply the four operating
rules on a single architectural decision, see how it goes, iterate.
The formalization of the pattern presented here is the result of
several days of work on a concrete project, not a manual studied a
priori.

The lessons documented in Part 2 are not abstract principles. Each
of them came from a specific painful episode that took a real
amount of time to debug and recover from. We document them not as
universal truths but as warnings: these are the shapes the pattern
breaks in, and these are the corrective practices we found useful.
Your project will probably break in different shapes. The general
posture is what matters: stay aware that the tools have failure
modes, and design your verification around them.

---

## References

- Architectural Decision Records of this project: [`docs/adr/`](adr/)
- Project main README: [`../README.md`](../README.md)
- Operational runbooks: [`how-to/`](how-to/)
- On MADR (Markdown Architectural Decision Records):
  https://adr.github.io/madr/
