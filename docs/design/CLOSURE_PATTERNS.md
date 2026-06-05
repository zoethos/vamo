# Closure patterns — cross-industry review of the "closure dance"

Status: research memo for founder review · 2026-06-05
Feeds: S17 (trip lifecycle) before implementation; amends `MONEY_GOVERNANCE.md` D2/A6 if accepted.

## Why this memo

S17's current design is **active unanimity**: close requires every active member
to tap "accept", with a 6-month timeout into `unresolved`. Multi-party closure
with money attached is a solved problem in several industries; none of them
use active unanimity with an indefinite wait. This memo extracts what they do
instead and what Vamo should borrow.

## The patterns

### P1 — Deemed acceptance after a bounded review window (freelance escrow)

Upwork fixed-price: freelancer submits work, client has **14 days** to approve
or object; **silence is approval** and funds auto-release. The submitter
triggers the clock with an explicit "submit for payment" act — informal
delivery doesn't count.

Lesson: the close *request* is a formal act that starts a short, well-known
clock. Non-response is consent, not a blocker. Nobody waits six months on a
ghost.

### P2 — Confirmation ends the dispute right (e-commerce escrow)

AliExpress: buyer confirms receipt (or the order auto-confirms after the
protection window, 15–60 days); **confirming receipt forfeits the right to
open a dispute**. Disputes are only possible before confirmation.

Lesson: Vamo already has this exact mechanic in MONEY_GOVERNANCE **A1** —
"you settled = you accepted the math". The per-member dispute window closing
at own settlement confirm is the industry-standard shape. Keep it; it is the
*final* gate, distinct from the close gate.

### P3 — Deemed-accepted statements with an outer limit (banking, UCC 4-406)

Bank customers have a duty to examine statements and report problems within a
reasonable period (**30 days** for the repeat-fraud preclusion) and an absolute
**one-year outer limit** regardless of care. The statement is *presumed
correct* unless objected to in time.

Lesson: the close report is Vamo's "statement". It is presumed accepted unless
someone objects within the window — and there is always a hard outer limit
after which the books are simply closed. An accounting system that can stay
open forever is considered defective, not flexible.

### P4 — Staged closure: practical completion → defects period → final
certificate (construction)

Construction never closes in one step: **practical completion** (stop new
work, handover) starts a **defects liability period** (~12 months) where
problems can still be raised and fixed, and only then is the **final
certificate** issued. Partial/sectional completion lets parts of the project
close while others continue.

Lesson: Vamo's lifecycle accidentally mirrors this and should embrace the
naming and semantics deliberately:

| Construction | Vamo |
|---|---|
| Practical completion | `closed` — no new expenses/captures (read-only) |
| Defects liability period | settling + disputes still open per member (A1) |
| Final certificate | per-member settlement confirm (dispute window closes) |
| Sectional completion | member `completed_at` — finish your own way |

"Closed" must NOT mean "everything is over" — it means "no new work". The
banner copy already says it: *"Trip closed — settling still open."*

### P5 — Lazy consensus: silence is consent (Apache / W3C governance)

Apache projects act on stated intent after a **72-hour objection window**;
silence equals support; objections must carry a reason and a willingness to
discuss. Decisions are not hostage to non-participation.

Lesson: the *default* should be assent. Requiring a positive tap from every
member makes the close hostage to the least-engaged person — precisely the
person a trip-close flow will always have (someone who flew home and stopped
opening the app).

### P6 — Force with recorded dissent (corporate squeeze-out)

Majority shareholders can force a merger on a dissenting minority, but the
minority keeps **appraisal rights** — the dissent is recorded and has legal
effect, even though it cannot block.

Lesson: owner force-close is legitimate *if* dissent stays loud — which is
exactly the hard display rule ("included — disputed by Marco"). Force-close +
recorded objection in the close report = squeeze-out with appraisal rights.

### P7 — Counterexample: no lifecycle at all (Splitwise-class apps)

Bill-split incumbents have no close ceremony: groups live forever, balances
linger, dormancy is indistinguishable from completion. This is the zombie-trip
disease R3 exists to cure — confirmation that *having* a dance matters; the
question is only its choreography.

## Synthesis — what every mature system shares

1. **A formal trigger** starts a clock (submit for payment / statement issued /
   practical completion / stated intent).
2. **A short, known window** for objection (72h … 14d … 30d), never months.
3. **Silence = consent.** Active objection, with a reason, is the only thing
   that interrupts — and it interrupts visibly, not silently.
4. **Closure is staged.** "No new work" comes first; financial finality comes
   later, per party; disputes survive the first gate but not the second.
5. **A hard outer limit** guarantees the books close no matter what.
6. **Force exists** but dissent is recorded and consequential.

S17's current draft violates #2 and #3 (active unanimity, indefinite wait) and
half-implements #4 (it has the stages but treats `closed` acceptance as the
hard gate instead of settlement confirm).

## Recommendation — the amended closure dance

Replace **active unanimity** with **deemed acceptance**:

1. **Close request** (owner, or auto when all members mark complete) →
   `lifecycle = closing`, `close_requested_at = now()`, push to all active
   members: *"Trip is closing — review the report. Closes automatically in
   14 days."*
2. **14-day acceptance window**: members may explicitly **accept** (nice
   signal, closes early if all accept) or **object with reason** (same
   machinery as share rejection — no new concepts). Silence does nothing.
3. **Window expires, no objections** → `closed`. Close report records who
   accepted explicitly vs. who was deemed accepted ("exposes consent" —
   deemed ≠ hidden).
4. **Objection raised** → trip stays `closing`; group resolves, objector
   withdraws, or owner **force-closes** (P6: objection survives into the
   close report, flagged). The 6-month → `unresolved` backstop now applies
   **only to objected/stuck trips** — it becomes the rare exception, not the
   default fate of every trip with one ghost member.
5. **Reminder at day 7** (half-window), single shot (`close_warned_at`,
   anti-nag) — replaces the month-5 warning as the common case.
6. **Financial finality stays per-member** (A1 unchanged): disputes and
   settling remain open after `closed` until each member confirms their own
   settlement — construction's defects period. `settlements` writable in
   `closing/closed/unresolved`, never in `cancelled`.

### Constitutional check

- "Consent is annotation, not a gate" — silence-as-assent finally makes this
  true for closure too; the current draft quietly made consent a gate.
- "Blocking is reserved for lifecycle integrity" — an explicit objection
  pausing clean-close is lifecycle integrity; one ghost member blocking
  everything is not.
- "Reports resolve ambiguity" — deemed vs. explicit acceptance is listed in
  the close report, never silently merged.

### S17 prompt delta (if accepted)

- `0015`: add `close_warned_at` (already amended), semantics of
  `close_accepted_at` unchanged; **no new columns needed** — deemed acceptance
  is computed (`close_requested_at + interval '14 days'`), explicit accepts
  recorded as today.
- New RPC `object_to_trip_close(p_trip_id, p_reason)` (or reuse S19 share
  rejection fields if sequencing allows — founder call; a dedicated minimal
  column pair `close_objected_at/close_objection_reason` on `trip_members`
  keeps S17 independent of S19).
- `trip-lifecycle-jobs` daily cron becomes three queries: day-7 reminder
  (once), day-14 deemed-close (no objections), 6-month unresolved (objected
  trips only; warn at month 5 stays for those).
- rls_smoke: + "deemed close after window with silent member" (state-based:
  lifecycle = closed), + "objection holds trip in closing".

### Open knobs (founder)

- Window length: **14 days** (Upwork-grade) vs 7 (consumer-snappy). Trips are
  social and small — 7 days is defensible; 14 is gentler. Default proposal: 14.
- Should explicit all-accept close early? Proposal: yes (it's strictly more
  consent than deemed).
- Does the owner need a separate force during the window? Proposal: no —
  force only exists as the objection-breaker (step 4); the window is short
  enough to wait out.

## Sources

- Upwork fixed-price protection / 14-day auto-release:
  https://support.upwork.com/hc/en-us/articles/211063748-Fixed-Price-Protection ·
  https://support.upwork.com/hc/en-us/articles/211063718-How-payments-for-milestones-and-fixed-price-contracts-work
- AliExpress dispute window & confirm-receipt forfeiture:
  https://service.aliexpress.com/page/knowledge?pageId=82&knowledge=1060568542&language=en ·
  https://www.dsers.com/blog/open-aliexpress-dispute/
- UCC § 4-406 (statement examination duty, 30-day preclusion, 1-year outer):
  https://www.law.cornell.edu/ucc/4/4-406
- Practical completion / defects liability period / final certificate:
  https://www.trimble.com/blog/construction/en-US/article/defect-management-from-practical-completion-to-the-final-certificate ·
  https://janecameronarchitects.com/blog/practical-completion-and-the-final-certificate
- Apache lazy consensus (72-hour window, silence = consent):
  https://openoffice.apache.org/docs/governance/lazyConsensus.html ·
  https://community.apache.org/committers/decisionMaking.html
