# DESIGN.md — Product, Interaction & Visual Design Contract

<!-- DESIGN_DIRECTOR_STATE
{"state":"D9_RENDERED_CRITIQUE","directionLocked":true,"updatedAt":"2026-11-02T08:15:25.217Z","reason":"Discovery field primary_input=true","discovery":{"version":3,"brief":{"product":true,"primaryUser":true,"coreJob":true,"primaryOutcome":true,"constraints":true,"productTruthReviewed":true,"synthesis":{"sections":{"design_brief":true,"evidence_synthesis":true,"product_brief":true,"interaction_brief":true,"ux_flow_brief":true,"design_implications":true,"constraints_non_goals":true,"open_decisions":true,"assumptions":true},"complete":true,"version":1}},"interaction":{"platforms":true,"primaryInput":true,"context":true,"reviewed":true},"interview":{"version":1,"active":true,"completed":true,"round":5,"askedTotal":10,"answeredTotal":10,"maxQuestions":12,"readinessTarget":0.86,"readiness":1,"recommendation":"ready","blockingGaps":0,"blockingGapIds":[],"readinessReasons":["No material discovery gap detected"],"candidates":[{"id":"Q-SCOPE","text":"Is this discovery meant to establish PiFrame's overall product/UI contract, or focus on a specific session-workflow change in the current branch?","category":"scope","impact":5,"uncertainty":0.95,"dependency":3,"answerability":0.98,"novelty":1,"blocking":true,"score":100,"status":"answered","round":1,"answerSummary":"User wants a whole-product PiFrame discovery and UX contract; active branch is context, not the design scope.","blockingResolved":true,"answeredAt":"2026-10-06T10:34:18.375Z"},{"id":"Q-FILE-VIEW","text":"Should repository files support read-only browsing/preview, or direct editing and saving from PiFrame?","category":"file pane behavior","impact":5,"uncertainty":0.98,"dependency":3,"answerability":0.95,"novelty":0.95,"blocking":true,"score":100,"status":"answered","round":2,"answerSummary":"User wants repository files editable and savable in PiFrame, not a read-only browser. This adds a source-editing capability to the requested file pane.","blockingResolved":true,"answeredAt":"2026-10-06T11:47:05.041Z"},{"id":"Q-VISUAL-DIRECTION","text":"Which visual composition should lead exploration: Bento Triptych, Artifact Atlas, or Conversation Desk?","category":"visual direction","impact":5,"uncertainty":0.9,"dependency":3,"answerability":0.98,"novelty":1,"blocking":true,"score":100,"status":"answered","round":3,"answerSummary":"User selected Bento Triptych: three co-visible wide work areas for repository/editor, Pi chat and Git Changes; preserve DR10 colors and PiFrame identity.","blockingResolved":true,"answeredAt":"2026-10-06T13:09:57.001Z"},{"id":"Q-COLD-TITLE","text":"Quando manca un titolo nell'indice, preferisci mostrare subito un ID provvisorio o attendere il titolo esatto?","category":"product-fidelity","impact":5,"uncertainty":0.95,"dependency":3,"answerability":1,"novelty":1,"blocking":true,"score":100,"status":"answered","round":5,"answerSummary":"Quando un titolo non è presente o non è aggiornato nell'indice, mostrare subito l'ID o l'ultimo titolo noto provvisorio e sostituirlo con il titolo esatto appena disponibile.","blockingResolved":true,"answeredAt":"2026-10-29T15:21:32.075Z"},{"id":"Q-FLOW","text":"Which session workflow should define the critical path: resume/reconnect ongoing work, find and switch sessions, branch/fork/clone, or protect uncertain/shared sessions?","category":"critical flow","impact":5,"uncertainty":0.9,"dependency":3,"answerability":0.95,"novelty":0.95,"blocking":true,"score":93,"status":"answered","round":1,"answerSummary":"User selected find/switch sessions as the product's primary critical workflow. Treat searching/browsing the index, selecting the intended session and confirming its current context as the core path; creation and branch operations remain secondary.","blockingResolved":true,"answeredAt":"2026-10-06T10:34:45.338Z"},{"id":"Q-REPO-CONTEXT","text":"Should the opened repository follow the active session's working directory, or be selected independently?","category":"repository context","impact":5,"uncertainty":0.82,"dependency":3,"answerability":0.95,"novelty":0.9,"blocking":true,"score":81,"status":"answered","round":2,"answerSummary":"Opened repository follows the active Pi session's working directory; selecting another session switches associated file and Git context.","blockingResolved":true,"answeredAt":"2026-10-06T11:48:43.468Z"},{"id":"Q-D6-LOCK","text":"Do you want Bento Triptych formally locked as the visual direction, preserving DR10 and PiFrame identity?","category":"direction lock","impact":5,"uncertainty":0.55,"dependency":3,"answerability":0.98,"novelty":0.8,"blocking":true,"score":50,"status":"answered","round":4,"answerSummary":"User explicitly locked Bento Triptych as PiFrame's visual direction while retaining DR10 colors and PiFrame identity.","blockingResolved":true,"answeredAt":"2026-10-06T13:12:47.907Z"},{"id":"Q-STALE-TITLE","text":"Come gestire un titolo in cache mentre si verifica una rinomina esterna?","category":"product-fidelity","impact":4,"uncertainty":0.75,"dependency":3,"answerability":1,"novelty":0.8,"blocking":false,"score":48,"status":"candidate"},{"id":"Q-LOADING-LIST","text":"Deve essere visibile una lista parziale durante la scoperta iniziale?","category":"product-fidelity","impact":4,"uncertainty":0.6,"dependency":3,"answerability":1,"novelty":0.7,"blocking":false,"score":34,"status":"candidate"},{"id":"Q-PLATFORM","text":"Among already-supported Windows, macOS and Web targets, which one should get priority when layout or interaction trade-offs appear?","category":"platform priority","impact":4,"uncertainty":0.7,"dependency":2,"answerability":0.95,"novelty":0.85,"blocking":false,"score":30,"status":"answered","round":1,"answerSummary":"User wants equal priority across Windows desktop, macOS desktop and Web; retain parity rather than choosing a single primary deployment.","blockingResolved":true,"answeredAt":"2026-10-06T10:36:03.653Z"},{"id":"Q-GIT-ACTIONS","text":"Should Git Changes be inspect-only, or include staging/commit/discard actions?","category":"Git capability scope","impact":4,"uncertainty":0.72,"dependency":2,"answerability":0.9,"novelty":0.85,"blocking":false,"score":29,"status":"answered","round":2,"answerSummary":"User wants Git write actions in Git Changes (stage, commit and/or discard), not inspect-only status/diff. Treat this as new repository-mutating capability, with destructive-action safety and exact command scope still to define.","blockingResolved":true,"answeredAt":"2026-10-06T11:49:36.122Z"},{"id":"Q-VISUAL-HIERARCHY","text":"Should chat or repository editing receive greatest space in expanded workspace?","category":"visual hierarchy","impact":4,"uncertainty":0.68,"dependency":2,"answerability":0.95,"novelty":0.8,"blocking":false,"score":28,"status":"candidate"},{"id":"Q-USER","text":"Should this experience favor expert/high-frequency Pi users or occasional/new-to-Pi users when throughput and discoverability trade off?","category":"primary user","impact":4,"uncertainty":0.6,"dependency":2,"answerability":0.95,"novelty":0.8,"blocking":false,"score":24,"status":"answered","round":1,"answerSummary":"User prefers a balanced experience for frequent CLI users and occasional users. They also explicitly want the primary workspace closer to the supplied VS Code Bento-style reference, with three reachable areas: chat, files in the open Git repository, and a Git Changes folder/pane.","blockingResolved":true,"answeredAt":"2026-10-06T10:48:17.403Z"},{"id":"Q-PANE-ADAPT","text":"At compact widths, must chat, file browser and Git Changes all remain simultaneously visible, or may some move into drawers/tabs?","category":"adaptive layout","impact":3,"uncertainty":0.72,"dependency":2,"answerability":0.9,"novelty":0.75,"blocking":false,"score":19,"status":"candidate"},{"id":"Q-PANE-PRIORITY","text":"Which area should dominate available workspace when space is tight: chat, repository files or Git Changes?","category":"layout priority","impact":3,"uncertainty":0.72,"dependency":2,"answerability":0.9,"novelty":0.75,"blocking":false,"score":19,"status":"candidate"},{"id":"Q-SUCCESS","text":"What result would make PiFrame most valuable: reliable continuity, faster session organization, or safer control of running work?","category":"primary outcome","impact":4,"uncertainty":0.55,"dependency":2,"answerability":0.9,"novelty":0.7,"blocking":false,"score":18,"status":"candidate"},{"id":"Q-REFERENCE-STYLE","text":"Does 'closer to VS Code Bento' mean spatial grouping only, or also visual styling?","category":"visual reference","impact":3,"uncertainty":0.55,"dependency":2,"answerability":0.95,"novelty":0.7,"blocking":false,"score":15,"status":"candidate"},{"id":"Q-VISUAL-COMPACT","text":"Must all three work areas remain visible at compact widths?","category":"adaptive layout","impact":3,"uncertainty":0.6,"dependency":2,"answerability":0.9,"novelty":0.7,"blocking":false,"score":15,"status":"candidate"},{"id":"Q-VISUAL-REF","text":"Should VS Code influence spatial composition only, or also color/type/branding?","category":"reference fidelity","impact":3,"uncertainty":0.25,"dependency":2,"answerability":0.95,"novelty":0.5,"blocking":false,"score":5,"status":"candidate"},{"id":"Q-VISUAL-SIGNATURE","text":"Which file/Git interaction should become the interface's signature moment?","category":"signature interaction","impact":2,"uncertainty":0.6,"dependency":1,"answerability":0.85,"novelty":0.6,"blocking":false,"score":4,"status":"candidate"},{"id":"Q-VISUAL-DENSITY","text":"Should visual density favor flat information bands or more separated pane framing?","category":"visual density","impact":2,"uncertainty":0.55,"dependency":1,"answerability":0.9,"novelty":0.55,"blocking":false,"score":4,"status":"candidate"},{"id":"Q-ERROR-RETRY","text":"Come presentare un errore temporaneo di lettura dell'indice?","category":"recovery","impact":2,"uncertainty":0.3,"dependency":2,"answerability":1,"novelty":0.5,"blocking":false,"score":4,"status":"candidate"},{"id":"Q-D6-CHAT-WEIGHT","text":"Should chat or source editor receive a little more width in the selected Bento Triptych?","category":"pane hierarchy","impact":3,"uncertainty":0.4,"dependency":1,"answerability":0.9,"novelty":0.4,"blocking":false,"score":3,"status":"candidate"},{"id":"Q-SCAN-ALL","text":"Va mantenuto il limite corrente di sessioni mostrate?","category":"scope","impact":2,"uncertainty":0.2,"dependency":2,"answerability":1,"novelty":0.3,"blocking":false,"score":2,"status":"candidate"}],"lastPlanAt":"2026-10-29T15:01:08.149Z","lastAskedAt":"2026-10-29T15:01:41.395Z"},"evidence":{"referencesTotal":17,"referencesResolved":17,"referencesUnresolved":0,"references":[{"id":"REF-001","status":"inspected"},{"id":"REF-002","status":"inspected"},{"id":"REF-003","status":"inspected"},{"id":"REF-004","status":"inspected"},{"id":"REF-005","status":"inspected"},{"id":"REF-006","status":"inspected"},{"id":"REF-007","status":"inspected"},{"id":"REF-008","status":"inspected"},{"id":"REF-009","status":"inspected"},{"id":"REF-010","status":"inspected"},{"id":"REF-011","status":"inspected"},{"id":"REF-012","status":"inspected"},{"id":"REF-013","status":"anti-reference"},{"id":"REF-MAX-CONTEXT","status":"inspected"},{"id":"REF-SHIFT-CLOSED","status":"inspected"},{"id":"REF-SHIFT-OPEN","status":"inspected"},{"id":"REF-USER-QUESTION-PAUSE","status":"inspected"}],"conflictsRecorded":11,"reviewed":true},"ux":{"criticalFlowDefined":true},"visual":{"candidateCount":3,"selected":true,"locked":true},"system":{"ready":true},"build":{"implemented":false,"implementationFiles":[],"implementationMarkedAt":""},"qa":{"renderedCritique":false,"renderedEvidence":[],"renderedRequiredAfter":"2026-10-16T14:18:27.471Z","humanReview":{"status":"not_ready","round":10,"feedback":[{"round":2,"submittedAt":"2026-10-07T08:44:24.099Z","text":"User feedback from live app testing (preserve full intent): (1) Repository pane opens empty; error is `Bad state: Unsupported command type: workspace.listFiles`. (2) Visual direction is unsatisfactory: keep Bento spatial grouping but use a modern VS Code-like treatment—slight borders and small gaps between compartments, rounded corners; current square-off UI feels wrong. Replace DR10 palette with PiFrame Dark (dark) and Latte (light), source https://catppuccin.com/palette/. (3) Sessions UX: allow opening/choosing a folder before creating a session in it; show sessions in a tree grouped by folder/repository; hide worker# subagent sessions. Session and Git lists have excessive whitespace. (4) Light theme has odd black components, including chat input. (5) Show Pi session metrics in chat: context-window usage, session cost, model, thinking effort and package-provided controls/metadata such as Caveman and Ponytail levels. (6) Make panels resizable and hideable. (7) Remove redundant Workarea list of modified files; unify with Git Changes, distinguishing agent-authored from manual changes. Git Changes should list modified tracked files; selecting a file opens its diff; per-file plus stages it and undo reverts its changes. (8) Settings should list installed Pi packages and support remove, individual update and version pinning. (9) Composer needs add-files-to-context; selecting code lines and right-clicking should offer `Add to chat` with exact file/line reference. (10) Minimize/restore/fullscreen causes several seconds of unresponsiveness."},{"round":4,"submittedAt":"2026-10-07T12:43:12.231Z","text":"User reports PiFrame Light / Dark appear in Settings, but activating them still renders the old palette; remove those colors from the active theme. Remove Rams and Teenage Engineering from the current design direction and design decisions because user is moving away from that language. Bento pane compartments now have grouping, but other app surfaces still use square, borderless styling; extend consistent modest rounding and subtle borders to those surfaces too. User reports minimize/maximize stalls seem improved or gone. Fix theme and surface issues; user will review the app again. No approval given."},{"round":9,"submittedAt":"2026-10-16T13:21:48.427Z","text":"(1) Unified chat input box: text area and buttons (model, thinking, attach, review, send) share the same single background card, like VS Code and Antigravity, eliminating wasted padding. (2) Attach button positioned on the right side, to the left of review and send. (3) Remove separate top tab bar for 'File'/'Git Changes' in medium/compact layout; instead embed expandable/collapsible tabs directly in the companion pane title bar ('|-File-||---Git Changes---|' and vice-versa). (4) Remove background and border from intermediate blocks (reasoning/thinking, edit, tool execution) in chat transcript so they are completely compact and borderless."}],"approvedAt":"","approvedRound":0},"hardened":false,"hardeningEvidence":"","verified":false,"verificationCommand":"","verifiedAt":""},"openQuestions":0,"assumptions":3,"lastUpdated":"2026-11-02T08:15:25.217Z"}}
DESIGN_DIRECTOR_STATE -->

> **Source of truth for UI/UX.**
>
> This file is not a static style guide. It is the durable record produced by the **Design Director workflow**:
>
> `brief intake → evidence review → product definition → interaction model → visual exploration → direction lock → design system → implementation → rendered critique → hardening → decision log`
>
> The user may provide URLs, images, screenshots, PDFs, documents, existing apps, or written references. These are evidence and inspiration. The agent must extract principles from them, not blindly copy their surface appearance.

---

## Context picker / slider iteration — human feedback, approval pending

- **Direct live-app feedback (high confidence):** the saved tier is visible in the composer but clicking does nothing. User requests a Custom option plus exact pricing tiers, a hidden-until-Custom maximum slider (100k–1M, 50k steps), and an always-visible reserve slider (0.5–25%, 0.5 steps). Example GPT-6 Luna: Custom / 272k (Tier base) / 1M (Max / Tier esteso). User closed the app for implementation; no approval given.
- **Cause reproduced:** composer loads its own model catalogue once at initialization; mounting before the daemon connects leaves an empty list. The chip can render from the saved override and model name, but its picker silently returns without model metadata. Regression: `apps/pi_frame/test/composer_context_picker_test.dart` fails on the previous implementation.
- **Interaction contract:** both entry points use one context-window selector. Reload catalogue on chat click, visibly report missing model metadata, keep exact provider tiers independent of the Custom step size. Maximum never exceeds physical model capability; disable Custom below 100k. Commit slider changes only on release and retain the server-confirmed value on failure. Disabled/read-only/busy states must not accept mutations.
- **State contract:** explicit Custom/preset UI mode is shared between chat and panel during the session; a saved non-preset limit implies Custom when UI mode is reconstructed. No new backend preference or provider capability is invented.
- **Visual intent:** reuse current theme tokens; dropdown first, conditional maximum slider directly below it, then reserve slider with numeric labels and the calculated threshold. Fresh real Flutter widget captures (test-fixture model/usage): `docs/design-evidence/context-policy-presets-fixture.png` and `docs/design-evidence/context-policy-panel-fixture.png`. Focused QA: `docs/design-evidence/hardening.md`; 57 focused Flutter tests pass and `flutter analyze` is clean. Human review pending; remain in D9.

## Context policy iteration — pending human visual review

- **Product truth (high confidence):** the model picker must show authenticated GitHub Copilot models allowed by organization policy, intersected with local Pi `enabledModels`. Failed verification must not expose the static Copilot catalogue.
- **Interaction truth (high confidence):** Area di lavoro → Sessione exposes a custom maximum for every model, capped by its physical window, with tier presets and reset. A reserve percentage means unused capacity: default 2.5% of 200k triggers at 195k; 5% of 1M triggers at 950k. Settings are session-scoped and survive reopening. Busy/read-only sessions cannot silently accept changes.
- **Implementation evidence:** `apps/agentd/src/pi/contextLimitExtension.ts` maps this threshold onto native Pi compaction without changing Pi settings; `tools/scripts/smoke-context-policy.mjs` verifies it against Pi 1.4.0 and a loopback model. Provider token estimates and individual large outputs mean this is not an absolute billing guarantee.
- **Reference:** REF-MAX-CONTEXT, upstream README and extension source inspected. Reuse the soft-limit intent and failed-compaction loop safeguards, not its separate slash-command UI.
- **Visual intent:** reuse existing panel fields, subtle borders and rounding; no new visual direction. Real Flutter widget capture (test-fixture model and usage, not a live provider session): `docs/design-evidence/context-policy-panel-fixture.png`, generated by `apps/pi_frame/test/context_policy_panel_test.dart`. Current human rendered review remains pending; no approval inferred.

# 00. Design Director — project brief intake

## Project identity

### Product / app name
PiFrame.

### One-sentence product description
A Flutter desktop and web GUI for Pi coding-agent sessions, with chat, editable repository files and Git Changes (stage/commit/discard) organized as one workspace while Pi remains owner of session history.

### Core job-to-be-done
Find/create/switch Pi sessions; follow agent work in chat while editing the active session's repository and managing its Git Changes, then safely reattach after GUI interruption.

### Primary user
Pi coding-agent / CLI users who want session management and live agent interaction through a GUI. User prefers balance: fast routine paths plus discoverable controls for occasional use.

### Secondary users
No separate secondary audience established by current evidence.

### User context / scene
Local developer workstation on Windows, macOS or Web, with keyboard and pointer input. User selected equal platform priority. Users may follow long-running agent work intermittently; GUI can close or disconnect while the daemon preserves/replays events.

### Primary outcome / aha moment
User returns to intended Pi-owned session with history intact, can edit its repository and stage/commit/discard changes alongside agent work, and never loses unsaved edits or triggers hidden Git writes.

### Business or product priority
No business metric stated. Product evidence emphasizes continuity, trustworthy session control and local privacy.

### Non-negotiable constraints
Windows/macOS/Web at equal priority; local daemon and loopback security; no remote telemetry; Pi owns session files/history; preserve replay, drafts, queues, read-only session safeguards and extension UI; retain Italian copy and original PiFrame identity. Official default themes are PiFrame Dark (`themes/piframe-dark.json`) and PiFrame Light (`themes/piframe-light.json`), retaining Bento work-area grouping. User requires editable active-session repository files and IDE-like Git Changes with explicit stage/undo; protect dirty edits and never hide writes. iOS/Android out of scope.

---

## 00.1 User-provided references

> References are part of the brief. Do not treat them as decoration.

### How to interpret references

Classify each reference as one or more of:

- `visual-inspiration`
- `interaction-inspiration`
- `brand-reference`
- `competitor`
- `platform-reference`
- `content/reference material`
- `technical/reference implementation`
- `anti-reference` — something we explicitly do NOT want

For every reference, extract:
1. what is useful;
2. what is not useful;
3. which design principle it suggests;
4. whether it is a direct constraint or merely inspiration;
5. where the principle should or should not appear in the product.

### Reference register

| ID | Type | Source | What to extract | Status |
|---|---|---|---|---|
| REF-USER-QUESTION-PAUSE | interaction requirement | User request in conversation: keep composer draft private during agent question; require answering; restore draft afterward. | Inline custom answer; temporarily hide and disable normal composer during a pending agent question; restore the unsent draft after resolution. — Principle: A pending question owns the input focus and blocks unrelated chat sends without losing user work. — Product need: Clear single-step response to agent questions and preserve in-progress composer text. | inspected |
| REF-SHIFT-OPEN | screenshot | C:\Users\strenti\Pictures\Screenshots\Screenshot 2026-10-30 144706.png | Expanded subagent tab, transcript position. — Principle: Opening the panel must not move transcript content. — Product need: Stable chat position. | inspected |
| REF-SHIFT-CLOSED | screenshot | C:\Users\strenti\Pictures\Screenshots\Screenshot 2026-10-30 144658.png | Closed subagent tab, transcript position. — Principle: Opening the panel must not move transcript content. — Product need: Stable chat position. | inspected |
| REF-MAX-CONTEXT | repository | https://github.com/indie-arch/max-context | Configurable soft context limit, proactive compaction after a completed prompt, pending-input safety and failed-compaction loop prevention. — Principle: Context limits must affect runtime compaction, not just usage display. — Product need: Workspace controls for maximum context and reserve percentage while respecting model capabilities and pricing tiers. | inspected |
| REF-013 | anti-reference | C:\Users\strenti\Pictures\pi-frame-design-inspo\AI_GENERATED_LOOK.png | Reject same-hue fill/outline/text applied everywhere; keep surfaces and labels independently readable and avoid generic AI dashboard polish. — Principle: Accent color is a signal for content/meaning, not a universal component paint; surfaces use tonal neutrals and quiet boundaries. — Product need: Improve scanability and product-specificity without recreating the monochrome, synthetic card/button aesthetic the user rejects. | anti-reference |
| REF-012 | interaction-inspiration/visual-inspiration | C:\Users\strenti\Pictures\pi-frame-design-inspo\Antigravity_chat.png | Compact activity timeline for reasoning, commands, tool calls and streaming steps; progressive disclosure of details; slim composer and low-scroll overhead. — Principle: Intermediate agent activity should summarize into dense, low-height rows; expand only when user asks for detail, keep final answer primary. — Product need: Reduce scroll length and jitter in long Pi sessions while preserving inspectable reasoning, command output and tool results. | inspected |
| REF-011 | visual-inspiration/platform-reference | C:\Users\strenti\Pictures\pi-frame-design-inspo\VSCODE_UI.png | Selective color sparks, dense but legible explorer/chat/status hierarchy, compact toolbar and composer placement. — Principle: Use distinct semantic palette accents to make code, status and controls scannable; color should explain content, not merely decorate borders and fills. — Product need: Make repository paths, code tokens, tool states and chat controls easier to parse without increasing wasted space. | inspected |
| REF-010 | palette / theme reference | themes/piframe-dark.json; themes/piframe-light.json | Official PiFrame Dark and PiFrame Light normative theme tokens. PiFrame Dark (#161c27) and PiFrame Light (#f1f3f7). — Principle: Direct mapping of theme tokens to surface, chassis, text, accent (#5f9fc5 / #24638a) and semantic states. — Product need: Provide ergonomic, high-contrast default dark and light themes with full JSON theme customization. | inspected |
| REF-009 | existing rendered UI screenshots | apps/pi_frame/.impeccable/review/precision/overview-light-1440.jpg; apps/pi_frame/.impeccable/review/precision/dark-1440-workspace.png; apps/pi_frame/.impeccable/review/precision/dark-390.png | Established app information architecture, actual session surface and responsive affordances; do not treat as new build output for this intake. — Principle: Session navigation, transcript and workspace controls persist across wide and compact layouts; focus remains on actual agent content. — Product need: A user should monitor and operate sessions from desktop and narrow client widths without losing essential controls. | inspected |
| REF-008 | superseded historical visual reference | https://www.vitsoe.com/us/about/good-design; archived product images in `apps/pi_frame/.impeccable/research/round2/` | Historical D6 input only. D9 round 4 explicitly removes this design language from the active direction; do not reuse its shape, palette or composition. | anti-reference |
| REF-007 | superseded historical visual reference | Archived `apps/pi_frame/.impeccable/research/round2/` captures and former source URLs | Historical D6 input only. D9 round 4 explicitly removes this design language from the active direction; do not reuse its visual style. | anti-reference |
| REF-006 | user-selected spatial/layout reference | design references/VisualStudioCode-Bento-Layout.png | Three-area inspiration: chat, opened-repository files, Git Changes. Use Bento grouping and compartment hierarchy; do not copy VS Code branding or exact chrome. Palette is now independently governed by user-selected REF-010. — Principle: Keep related work surfaces visible and legible together. — Product need: Users should interact with Pi sessions while seeing repository files and changes. | inspected |
| REF-005 | historical palette reference | DR10–by Matus Hatala.pdf; apps/pi_frame/.impeccable/research/palette-1.png | Historical D6 palette reference; distinguish source swatches from semantic values. Its former DR10 direction was explicitly superseded during D9 by REF-010 (PiFrame Light / Dark). — Principle retained: status colors convey actual state, never decoration. — Product need: maintain readable contrast and semantic cues in the user's latest selected palette. | inspected |
| REF-004 | historical design records | apps/pi_frame/.impeccable/research/round2/ and `apps/pi_frame/.impeccable/surfaces/` | Historical D6 proposal and approval record only; superseded by explicit D9 rounds 2 and 4. Do not use prior surface language as current styling guidance. | inspected |
| REF-003 | app-level design contract | apps/pi_frame/DESIGN.md | Implementation-level PiFrame Dark and PiFrame Light and whole-app surface rules, maintained under this root contract. — Principle: align Flutter components to the current user-selected palette and surface grammar. | inspected |
| REF-002 | product brief | apps/pi_frame/PRODUCT.md | Primary user, core job, outcome, context, non-goals and hard constraints. — Principle: PiFrame is a desktop/web GUI over a local daemon, not an agent runtime or session-history owner. — Product need: Users want GUI affordances for Pi's sessions, transcripts, tools, workspace and extension prompts. | inspected |
| REF-001 | product and architecture brief | README.md | Product purpose, primary users, supported platforms, work continuity, session ownership, security and feature scope. — Principle: GUI can disconnect while Pi work persists; Pi remains history authority; daemon supplies local reconnect and event replay. — Product need: Make ongoing Pi coding work visible and manageable without taking ownership of sessions or depending on continuous GUI availability. | inspected |
<!-- Add real references here. Do not count examples/placeholders as references. -->

### Reference precedence

When sources conflict, use this order:

`explicit user constraint → product truth → platform/accessibility requirement → established brand/system → selected visual direction → inspiration`

Inspiration never overrides an explicit product, accessibility, platform, or functional requirement.

### Reference analysis notes
Product, interaction, visual intent and constraints are separated in the synthesis below. User selects REF-006's Bento spatial grouping, with PiFrame Light and Dark and rounded, lightly bordered surfaces across both panes and the rest of the interface. Preserve PiFrame identity; do not copy VS Code branding or exact chrome. REF-010 replaces the prior palette. REF-007/008 are archived anti-references and have no active design influence. References REF-001–REF-010 are registered; all are resolved.

### Reference conflicts

Record conflicts as:

`[CONFLICT-ID] competing principle → decision → precedence reason`

---

- **CONFLICT-001 — platform metadata:** `PRODUCT.md` metadata says Web; its body, root README and approved direction state Windows/macOS/Web. User selected equal priority; keep all three and reconcile stale metadata.
- **CONFLICT-002 — VS Code reference scope:** user wants Bento compartment organization and has specified its surface principles (separated, subtly bordered, rounded work areas); preserve PiFrame identity and do not copy VS Code branding or exact chrome.
- **CONFLICT-003 — Retired external design language:** user explicitly removed former product-design inspirations from the active direction; preserve PiFrame's original mark and use REF-010 for all theme colors.
- **CONFLICT-004 — prior single-transcript topology vs Bento request:** latest explicit user request uses chat, editable session-repository files and Git Changes as three work areas, with a consistent rounded/bordered grammar across the rest of the app. REF-010 supersedes the former palette.
- **CONFLICT-005 — inspect-only Git vs IDE-like change workflow:** user now requests unified changed-file list, diff-on-select, per-file stage/undo and truthful agent/manual provenance. Inspect-only status is insufficient; provenance feasibility must be verified before labeling.
- [CONFLICT-REF-010] **CONFLICT-006 — D9 visual revision:** user replaces former palette and square pane grammar with PiFrame Light / Dark and rounded, subtly bordered surfaces throughout the app. Preserve PiFrame identity; Bento remains spatial grouping only.
- **CONFLICT-007 — D9 round-4 palette/surface correction:** theme names claimed PiFrame while several Latte semantic values remained custom/off-palette, and non-pane UI remained square/flat. Latest feedback requires official palette colors and shared rounded borders beyond the Bento panes.
- [CONFLICT-CONFLICT-007] Documented in DESIGN.md §00.1 conflicts and D9 round-4 design decision.
- [CONFLICT-REF-011] **CONFLICT-008 — VS Code inspiration vs PiFrame identity:** user wants colorful semantic sparks for file icons, syntax and status like VS Code (`VSCODE_UI.png`), without copying VS Code branding, window chrome, or proprietary elements. Precedence: adopt semantic icon coloring and dense, scannable hierarchies while maintaining PiFrame's custom Bento shell.
- [CONFLICT-REF-012] **CONFLICT-009 — Dense activity rows vs bulky tool cards:** prior tool/reasoning blocks used large nested cards that caused excessive vertical scrolling; Antigravity reference (`Antigravity_chat.png`) demonstrates compact, inline summary rows (~26-28px) with status icons that expand on demand. Precedence: implement compact collapsible rows as default, keeping primary answer text prominent.
- [CONFLICT-REF-013] **CONFLICT-010 — Anti-reference AI-generated styling:** reject the monochromatic "AI-generated" look (`AI_GENERATED_LOOK.png`) where boxes use same-hue background, lighter outline, and colored text. Precedence: containers use neutral surface backgrounds and subtle borders; color is strictly reserved for semantic indicators (file types, git status, active states, syntax).
## 00.2 User-provided visual / file inputs

The Design Director should be able to work from:

- URLs;
- image files;
- screenshots;
- PDFs;
- written briefs;
- product documentation;
- competitor references;
- existing design files exported to accessible formats;
- recordings or walkthrough descriptions when available.

### Input checklist

- [x] References collected
- [x] References actually inspected
- [x] Important source content summarized
- [x] Inspiration separated from hard constraints
- [x] Anti-references captured
- [ ] Conflicts resolved (platform metadata mismatch remains open)
- [x] Evidence registry updated

Do not claim that a reference was inspected when it was not accessible.

---

# 00.3 Adaptive discovery interview

> The Design Director uses a bounded adaptive interview rather than a fixed questionnaire. Candidate questions are ranked by expected information gain: impact × uncertainty × dependency × answerability × novelty, with a small boost for blocking decisions. The agent asks only the top 1–3 questions per round and stops when readiness reaches the project threshold with no blocking gaps.

<!-- DD_INTERVIEW_STATUS_START -->
### Current interview status

**Status:** complete
**Readiness:** 100% (target 86%)
**Recommendation:** ready
**Round:** 5
**Questions asked:** 10
**Questions answered:** 10
**Blocking gaps:** 0
**Why / remaining gaps:** No material discovery gap detected

| ID | Category | Score | Blocking | Status | Question |
|---|---|---:|---|---|---|
| Q-SCOPE | scope | 100 | yes | answered | Is this discovery meant to establish PiFrame's overall product/UI contract, or focus on a specific session-workflow change in the current branch? |
| Q-FILE-VIEW | file pane behavior | 100 | yes | answered | Should repository files support read-only browsing/preview, or direct editing and saving from PiFrame? |
| Q-VISUAL-DIRECTION | visual direction | 100 | yes | answered | Which visual composition should lead exploration: Bento Triptych, Artifact Atlas, or Conversation Desk? |
| Q-COLD-TITLE | product-fidelity | 100 | yes | answered | Quando manca un titolo nell'indice, preferisci mostrare subito un ID provvisorio o attendere il titolo esatto? |
| Q-FLOW | critical flow | 93 | yes | answered | Which session workflow should define the critical path: resume/reconnect ongoing work, find and switch sessions, branch/fork/clone, or protect uncertain/shared sessions? |
<!-- DD_INTERVIEW_STATUS_END -->

# 00.4 Discovery synthesis (generated)

> This section is the first usable Design/UX/Product brief produced during D0–D4. It is written by the Design Director from user input, repository evidence, supplied references, and explicit assumptions. It is not a visual style board and it is not a substitute for the detailed sections below.
>
> Each subsection should carry confidence and evidence provenance. Unresolved consequential decisions belong in Open decisions, not hidden in prose.

## design brief
<!-- DD_SYNTHESIS_START:design_brief -->
### design brief

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-005, REF-006

**PiFrame** is a Flutter desktop/web companion for Pi coding-agent users. Scope includes session discovery/switching, Pi session health/metrics, repository editing, Git review/actions, context attachments and Pi package management while Pi remains session-history owner. Bento Triptych remains the spatial direction: repository/editor, Pi chat and Git Changes co-visible on wide layouts. D9 feedback selects official PiFrame Light / Dark colors and a consistent rounded, subtly bordered surface grammar throughout panes, settings, sessions, chat, composer, dialogs and controls. The retired D6 palette and creative references are not active guidance. Compact layout remains adaptive and state-preserving. **Confidence: high.** Evidence: REF-001, REF-002, REF-006, REF-010; Q-VISUAL-DIRECTION/Q-D6-LOCK; D9 human review rounds 2 and 4.
<!-- DD_SYNTHESIS_END:design_brief -->

## evidence synthesis
<!-- DD_SYNTHESIS_START:evidence_synthesis -->
### evidence synthesis

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-003, REF-004, REF-005, REF-006, REF-007, REF-008, REF-009

**Product truth:** PiFrame GUI for Pi coding-agent users; Pi owns session history and local daemon preserves process/replay continuity. **Interaction truth:** equal Windows/macOS/Web priority; keyboard+pointer; session tree groups by repository/folder, and selected folder can seed new-session cwd; worker sessions are hidden by default. Chat shows Pi model/thinking/context/cost metadata and accepts file/line references. Repository and Git review are unified around changed tracked files, diffs, explicit stage/undo, with agent/manual provenance. Panels are resizable/hideable; settings expose installed Pi package lifecycle. **Visual intent:** retain Bento spatial grouping; use exact PiFrame Light / Dark palette values and extend consistent modest rounding/subtle borders to non-pane UI. Retired D6 palette and design references must not shape implementation. **Constraints/conflicts:** local-only/no telemetry; preserve Pi's session and package ownership; maintain explicit, safe Git writes; REF-010 governs palette. Product metadata still says Web-only despite user-confirmed platform parity (CONFLICT-001). **Confidence: high** for user requests; exact use of palette accents must preserve text contrast. Evidence: REF-001–REF-010; D9 human review rounds 2 and 4.
<!-- DD_SYNTHESIS_END:evidence_synthesis -->

## product brief
<!-- DD_SYNTHESIS_START:product_brief -->
### product brief

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-006

**Product/app:** PiFrame, GUI companion for Pi coding-agent. **Primary user:** Pi coding-agent/CLI users; user wants balanced speed and discoverability. **Core job:** find/switch sessions by repository, follow Pi work and manage source/Git context without losing Pi-owned history. Requested outcomes now include folder-scoped session creation, a repository-grouped session tree without worker# noise, in-chat session metrics, editable files and diff-first Git operations, file/line context attachments, resizable panes and Pi package lifecycle controls. **Priority:** continuity, safe explicit changes, local privacy and an integrated IDE-like workbench. **Confidence: high** for requested scope; implementation/API feasibility remains open. Evidence: REF-001, REF-002, REF-006, REF-010; D9 human review round 2.
<!-- DD_SYNTHESIS_END:product_brief -->

## interaction brief
<!-- DD_SYNTHESIS_START:interaction_brief -->
### interaction brief

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-003, REF-004, REF-005, REF-006

**Platforms:** Windows desktop, macOS desktop and Web at equal priority; iOS/Android out of scope. Windows keeps native caption/window actions, macOS keeps native window conventions, Web remains served from the local daemon origin with browser controls. **Primary input:** keyboard + mouse/pointer; standard text editing, visible focus, keyboard navigation and explicit pointer controls. Existing shortcuts: Ctrl/Cmd+K command palette, Ctrl/Cmd+Enter send, Escape interrupt. New editor shortcuts remain to be designed, not assumed.

**Workspace model:** Session index groups sessions by repository/folder, suppresses `worker#` subagent entries by default, and lets users create a session from a selected folder. Bento work areas are resizable/hideable; compact layout retains explicit pane switching and state. **Repository/Git:** show changed tracked files, distinguish agent/manual origin when evidence permits, select a file to view its diff, offer per-file stage and undo, and keep writes explicit/recoverable. **Chat context:** allow file attachments and line-specific references from editor selection/context menu; show model, thinking, context-window and cost metadata plus supported Pi package controls. **File safety:** edits stay inside active session repo, dirty buffers survive panes, external conflicts preserve both versions, and session switches resolve dirty files before changing cwd. **Git safety:** undo/discard names the exact file and confirms destructive loss; stage/commit are explicit and guarded against active Pi writes. **Accessibility:** keyboard/focus, semantics, large text and contrast must be tested before claiming complete.

**Confidence:** high for direct user constraints and platforms; medium for these safety/adaptive decisions. Evidence: REF-001–REF-006; Q-PLATFORM, Q-FILE-VIEW, Q-REPO-CONTEXT, Q-GIT-ACTIONS; current `app_shell.dart`, `context_panel.dart`, root README and daemon `gitClient.ts`.
<!-- DD_SYNTHESIS_END:interaction_brief -->

## ux flow brief
<!-- DD_SYNTHESIS_START:ux_flow_brief -->
### ux flow brief

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-006

**Primary critical flow: Find/switch session and resume project work**

**User intent:** Return to intended Pi conversation and continue in correct repository without losing history or edits.

**Start state:** Launch/reopen at session index; daemon connected, reconnecting or unavailable; session list populated, empty or loading.

**Main path:** Browse/search sessions grouped by repository/folder (worker# rows hidden by default) → select session or choose folder for new session → verify title/cwd and read-only/agent state → inspect Pi chat metrics, repository/editor and unified Git Changes → select changed file for diff → edit/save or stage/undo explicitly; add files/selected line ranges to chat context when needed.

**Alternative paths:** No match → reset filters or create session. No Git repo → chat remains usable; explain unavailable panes. Read-only/ambiguous session → allow safe inspection but disable repository writes. Compact width → explicit pane switcher preserves state.

**Errors / interruption / recovery:** Daemon failure → retry/reconnect; journal gap → fresh snapshot; worker crash → explicit recovery, no blind replay; filtered empty → reset. Save failure retains dirty buffer; concurrent file change preserves both versions and offers compare/reload/keep. Dirty session switch/window close offers Save / Discard / Cancel. Git failure retains selection/state; refresh before writes; discard previews and confirms target; serialize/reject writes racing active Pi changes.

**Completion:** Correct session identity/cwd and transcript visible; file/Git panes match cwd; save/Git result explicit.

**Success signal:** Intended context reached; Pi history gap-free; no silent overwrite or hidden Git mutation.

**Exit:** Continue chat/editing, switch pane, return to session list or close after resolving dirty buffers.

**Secondary flows — repository/Git and context:** Select modified tracked file → inspect diff → stage with per-file plus or undo after impact/confirmation; preserve agent-vs-manual provenance when protocol provides it. Select file or source lines → Add to chat with stable path and line range. Settings show installed Pi packages with individual update/remove/pin actions, subject to Pi CLI/package APIs.

Design hypothesis: wide workspace exposes three Bento work areas; compact layout uses explicit pane switching and preserves state. Current app has session search and read-only Git status/diffs only; editor/Git writes are new scope. No destructive action is automatic. Confidence: high for user-selected task/scope; medium-high for safety. Evidence: REF-001, REF-002, REF-006; Q-FLOW/Q-FILE-VIEW/Q-REPO-CONTEXT/Q-GIT-ACTIONS; `sessions_sidebar.dart`, `app_shell.dart`, `composer.dart`, `context_panel.dart`, daemon `gitClient.ts`.
<!-- DD_SYNTHESIS_END:ux_flow_brief -->

## design implications
<!-- DD_SYNTHESIS_START:design_implications -->
### design implications

**Confidence:** high
**Evidence:** REF-003, REF-004, REF-005, REF-006, REF-009

**Bento remains the spatial grouping, not a pane-only skin.** Apply the exact named PiFrame Dark and PiFrame Light colors from `themes/piframe-dark.json` and `themes/piframe-light.json`. Where an accent cannot carry small text accessibly, pair it with named text/surface colors and use the accent for icons, borders or tinted state surfaces. Use modest radii and 1px subtle borders for other functional surfaces too: session rows, message/tool/code blocks, composer, settings cards, inputs, dialogs and menus. Preserve PiFrame identity and avoid copying VS Code chrome. Minimize/maximize stalls are reported improved; keep transcript lazy layout. **Confidence: high** for explicit direction; exact component sizes remain implementation choices. Evidence: `themes/piframe-dark.json`, `themes/piframe-light.json`; D9 review rounds 2 and 4.
<!-- DD_SYNTHESIS_END:design_implications -->

## constraints non goals
<!-- DD_SYNTHESIS_START:constraints_non_goals -->
### constraints non goals

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-003, REF-004, REF-005, REF-006

**Hard constraints:** Windows/macOS/Web equal priority; local loopback daemon/token/origin security; zero remote telemetry; Pi owns session history and package lifecycle; preserve replay, drafts, queues, read-only safeguards and extension UI; keep Italian UI and original PiFrame identity. Default requirements: exact PiFrame Dark and PiFrame Light palette; rounded, subtly bordered surfaces across the whole application; resizable/hideable Bento panes; repository-grouped non-worker sessions and folder-scoped creation; visible Pi metrics; integrated diff-first Git Changes with explicit stage/undo and truthful origin labels; file/line-to-chat context; Pi package management. Preserve dirty buffers, confirm destructive undo, and guard writes against active Pi changes. **Non-goals:** changing Pi session/history ownership; remote/cloud repo access or telemetry; iOS/Android; copying VS Code branding/exact chrome; reactivating retired D6 design references; auto-stage/commit or hidden data loss. **Confidence: high** for requested outcomes. Evidence: `themes/piframe-dark.json`, `themes/piframe-light.json`; D9 review rounds 2 and 4.
<!-- DD_SYNTHESIS_END:constraints_non_goals -->

## open decisions
<!-- DD_SYNTHESIS_START:open_decisions -->
### open decisions

**Confidence:** high
**Evidence:** REF-001, REF-002, REF-003, REF-004, REF-006

1. **Platform metadata:** `apps/pi_frame/PRODUCT.md` frontmatter says Web while body/README/design history and user decision specify equal Windows/macOS/Web; preserve parity and reconcile when product docs are next edited (CONFLICT-001).
2. **Quantitative business success metric:** none supplied; qualitative outcomes remain correct session context, safe file/Git changes and continuous Pi history.
3. **Runtime after user restart:** previous `daemon.json` still names PID 40604, which is no longer running. Launch the rebuilt app and confirm it starts a fresh daemon before testing workspace/package commands.
4. **Change provenance:** Git can report changed paths/status but agent-vs-manual authorship may not be derivable from current snapshots. Investigate Pi/daemon write provenance; never guess labels.
5. **Pi package lifecycle runtime:** user-scope list/update/remove/pin implementation and isolated tests exist; confirm the restarted app's live daemon can list packages before human review.
**Direction lock:** Bento Triptych spatial topology remains. D9 user explicitly revised palette and shape (REF-010; rounded PiFrame Dark and PiFrame Light compartments); this is a user-directed refinement, not permission to clone IDE branding.
<!-- DD_SYNTHESIS_END:open_decisions -->

## assumptions
<!-- DD_SYNTHESIS_START:assumptions -->
### assumptions

**Confidence:** medium
**Evidence:** REF-001, REF-002, REF-003

**Resolved by user:** balance throughput and discoverability; repository files are editable/saveable; file/Git context follows active session cwd; Git Changes supports stage/commit/discard. Treat these as explicit product requirements, not assumptions.
- **A-002 — Keyboard + mouse/pointer is primary across desktop and Web.** Inferred from platform scope, composer, command shortcut and window controls; no mobile-native target. Risk: browser sessions on touch devices may need more touch adaptation. Evidence: REF-001–REF-003.
- **A-003 — Local developer workstation and intermittent session monitoring are typical.** Inferred from Pi coding-agent context and persistent daemon/reconnect architecture; exact cadence/time pressure is unknown. Risk: remote/shared environments could change recovery and collaboration needs. Evidence: REF-001, REF-002.
**Design Director decisions, not user questions:** protect dirty buffers; Save / Discard / Cancel before losing edits; compare/reload/keep on external conflicts; refresh and identify targets before writes; commit reviewed staged files only; preview/confirm discard; adapt three areas across widths. Exact copy and implementation mechanics remain for later design/build. No demographics or business metrics invented. **Confidence: medium.**
<!-- DD_SYNTHESIS_END:assumptions -->

### A-001
Resolved by user Q-USER: balance high-frequency throughput with discoverability for occasional users; no assumption remains about which group dominates.
### A-002
Inferred from target platforms and source; documented as assumption, not user-confirmed input preference.
### A-003
Reasonable inference from local coding-agent use and daemon continuity architecture; exact cadence remains unknown.
## Discovery synthesis status
<!-- DD_SYNTHESIS_STATUS_START -->
**Synthesis status:** complete
**Finalized:** 2026-10-06T15:01:46.771Z
**Reason:** Re-finalize all nine discovery synthesis sections after recording the locked direction and D8 implementation evidence; no feature code beyond authorized D8.
<!-- DD_SYNTHESIS_STATUS_END -->

---

# 01. Product truth

## What the app does

Current client provides GUI session discovery/operation, streaming transcript, prompt/steer/interrupt, workspace Git status/diff and extension UI; a local daemon preserves execution/replay across GUI disconnects. **User-requested expansion:** active-session repository files must be editable/saveable, and Git Changes must support stage/commit/discard actions alongside Pi chat. These editor and Git write capabilities are not present in current feature code reviewed.

## What the app does not do

It does not replace Pi, own Pi's session files/history, run the agent inside Flutter, send remote telemetry, or target iOS/Android. It does not blindly replay uncertain commands after a daemon identity change.

## Core entities / objects

Pi session and branch/tree; user/assistant messages; reasoning and tool events; queued steer/follow-up prompts; active-session repository tree, editable file and dirty buffer; Git changed-file/staged state, diff and commit; model/thinking settings; daemon connection, snapshot and replay cursor; extension UI request.

## User goals

| Goal | Priority | Frequency | Success signal |
|---|---|---:|---|
| Find/switch Pi sessions, edit session-repository files and manage Git changes | P0 | Recurring; exact cadence unknown | Correct session context; edits save safely; Git writes are explicit; no history loss/duplicate replay |

## Critical scenarios

- User launches/reconnects client to local daemon and resumes session from replay/snapshot.
- User creates/selects a session, follows streamed text/tool work, sends or steers a prompt, and interrupts safely.
- User encounters a session already possibly open in terminal and uses read-only/clone/explicit-confirm recovery rather than concurrent writes.
- User edits and saves a repository file alongside Pi chat; app must preserve unsaved content and resolve concurrent agent/external edits safely.
- User stages/commits/discards Git changes after editing a file; target and consequences remain clear and failures recover safely.
- User inspects workspace diff or Pi extension request; handles empty, daemon-disconnected and worker-failed states.

## Content reality

Document realistic:

- minimum content;
- typical content;
- maximum / extreme content;
- missing content;
- user-generated content;
- localized content;
- sensitive / high-stakes content where applicable.

Sessions contain user prompts, streamed assistant text, reasoning, tool arguments/output, code, diffs, queue state, branch/session metadata, model settings and extension UI payloads. Content length and session history can grow; exact production maxima are not documented. Names, previews, cwd and model data can be missing. Existing UI copy is predominantly Italian. Session history and workspace details are developer data; preserve Pi ownership and avoid exporting secrets in diagnostics.

---

# 02. Interaction environment

The interface must be designed around the actual input/output environment.

## Target platforms

- [ ] iOS
- [ ] Android
- [ ] iPad/tablet
- [x] macOS
- [x] Windows
- [ ] Linux
- [x] Web
- [ ] Other: not identified

Windows, macOS and Web have equal priority by user choice; PRODUCT.md frontmatter conflicts with other project evidence (CONFLICT-001).

## Primary input

Keyboard + mouse/pointer on desktop/Web; desktop keyboard shortcut and text-composer paths are explicit in source. No mobile-native or touch-first target is established.

### Pending agent questions

A pending agent question owns the response flow: hide and disable the normal composer, preserve its unsent draft unchanged, and restore it after the question is resolved. Selecting `Type something` replaces its label with a focused text field in the same list; the other options remain directly selectable, and returning to the field preserves the typed answer. Ordinary custom answers are submitted once. For RPC responses that would otherwise be mistaken for an option, PiFrame uses Pi's follow-up input; do not show a dynamic warning while the user is typing.

## Input behavior

Document:
- tap / press;
- long press;
- drag;
- swipe;
- scroll;
- hover;
- secondary click;
- keyboard shortcuts;
- focus traversal;
- text selection;
- pointer precision needs;
- Gesture cancellation/interruption: keyboard actions remain immediate; inspector motion is interruptible and reduced-motion aware per approved app direction.

Keyboard + pointer for session search/selection, chat composition, repository tree navigation and editing. Preserve Ctrl/Cmd+K command palette, Ctrl/Cmd+Enter send and Escape interrupt. Editor uses standard text-editing keys; ensure focus can move among chat, file tree/editor and Git Changes without trapping. Git actions show repository/branch and exact file targets; discard previews impact and requires confirmation; commit operates on reviewed staged files. Dirty buffers survive pane changes; session switch/window close offers Save / Discard / Cancel. External file changes preserve the user's buffer and offer compare/reload/retry. Windows keeps integrated drag/standard window actions; macOS native window behavior; Web follows browser keyboard/navigation conventions. Full accessibility QA remains pending.

## Primary output

Desktop monitor or browser window. Wide layouts expose chat, repository tree/editor and Git Changes together; compact layouts keep chat primary and provide explicit pane switching/drawers with per-pane state preserved. Screen-reader and large-text validation remain pending.



## Context of use

Local developer workstation. User may monitor a long-running Pi task intermittently, edit repository files while Pi is active, or lose the GUI/daemon connection. Session cwd binds repository context; Pi work remains replayable. User prefers balanced throughput and discoverability. Exact work cadence/time pressure remains unknown.

Consider:
- one-handed use;
- standing / moving;
- bright outdoor light;
- low-light environment;
- noisy environment;
- intermittent connectivity;
- time pressure;
- frequent/repetitive operations;
- expert users;
- novice users.

## Platform conventions

The Design Director must document where the app follows platform norms and where it intentionally deviates.

### iOS
Out of scope; no iOS-specific interface.

### Android
Out of scope; no Android-specific interface.

### Desktop / web
Preserve platform-native window behavior; Windows integrated caption actions, macOS native titlebar, Web browser conventions. Use Ctrl/Cmd variants for shared shortcuts. Web is served from the local daemon origin. Equal platform priority means feature parity, not identical pane layout at every width.

### Shared behavior
Selected session cwd defines file tree and Git Changes. Wide workspace presents chat, editable file area and Git Changes as distinct panes; compact workspace exposes explicit pane switcher/drawers, keeping chat default and preserving pane state. Dirty edits require save/discard/cancel before session-context loss; stale files cannot silently overwrite; Git mutations identify exact repository/files and result.

---

# 03. Information architecture & flow model

## Primary navigation

Session index → active-session workspace. Wide workspace shows Pi chat + editable repository files + Git Changes; compact layout switches among these areas without losing state. Repository context follows active session cwd; settings and command palette remain global utilities.

## Top-level destinations

Sessions, Pi chat/transcript/composer, editable opened-repository files, Git Changes, workspace/model details, settings/diagnostics.

## Entry points

Launch/reopen PiFrame; connect to daemon; open the session index; select an existing session or create one. No deep-link route is established by current evidence.

## Exit points

Switch session, open settings/workspace, or close/reload GUI. Closing GUI must not be represented as stopping Pi work; daemon keeps running.

## Back behavior

Use platform dismissal/back behavior for drawers and dialogs; session switching returns focus to selected transcript. No browser deep-link/back contract is documented.

## Deep links / notifications / external entry

No supported deep-link, notification or external session-entry path identified.

---

## Critical flow: Find and switch sessions

### User intent

Return to the intended Pi conversation or switch into another existing session without losing its identity or history.

### Start state

PiFrame is open at the session index; daemon may be connected, connecting or reconnecting. The user recognizes a project/session name, cwd or recent preview. List may be populated, empty, loading or unavailable.

### Main path

Search/filter by name, ID, cwd, preview or activity; select a session; verify title/cwd and read-only/agent state; active cwd becomes repository root; inspect chat, repository tree/editor and Git Changes; read/edit/save a file; refresh status/diff; optionally stage explicit files, commit reviewed staged files with message, or preview and confirm discard.

### Alternative paths

No match → clear/reset filters or create a session; no Git repository → keep chat usable and explain unavailable file/Git areas; read-only/ambiguous session → allow safe browsing but disable repository writes until ownership is safe; compact width → explicit pane switcher/drawers preserve file and scroll state.

### Errors / interruption / recovery

Daemon unavailable → retry/reconnect while Pi history remains authoritative; journal gap → fresh snapshot; worker failure → explicit recovery, no blind command replay; ambiguous terminal session → read-only explanation/clone or confirmed safe continue; filtered empty → reset. Save failure → retain dirty buffer and retry; concurrent file edit → preserve both and compare/reload/keep; dirty session switch/app close → Save / Discard / Cancel. Git failure → keep selection/status and report operation; refresh before writes; discard previews targets and requires confirmation; stale writes during active Pi work are serialized or rejected.

### Completion

Target session becomes active; its identity and cwd are visible, Pi-owned transcript is current, and repository files plus Git Changes reflect that session before further edits or Git actions.

### Success signal

User reaches intended session, can chat/edit/review Git changes in its repository, and has clear unsaved/staged state without history gaps, duplicate events or hidden repository writes.

### Known friction

Current app has session filters/search and read-only Git status/diffs but no editor or Git write actions. Verify filtered-empty recovery, correct session/repository association, unsaved-file recovery and safe Git mutation feedback.

### Design hypothesis

Keep search/filters adjacent to session index; selected session identity determines file/Git context; organize chat, editable files and Git Changes as distinct related areas; balance routine speed with visible affordances; distinguish filtered-empty from lost/unavailable session; preserve dirty edits and make Git writes explicit. Adapt three areas across widths while keeping each reachable. Based on user answers, reference and existing implementation, not usability-test evidence.

## Secondary flow: Edit a repository file and manage its Git change

### User intent
Edit source in active Pi session's repository, understand resulting change, and apply only intended Git operations.

### Start state
Selected session has a canonical repository root; file pane shows repository tree; session may be idle or Pi may be working.

### Main path
Select file → edit in buffer → save explicitly → refresh Git status/diff → review exact file and diff → stage/unstage selected file → optionally commit reviewed staged files with explicit message.

### Alternative paths
Close or switch pane with editor state preserved; session switch or window close while dirty offers Save / Discard / Cancel; no repository or unsupported file type leaves chat usable and explains limit.

### Errors / interruption / recovery
Save failure keeps buffer; external/Pi edit conflict offers compare/reload/keep; stale Git status refreshes before write; commit failure retains staged selection/message; discard shows affected files/diff and requires confirmation; concurrent worker mutation is serialized or rejected, never silently raced.

### Completion
Saved file appears in Git Changes with accurate status/diff; staged/committed/discarded action reports actual result.

### Success signal
No silent overwrite or mutation; user can identify repository, branch, files and saved/staged state.

### Known friction
Current client has no source editor or Git write API. File-root containment, dirty-buffer recovery and safe worker concurrency require implementation design.

### Design hypothesis
Keep editor state alive across pane changes; stage/commit/discard target explicit files; commit staged files only; make destructive discard previewable; block writes outside active repository root.

---

# 04. UX principles

These are product-specific principles, not generic slogans.

### Principle 1
**Session is context boundary:** active session identity and cwd govern chat, repository files and Git Changes; never hide context switches.

### Principle 2
**Chat, code and changes are peers:** three clear work areas; selected Bento Triptych keeps each role legible and related.

### Principle 3
**Every write is accountable:** edits, staging, commit and discard name their targets, preserve recoverable state and report results.

### Cognitive load
Balance throughput and discoverability. Keep current session/repository and dirty/staged state visible; avoid duplicating metadata across panes.

### Progressive disclosure
Keep session search, chat and file navigation direct. Show Git write actions in Git Changes, but require explicit selection and reveal consequences before commit/discard.

### Feedback & system status
Distinguish daemon connection, Pi run state, file saved/dirty/conflict state, Git staged/unstaged state and operation result with text/icon and color.

### Errors & recovery
Preserve buffers and selections on save/Git failures. Compare/reload/keep on disk conflict; Save / Discard / Cancel before losing dirty edits; never replay uncertain agent commands.

### Empty states
Differentiate no sessions, no search results, no Git repository, clean Git tree, and no file selected. Offer a specific next action without theatrical illustration.

### Onboarding / first value
No onboarding ceremony. First value is selecting a real session and immediately seeing its chat, cwd-bound repository and Git state.

### Expert workflows
Keep keyboard search, editing and chat paths efficient; preserve per-session drafts and editor state across pane changes. Do not require mouse-only Git actions.

---

# 05. Visual world

## Creative North Star

**A session-bound coding workbench:** keep Pi conversation, active-project files and change consequences in one coherent working field. Each surface has a clear job; no file or Git write is hidden.

Bento defines spatial grouping, not a styling rule limited to the three panes. Use PiFrame Dark and PiFrame Light colors and a consistent soft-rounded, subtly bordered grammar across the whole app. Preserve PiFrame's own mark and name.

## Emotional character

- Precise
- Composed
- Discoverable
- Accountable

## Visual ingredients

### Color world
Use official PiFrame default themes from `themes/piframe-dark.json` and `themes/piframe-light.json`.
- **PiFrame Dark**: Background `#161c27`, Chassis `#121721`, Surface `#1c2432`, Elevated Surface `#242e40`, Display Surface `#242e40`, Display Text `#f1f5f9`, Border `#2e3c53`, Strong Border `#475a77`, Text Primary `#f8fafc`, Text Secondary `#a3b2c5`, Text Muted `#8696ab`, Accent `#5f9fc5` (Steel Blue), Focus Ring `#5f9fc5`, Success `#a1d9b0`, Warning `#f6bd53`, Danger `#f1887a`, Info `#5f9fc5`, User Bubble `#21344a`, Thinking `#81b2cf`.
- **PiFrame Light**: Background `#f1f3f7`, Chassis `#e6e9f0`, Surface `#ffffff`, Elevated Surface `#ffffff`, Display Surface `#dae0ea`, Display Text `#0f172a`, Border `#d3dae4`, Strong Border `#a3afc1`, Text Primary `#0f172a`, Text Secondary `#3d4a5c`, Text Muted `#566376`, Accent `#24638a` (Deep Steel Blue), Focus Ring `#24638a`, Success `#336c42`, Warning `#895706`, Danger `#882316`, Info `#24638a`, User Bubble `#d3e3ef`, Thinking `#436e89`.

### Typography voice
Keep bundled Barlow Condensed for identity/headings, Schibsted Grotesk for UI reading, and Source Code Pro for file paths/code/diffs. Let source content carry visual interest; avoid decorative display use in dense editor content.

### Material / texture
Use one coherent surface family in both themes. Major panes, settings sections, composer, transcript blocks, tool/code surfaces, dialogs and input controls use a quiet 1px border, modest corner radius and clear spacing. Avoid bare square rectangles and near-black-only components in Light theme. Avoid glass, gradients, deep shadows and nested card stacks.

### Shape language
Semantic radii: 6px small, 10px medium, 14px large; pane gutters stay narrow. Rounded borders apply to functional non-pane surfaces too, without turning every row or label into a card.

### Density
Balanced: enough source/Git detail for frequent CLI users, with visible labels and recoverable controls for occasional users. Wide layouts expose three work areas; compact layouts switch panes without losing state.

### Image / illustration language
No decorative photography or illustrations on work surfaces. Real repository files, code, diffs and session content are primary visual material.

### Iconography
Use familiar software/action icons with labels or tooltips; status meaning never relies on color alone. Do not copy VS Code product marks or proprietary icon shapes.

### Motion language
Keep keyboard actions immediate. Use short, interruptible pane transitions and subtle pointer feedback only; preserve reduced-motion behavior. No decorative entrance loops or streaming text theatrics.

### Composition / grid
**Selected direction: Bento Triptych.** Keep session navigation distinct from three co-visible wide work areas: repository/editor, Pi chat and Git Changes. At compact/medium widths, chat is default and explicit pane switching exposes files or changes without losing state. Proportions remain a design-system refinement.

## Distinctive product signatures

- **Session-bound workspace:** one visible session identity/cwd anchors chat, files and Git state.
- **Change consequence:** selected file, saved/dirty state, staged state and diff remain visibly connected.
- **Explicit action grammar:** stage, commit and discard always name repository/target and show outcome.

## Anti-reference

No VS Code logo, copied chrome or exact component clone; no generic AI/SaaS card dashboard, nested cards, glass/gradients, fake hardware or hidden repository writes. Preserve original PiFrame mark; PiFrame Dark and PiFrame Light colors and semantic status cues are now normative.

---

# 06. Direction exploration

Use only for new products, major redesigns, or materially open visual direction.

## Candidate directions

These are historical D6 composition candidates. Round-4 direction keeps Bento spatial grouping and supersedes their palette and surface treatments with official PiFrame Dark and PiFrame Light colors and consistent rounded borders.

### Direction: Bento Triptych

**Thesis**  
Chat, repository files and Git Changes are three first-class work surfaces; session identity ties them together.

**Why this belongs to the product**  
Direct translation of the user request and REF-006 spatial grouping into PiFrame's own working grammar.

**Audience / cultural resonance**  
Balanced for frequent Pi operators and occasional users: clearly labeled panes, familiar session navigation and immediate cross-reference between agent, source and changes.

**Palette strategy**  
Official PiFrame Light / Dark semantic colors. Do not retain DR10 or custom contrast-shifted accent hues.

**Type strategy**  
Barlow Condensed for brand/pane headings; Schibsted Grotesk for controls and transcript; Source Code Pro for paths, source and diff.

**Shape/material strategy**  
Rounded, subtly bordered panes and functional surfaces across the app; tight gutters; flat surfaces without shadows or nested card stacks.

**Composition strategy**  
Session navigation remains a slim rail/drawer. Wide workspace: repository file tree/editor left (~30%), Pi chat center (~46%), Git Changes right (~24%). Compact: chat default with explicit Repository/Git Changes pane switcher; preserve editor and scroll state.

**Signature interaction**  
Selecting a file keeps session/chat in place and shows that file's saved/dirty and Git status in adjacent Changes pane; no hidden context switch.

**Honest risk**  
Four navigational regions including session index can crowd medium windows; needs careful minimum widths and compact pane switching.

**Anti-slop rationale**  
Every pane contains real session/repository data. Bento divisions encode distinct user jobs, not decorative cards or invented metrics.

### Decision

selected

### Reason

User chose Bento Triptych and explicitly confirmed the lock; `/design lock` persisted D6. It most directly satisfies three co-visible named work areas while preserving PiFrame identity.

### D9 human-review revision (active)

Keep Bento topology, not the retired D6 design language. Use official PiFrame Light / Dark values and extend modest rounding/subtle borders to non-pane UI. Remove former external creative references from active decisions; preserve PiFrame identity. Maintain the D9 session-tree, Git/diff, metrics, package-management, context-attachment and resizable-pane requirements. See rounds 2 and 4 in Human review log.

### Direction: Artifact Atlas

**Thesis**  
The source file is primary artifact; chat explains and changes ledger records consequences.

**Why this belongs to the product**  
Users need inspectable, editable repository files and safe Git operations alongside Pi's work; this composition foregrounds code and its history.

**Audience / cultural resonance**  
Frequent code-reading/editing users, while retaining discoverable chat/Git labels and stable session identity.

**Palette strategy**  
Would use the active PiFrame Light / Dark semantic pair; this alternative differs only in information priority and remains rejected.

**Type strategy**  
Source Code Pro takes more hierarchy in editor/file tree; Schibsted Grotesk carries transcript/controls; condensed Barlow remains brand-only.

**Shape/material strategy**  
Document-like open editor plane, fine line numbers and rules, restrained pane boundaries; diff uses explicit added/removed status colors and text labels.

**Composition strategy**  
Explorer/file tree left, broad editor center, Git Changes as a shallow bottom ledger, persistent chat column right. Compact layouts switch between source+changes and chat.

**Signature interaction**  
Selecting a changed path opens the working file while keeping its diff/status linked in the bottom Changes ledger.

**Honest risk**  
Chat may feel secondary to code editing, shifting PiFrame toward a full IDE and increasing scope.

**Anti-slop rationale**  
Hierarchy comes from actual code, path and diff semantics—not generic IDE chrome, decorative tabs or fake activity metrics.

### Decision

rejected

### Reason

User selected a balanced three-area Bento composition; code-first editor dominance would over-prioritize source editing.

### Direction: Conversation Desk

**Thesis**  
The live Pi conversation remains center of gravity; files and Git Changes are always nearby supporting instruments.

**Why this belongs to the product**  
PiFrame's primary job is still session interaction. User can inspect/edit source and manage changes without letting repository chrome overwhelm agent work.

**Audience / cultural resonance**  
Occasional users and balanced workflows; chat is immediately legible, while labeled file/Git surfaces remain reachable and visible on wide screens.

**Palette strategy**  
Would use the active PiFrame Light / Dark semantic pair; this alternative differs only in information priority and remains rejected.

**Type strategy**  
Schibsted Grotesk leads transcript/controls; Barlow Condensed marks session identity; Source Code Pro remains limited to source, path and diff.

**Shape/material strategy**  
Open conversation plane with a compact repository navigator and a crisp, narrow Git Changes ledger; thin dividers rather than tiles.

**Composition strategy**  
Chat receives the broad center (~55%); repository files sit as a left work pane and Git Changes as a right rail (~20–25%). Compact mode defaults to chat and uses clearly labeled pane switching.

**Signature interaction**  
A file/branch context label persists in the chat header; pane switches preserve conversation scroll and draft, making current repository explicit.

**Honest risk**  
Editor and Git Changes may be too narrow for long paths, code and staged-file review; could bias product away from the user's three first-class areas.

**Anti-slop rationale**  
Conversation hierarchy is caused by PiFrame's core job; no chat bubbles, generic AI dashboard cards or decorative assistant glyphs.

### Decision

rejected

### Reason

Would visually subordinate repository files and Git Changes despite user's explicit three-area requirement.

---

# 07. Design system

Only create or expand abstractions that have a clear shared intent.

## Tokens

### Semantic colors
`piframe-light.json` / `piframe-dark.json` define the normative hex values for `background/chassis`, `surface/displaySurface`, text/subtext, `accent/focusRing`, `success/warning/danger/info`, `agent*`, syntax and diff roles.
- Primary accent is signature Steel Blue (`#5f9fc5` in Dark, `#24638a` in Light).
- Status roles: Success (`#a1d9b0` Dark / `#336c42` Light), Warning (`#f6bd53` Dark / `#895706` Light), Danger (`#f1887a` Dark / `#882316` Light), Info (`#5f9fc5` Dark / `#24638a` Light).
- Background/Chassis: `#161c27` / `#121721` in Dark; `#f1f3f7` / `#e6e9f0` in Light.
- Card Surfaces: `#1c2432` / `#242e40` in Dark; `#ffffff` in Light.
- Status and syntax accents that miss text contrast pair with named text/surface colors; never invent darker replacement hues. PiFrame Light chat/composer use coordinated crisp surfaces; PiFrame Dark uses layered midnight-slate surfaces.

### Typography roles
Keep bundled Schibsted Grotesk for UI/body (14px base, 1.5 line-height); Barlow Condensed for brand and pane headings; Source Code Pro for code, file paths, commit messages and diffs. Existing roles: 11/12/14/16/20/28px; 400/500/600 weights. Preserve text scaling and avoid condensed type for long reading.

### Spacing scale
4px base unit; keep work-area gutters tight (about 6px), with 4/8/12/16/24/32/48px inner spacing. Use compact session/Git rows and reserve larger gaps for hierarchy, not repeated list padding.

### Radii / shape
Use 1px subtle borders and 6/10/14px semantic radii (small/medium/large). Apply to panes and non-pane functional surfaces; keep list rows compact and avoid giant cards or pill treatment.

### Elevation / surface hierarchy
Use aligned surfaces, thin 1px borders (`#2e3c53` Dark / `#d3dae4` Light) and small gaps to separate compartments; avoid heavy shadows. Reserve native elevation for menus/dialogs.

### Motion
Existing tokens: 120ms pointer press feedback; 240ms pane movement with drawer curve. Keyboard actions stay immediate. Respect reduced motion; no decorative launch or streaming animations.

### Breakpoints / size classes
Use current content-driven classes: compact <900px; medium 900–1439px; expanded ≥1440px. Compact: chat default + explicit Repository/Git Changes switcher. Medium: chat + one companion pane. Expanded: Bento Triptych visible; collapse session navigation before shrinking work panes. Revalidate exact widths with rendered layouts.

## Shared components

| Component | Intent | Variants | States | Accessibility |
|---|---|---|---|---|
| Session navigator | Find/create/switch Pi session | Repository tree, folder-scoped creation, hidden worker rows | Loading, empty, filtered-empty, selected, error | Search/tree semantics, keyboard traversal, clear folder context |
| Bento panes | Identify and arrange work areas | Repository, Pi chat, Git Changes; resize/hide | Visible, hidden, resized, compact switcher | Named controls, focus, persist pane state |
| Repository/Git workbench | Browse source and inspect changes | Changed tracked files, diff/editor, stage/undo, provenance | Clean, dirty, stale, error, read-only | Exact paths/ranges, confirm destructive undo, preserve dirty text |
| Pi chat/composer | Follow/send work and attach context | Streaming, settled, read-only, file/line references | Loading, empty, queued, interrupted, error | Preserve shortcuts; announce selected file/range and metadata |
| Session metrics | Show Pi work state | Model, thinking, context usage, cost, extension settings | Loading, unavailable, stale | Text labels/units; never fabricate unavailable data |
| Pi package manager | Inspect/update installed Pi packages | Per-package update/remove/version pin | Loading, update, error | Confirm removals; delegate lifecycle to Pi's package manager |

### Abstraction rule

Extract repeated patterns when they share the **same intent**, not merely because they look similar.

Do not create generic components whose abstraction removes product meaning.

---

# 08. Content & UX writing

## Voice
`[TO DEFINE]`

## Tone
`[TO DEFINE]`

## Naming rules
`[TO DEFINE]`

## Copy principles

- specific actions over vague CTAs;
- useful error messages;
- concise labels;
- never invent factual claims;
- preserve meaning under localization.

---

# 09. Accessibility

Accessibility is part of the design contract.

Check:
- semantic roles and labels;
- screen-reader reading order;
- contrast;
- touch target sizing;
- focus visibility;
- keyboard traversal;
- text scaling;
- reduced motion;
- color-independent meaning;
- error announcements;
- localization / RTL when relevant.

---

# 10. Responsive & adaptive behavior

## Size classes

### Compact
Below roughly 900px, session index is a drawer; chat remains the default workspace. A visible pane switcher opens Repository or Git Changes as full-width panes; preserve selections, scroll positions and dirty editor buffer when switching. Never reduce controls to inaccessible overflow.

### Medium
Roughly 900–1439px: keep session navigation collapsible; show chat plus one companion pane (Repository or Git Changes) at a time, with a clear switcher. Maintain current session/repository identity and visible Git state.

### Expanded
At 1440px and above, show Bento Triptych work areas together. Show the session index as a rail only when total width leaves roughly ≥420px for Repository/editor, ≥520px for chat and ≥260px for Git Changes (about 1560px overall); otherwise keep session navigation in a drawer. Collapse navigation before shrinking work panes below legible widths.

## Adaptive decisions

- **Session index:** remains global navigation; drawer at compact/medium and whenever expanded width is tight; rail only when three work panes retain minimum widths. Search/filter state survives pane changes.
- **Workspace:** selected session sets repository root; chat, editor and Git Changes remain one session-scoped workspace.
- **Compact:** one work pane visible at a time; chat default; explicit switcher reaches Repository and Git Changes. Keep each pane's scroll, selected file and dirty buffer.
- **Medium:** chat plus one companion pane; expose pane switcher and current pane label.
- **Expanded:** three Bento work areas visible together; session navigation yields space before work panes lose usable width.
- **State/recovery:** never discard editor buffer on pane/session switch without Save / Discard / Cancel; stale file content opens compare/reload recovery; Git actions always carry current repo/branch/file selection.

---

# 11. State matrix

Every critical screen should define applicable states.

| Screen | Initial | Loading | Populated | Empty | Error | Success | Disabled | Offline | Overflow |
|---|---|---|---|---|---|---|---|---|---|
| Bento session workspace | Launch/reconnect | Snapshot/status | Chat + tree/editor + Git | No session/no repo/clean Git | Save conflict/Git failure/offline | Saved/staged/committed | Read-only session | Daemon unavailable | Long paths, large diffs, narrow pane |

---

# 12. Visual QA & evidence

The agent must verify rendered output.

## D8 implementation status

D8 round-5 visual density and color refinements are complete. Changed files include:
- `apps/pi_frame/lib/ui/code/file_icon.dart`: Semantic semantic file icons for VS Code-like readability (REF-011).
- `apps/pi_frame/lib/features/workspace/repository_workspace.dart`: Replaced monospace font with `tokens.uiFontFamily` (`SchibstedGrotesk`) for tree items; aligned top bar to chat card style (38px).
- `apps/pi_frame/lib/features/transcript/thinking_block.dart`: Compacted thinking/reasoning into low-height summary rows (~26-28px) with expandable details (REF-012).
- `apps/pi_frame/lib/features/tool_timeline/tool_card.dart`: Compacted tool executions into slim status rows.
- `apps/pi_frame/lib/features/transcript/transcript_view.dart`: Hidden scrollbar track background (`trackVisibility: false`); indented and offset user messages to the right.
- `apps/pi_frame/lib/features/composer/composer.dart`: Converted buttons to icon-only, moved model and thinking selectors to the bottom row on the left, compacted padding.
- `apps/pi_frame/lib/app/app_shell.dart`: Slimmed app window toolbar to 42px with subtle branding.
- `apps/pi_frame/lib/features/session_changes/session_changes_pane.dart`: Aligned top bar to matching 38px card header.
- Themes & tokens: Added explicit `diffAddedFg` and `diffRemovedFg` tokens across PiFrame themes.

All 58 Flutter tests and 7 theme tests pass. `flutter analyze` passes clean. Live Windows debug application runs stably at PID 19992 with zero runtime errors.

## D9 rendered evidence

Fresh evidence captures:
- Live Windows 11 app (1600×960 maximized Bento triptych): `docs/design-evidence/pi-frame-live-windows.png` showing the slim 42px toolbar, unified 38px card headers, colorful file explorer with `SchibstedGrotesk` font and semantic file icons, compact reasoning summary row, right-offset user message bubble, and transparent-track scrollbar.
- Synthetic workspace fixture captures: Light `docs/design-evidence/bento-triptych-fixture-wide.png` (PiFrame Light) and Dark `docs/design-evidence/bento-triptych-fixture-dark-wide.png` (PiFrame Dark).
- Compact fixture captures: `docs/design-evidence/bento-triptych-fixture-compact-*.png` and `docs/design-evidence/bento-triptych-fixture-dark-compact-*.png`.
- Live Theme Customizer & Settings captures: `scratch/release_ui_screenshots/04_theme_editor.png` and `scratch/release_ui_screenshots/05_appearance_settings.png`.

Initial compact review found file tree/editor split too cramped and path labels truncated. The consolidated correction gives repository/editor its own file-list→editor transition below 420px, keeps full paths available by tooltip, and collapses session navigation into a drawer until the three work panes retain minimum widths. Fresh screenshots confirm readable compact file browsing/editor and balanced wide panes.

**D9 review round 2:** User reported `workspace.listFiles` failure and requested revised Catppuccin/rounded Bento styling plus session, Git, chat-context, package and resize capabilities. At discovery, active PID 40604 loaded a stale release sidecar (started Oct 5) that lacked `workspace.listFiles`; current source/schema already supported it. `pnpm run build:agentd` rebuilt the daemon, validated the workspace commands in the bundle, and passed an isolated PCP smoke test for `workspace.listFiles` session scoping. `flutter build windows --release` then refreshed the Release package; on-disk sidecar contains both `workspace.listFiles` and `pi.packages.list`. The live PID remains stale in memory and still rejects `pi.packages.list`; its process tree has three child Pi CLI processes. It was not stopped because that may terminate active workers. Wait for a safe user-controlled window before restarting and exercising native repository/package flows.

**D8 feedback slices — Git + sessions:** Removed duplicate changed-file list from Session settings. Git Changes omits untracked files, opens per-file diffs, offers per-file stage/unstage, and undo previews exact diff + confirms before discarding staged/unstaged state. Provenance is evidence-based: successful Pi `write`/`edit` tool calls mark “Tool Pi ha scritto il percorso”; PiFrame saves mark “Salvato da te in PiFrame”; both show mixed, unobserved/external changes remain unknown. This is event evidence, not guaranteed last-byte authorship. Session list groups by `gitRoot` when available and cwd otherwise, hides `worker#` rows, and offers a new-session dialog with native Windows/macOS folder picker. Web uses explicit daemon-local path entry because browsers do not expose native paths. Official `file_selector` 1.1.0 handles native picking. Tests cover tracked filtering, diff/stage/undo/provenance, repo groups, worker hiding and chosen cwd.

**D8 feedback slice — visual system and layout:** Replaced contrast-shifted Latte hues with official Catppuccin colors; Mauve is the primary accent and semantic statuses use palette Green/Yellow/Red/Blue. Text pairs use palette text colors for contrast. Removed the non-Catppuccin sample theme from the selectable built-in list; settings now offers PiFrame Light / Dark plus user themes. Tests assert exact palette roles, accessible text pairings, source/bundle parity and that selection changes `MaterialApp` colors. Extended modest rounded corners and 1px borders from Bento panes to app/settings headers, session rows, transcript blocks, composer, dialogs, menus and inputs. Existing code/diff surfaces keep the same grammar. Root/app design documents and sidecar contract now retire prior creative references.

**D8 feedback slice — resize responsiveness:** After lazy transcript layout, user reports minimize/maximize stalls seem improved or gone. Record as positive user validation; true fullscreen and long-history performance remain unprofiled. Do not reopen performance work unless the user reports recurrence.

**D8 feedback slice — chat metrics/context:** Pi `get_session_stats` returns cumulative token totals, cost and `contextUsage` (`tokens`, `contextWindow`, `percent`); UI refreshes on session attach, usage and settled events, without inventing missing values. Chat shows model, thinking level and extension `ui.status` values when packages publish them (Caveman/Ponytail metadata is never fabricated). Composer attaches repository files (inline content up to 64 KiB, otherwise path reference) and selected editor code with exact path and line range. Automated tests cover metrics, extension statuses, file context and code ranges.

**D8 feedback slice — Pi packages:** Settings lists user-scope packages through Pi's CLI and supports per-package update, remove and exact npm semver pin, with confirmation for destructive changes. Project packages stay outside this user-scope control to preserve Pi trust rules. Parser/pinning tests, dispatcher tests, actual local `pi list` parsing, Flutter settings test, 67 agentd tests and bundle build pass. The refreshed live daemon now returns 16 user packages; no package was modified.

## Required evidence

- [x] fresh light/dark synthetic workspace captures and native light/dark Settings captures inspected;
- [x] synthetic workspace navigation exercised (session drawer, file list/editor, Git Changes, compact pane switch); live package list verified; no registered live session available for file-list integration;
- [ ] all key state variants inspected in rendered form;
- [x] compact layout inspected at 390px in fresh light/dark fixture captures;
- [x] expanded layout inspected at 1440px in fresh light/dark fixture captures;
- [ ] large text checked;
- [ ] full keyboard/focus traversal checked;
- [x] light/dark rendered pair inspected (synthetic workspace plus live Settings captures);
- [ ] accessibility checked;
- [ ] live-session errors/recovery checked against refreshed daemon.

## Critique findings

Record high-impact issues:

| ID | Severity | Area | Evidence | Fix | Verified |
|---|---|---|---|---|---|
| QA-001 | P1 | Compact Repository | Initial 390px render split tree/editor, truncating names and constraining code pane | Switch list/editor below 420px; show full-width file list/editor with back control; provide full-path tooltip; keep session rail hidden until pane minima fit | [x] Confirmed in fresh light/dark compact captures |
| QA-002 | P1 | Native resize responsiveness | User reports minimize/maximize stalls improved or gone after lazy transcript layout; long transcript/fullscreen not profiled | Keep lazy `ListView`; only profile again if native stall recurs | [x] Positive user feedback; no recurrence reported |
| QA-003 | P1 | Theme color fidelity | Latte JSON retained custom dark green/status/syntax values despite Catppuccin label | Map all semantic roles to official Catppuccin values and pair low-contrast statuses with readable text | [x] Exact-color/token tests and live PiFrame Light / Dark selection confirmed |
| QA-004 | P1 | Non-pane surface grammar | Settings selectors, composer and transcript still used square/flat surfaces | Apply modest radii and subtle borders across controls and content, not only Bento panes | [x] Widget suite passes; live Settings and synthetic workspace captures inspected |

## Human review log

| Round | Date | Status | Feedback |
|---:|---|---|---|
| 2 | 2026-10-07T08:44:24.099Z | Changes requested | User feedback from live app testing (preserve full intent): (1) Repository pane opens empty; error is `Bad state: Unsupported command type: workspace.listFiles`. (2) Visual direction is unsatisfactory: keep Bento spatial grouping but use a modern VS Code-like treatment—slight borders and small gaps between compartments, rounded corners; current square-off UI feels wrong. Replace DR10 palette with PiFrame Dark (dark) and Latte (light), source https://catppuccin.com/palette/. (3) Sessions UX: allow opening/choosing a folder before creating a session in it; show sessions in a tree grouped by folder/repository; hide worker# subagent sessions. Session and Git lists have excessive whitespace. (4) Light theme has odd black components, including chat input. (5) Show Pi session metrics in chat: context-window usage, session cost, model, thinking effort and package-provided controls/metadata such as Caveman and Ponytail levels. (6) Make panels resizable and hideable. (7) Remove redundant Workarea list of modified files; unify with Git Changes, distinguishing agent-authored from manual changes. Git Changes should list modified tracked files; selecting a file opens its diff; per-file plus stages it and undo reverts its changes. (8) Settings should list installed Pi packages and support remove, individual update and version pinning. (9) Composer needs add-files-to-context; selecting code lines and right-clicking should offer `Add to chat` with exact file/line reference. (10) Minimize/restore/fullscreen causes several seconds of unresponsiveness. |
| 4 | 2026-10-07T12:43:12.231Z | Changes implemented; review pending | User reports PiFrame Light / Dark appeared in Settings but still rendered the old palette; replaced off-palette values with official tokens and added live theme-selection coverage. Retired former external design references from active direction. Extended rounded, subtly bordered surfaces beyond panes. User reports minimize/maximize stalls seem improved or gone. Fresh screenshots await review; no approval given. |
| 5 | 2026-10-07T16:00:00.000Z | Changes implemented; review pending | User feedback: (1) Application felt too monochromatic (grey + purple wash); add varied semantic color sparks (VS Code inspiration REF-011) to make files and chat scannable. (2) Bento boxing took too much space in chat; compress intermediate agent activity (thinking, tool cards, commands) into low-height Antigravity-style summary lines (REF-012). (3) Reject "AI-generated" look (REF-013) of same-hue fill, lighter outline, and colored text on every box. (4) Repository pane items must use UI font, not monospace code font. (5) Window toolbar was too tall; slim it down and make branding subtle. (6) Unify top bars across Repository, Git Changes, and Review Changes to match the chat pane header in a slim 38px profile. (7) Chat scrollbar should have no background track (thumb only). (8) User chat messages should be offset slightly to the right of agent blocks. (9) Redesign chat input: icon-only buttons, model/thinking selectors moved to bottom-left row, send/attach on bottom-right. |
| 9 | 2026-10-16T13:21:48.427Z | Changes requested | (1) Unified chat input box: text area and buttons (model, thinking, attach, review, send) share the same single background card, like VS Code and Antigravity, eliminating wasted padding. (2) Attach button positioned on the right side, to the left of review and send. (3) Remove separate top tab bar for 'File'/'Git Changes' in medium/compact layout; instead embed expandable/collapsible tabs directly in the companion pane title bar ('\|-File-\|\|---Git Changes---\|' and vice-versa). (4) Remove background and border from intermediate blocks (reasoning/thinking, edit, tool execution) in chat transcript so they are completely compact and borderless. |

| 6 | 2026-10-07T18:00:00.000Z | Changes implemented; review pending | User feedback: (1) Unified chat composer: text area and all controls (model, thinking, attach, review, send) share one background card, like VS Code/Antigravity, to reduce wasted space. (2) Attach button moved to the right side, left of review and send. (3) Removed the separate File / Git Changes switcher bar in medium/compact layouts; the companion pane title bar hosts the tabs: active tab expanded with label, inactive tab minimized, clicking it expands it and minimizes the other. (4) Intermediate chat blocks (reasoning, tool/edit execution) have no background or outer border, so they are compact. |

**Status:** round 6 changes implemented. Fresh live 1280×720 Windows render `docs/design-evidence/pi-frame-live-windows.png` shows the unified composer, the companion tab bar and the borderless reasoning row. No approval recorded.

**Later user feedback:** Align the right-hand controls of intermediate tool rows with each other and align their expand/collapse icons with the reasoning row. Short labels must not pull those controls toward the text. User review of this change remains pending; no new live capture was requested.

**Session-list startup:** Show repository and session rows in under one second when practical, reusing indexed titles. If a title is absent or outdated in the index, show the ID or last known title provisionally and replace it with the authoritative title when available. Load transcript-derived details in the background without blocking daemon interaction. User explicitly selected this fallback; live review remains pending.

## Bounded verification rule

Use bounded review passes:
1. one comprehensive review;
2. one consolidated fix pass;
3. one confirmation pass when needed.

Do not endlessly polish without a new user/product reason.

---

# 13. AI-slop quality gate

Before shipping, challenge:

### Genericity test
Would this interface look plausible for an unrelated SaaS / AI dashboard / productivity app?

### Specificity test
What elements are clearly caused by this product's users, content, environment, or brand?

### Justification test
Can every major visual treatment be explained by a user/product need or a documented design principle?

### Restraint test
Could removing a decorative element improve the task?

### Coherence test
Does the same design grammar hold across screens and states?

### Reference fidelity test
When the brief pins a reference, did we preserve its intended principle without blindly cloning its surface?

---

# 14. Design decision log

### 2026-10-06 — Lock Bento Triptych

**Context:** User requested a Bento-style workspace with chat, active-repository files and Git Changes, preserving PiFrame identity and the then-current DR10 palette.
**Evidence:** REF-003/004 (historical app design record), REF-005 (palette at that time), REF-006 (Bento layout reference), user answers Q-VISUAL-DIRECTION and Q-D6-LOCK.
**Decision:** Lock Bento Triptych spatial grouping: co-visible repository/editor, Pi chat and Git Changes on expanded layouts; explicit state-preserving pane switcher on compact layouts. Later D9 feedback supersedes the old palette and surface language.
**Why:** Best matches requested three co-equal work areas without copying VS Code styling; supports balanced throughput and discoverability.
**Alternatives rejected:** Artifact Atlas (overweights editor); Conversation Desk (subordinates repository/Git areas).
**Impact:** Durable spatial direction. D9 revision below supersedes only palette/surface treatment.

### 2026-10-07 — D9 live-review revision and expanded requirements

**Context:** Human reported a workspace command failure and requested revised palette/surfaces plus broader IDE-like workflows.
**Evidence:** REF-010 PiFrame palette; human D9 review round 2 in §12; reported `workspace.listFiles` error.
**Decision:** Keep Bento topology; use PiFrame Light / Dark and rounded, subtly bordered compartments. Track session tree/folder creation/worker filtering; Pi metrics; resizable/hideable panes; unified Git review/actions with evidence-based provenance; package lifecycle; file/line context; and resize responsiveness.
**Impact:** D9 remains changes_requested pending implementation and fresh review.

### 2026-10-07 — D9 round-4 visual correction

**Context:** User restarted Pi and reported selected PiFrame themes still looked like the previous palette; non-pane UI retained square, borderless treatment. User retired former external design references and reports minimize/maximize stalls improved or gone.
**Evidence:** Human feedback log round 4; current Latte theme JSON still contains noncanonical green/status/syntax hues; global surface defaults and several custom containers remain square/flat.
**Decision:** Map every semantic role to official PiFrame Dark and PiFrame Light values; retain readable text by pairing accents with named palette text/surface colors rather than darkening palette hues. Extend modest rounding and subtle borders to non-pane UI. Keep Bento as topology; preserve resize improvement, do not reopen it without regression.
**Impact:** Return to D8 for correction, then regenerate and present fresh renders. No approval recorded.

### 2026-10-07 — D9 round-5 density, hierarchy and anti-slop refinement

**Context:** User reviewed rendered UI and identified: monochromatic two-tone wash; excessive card boxing in chat activity; unwanted AI-generated triple-tinted styling; monospace font in file explorer; bulky 76px window toolbar; mismatched pane header treatments; visible chat scrollbar track; centered/undifferentiated user chat bubbles; and cluttered composer layout.
**Evidence:** User references REF-011 (`VSCODE_UI.png`), REF-012 (`Antigravity_chat.png`), and anti-reference REF-013 (`AI_GENERATED_LOOK.png`). Human feedback log round 5.
**Decision:**
1. Introduce semantic color sparks (`FileIcon`, diff counters, syntax) for immediate scannability without two-color wash.
2. Compress intermediate agent activity (thinking, tools, commands) into low-profile collapsible summary rows (~26-28px).
3. Strictly ban "AI-generated" same-hue fill/border/text cards. Use neutral surfaces, readable text, and selective accents.
4. Set repository explorer font to `tokens.uiFontFamily` (`SchibstedGrotesk`), reserving `tokens.monoFontFamily` for code and paths.
5. Slim app window toolbar to 42px with 18px icon and 15px `PIFRAME` wordmark.
6. Unify top bars across Repository, Git Changes, and Review Changes into 38px subtle card headers matching the chat pane header.
7. Hide chat scrollbar track background (`trackVisibility: false`).
8. Indent and right-offset user chat messages.
9. Streamline composer: icon-only buttons, model/thinking selectors on bottom-left, send/attach on bottom-right.
**Impact:** Implementation verified across unit/widget tests and live Windows 11 capture `docs/design-evidence/pi-frame-live-windows.png`. Awaiting human review round 6. No approval recorded.

---

# 15. Assumptions

Temporary assumptions only.

### `[DATE] — [ASSUMPTION]`
**Why inferred:**  
**Risk if wrong:**  
**How to confirm:**  

---

# 16. Open questions

Only unresolved questions that materially affect the design.

- `[TO DISCOVER]`

---

# 17. Definition of done

A Design Director task is complete only when:

- `DESIGN.md` is current;
- references have been inspected and registered;
- product truth and visual inspiration are separated;
- the interaction environment is explicit;
- the critical user flow is modeled;
- the visual direction is intentional and specific;
- important UI states are defined;
- accessibility and adaptation are designed;
- implementation follows the design contract;
- rendered UI has been inspected;
- high-impact critique findings are fixed;
- hardening has covered realistic content/errors/localization where relevant;
- no major generic/AI-default decision remains unexplained.
