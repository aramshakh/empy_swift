# Empy Swift — Learnings from 2026-03-04 Transcript Incident

## Context
6+ hour cycle on transcript UX where 3 acceptance criteria repeatedly failed:
1. Replicas/messages still overwritten
2. `other` speaker missing in feed
3. No persisted transcript after Stop

---

## A) Critical mistakes (understanding + execution)

### 1) Fixed symptoms, not the state machine
- I changed UI mapping (`id`/`timestamp`) before fixing transcript lifecycle model in `TranscriptEngine`.
- Result: apparent progress, but overwrite behavior remained.

### 2) Treated `diarize=true` as guaranteed speaker split
- Assumed Deepgram diarization in mixed/mono flow would reliably output `other`.
- Result: `other` label remained unstable/absent.

### 3) Persistence tied only to finals
- Saved only final segments; if finalization timing failed, nothing was saved.
- Result: Stop -> no transcript artifact.

### 4) Claimed “done” before end-to-end acceptance
- Multiple “almost fixed” updates without proving all 3 criteria in one real-call run.
- Result: trust loss + repeated loop.

### 5) Too much narration between actions
- Repeated “next step” messages instead of shipping diff evidence quickly.
- Result: user perceived no execution between messages.

---

## B) Product learnings (locked)

### 1) Required UX contract for transcript feed
- Partial is temporary preview only.
- Final is immutable message in dialogue stream.
- Existing finals must never be overwritten/removed.

### 2) Speaker identity must be source-first
- Primary mapping: stream source (`microphone` => `me`, `system` => `other`).
- DTX/diarization is secondary enrichment, not the primary identity source.

### 3) Stop behavior must be fail-safe
On Stop always produce persisted session artifact:
- all final segments
- plus close/flush current partial if present

### 4) Acceptance criteria must be tested as one package
Single test run must verify all three simultaneously:
- no overwrite
- `me/other` visible
- persisted transcript exists after Stop

---

## C) What can be extracted from empy-trone (high ROI)

### 1) Recorder finalization protocol (already solved)
`src/swift/Recorder.swift`:
- Emits chunk notifications with explicit speaker tags (`me`/`other`)
- Emits explicit final chunk on termination (`is_final: true`)
- Finalization on stop is deterministic (both streams)

Use in Swift app:
- preserve explicit stream-speaker mapping as canonical source
- force final flush on stop for both streams

### 2) Conversation data contract used in trone frontend/backend
`src/features/conversation/api/conversationApi.ts`:
- transcription item shape includes:
  - `id`
  - `text`
  - `time_start`
  - `time_end`
  - `speaker: 'me' | 'other'`

Use in Swift app:
- persist exactly this shape (or strict superset) to simplify endpoint handoff

### 3) Session-only transcript state behavior
`src/features/conversation/state/conversationAtoms.ts`:
- transcription state intentionally non-persistent across sessions in UI memory

Use in Swift app:
- keep live state in-memory per session
- persist archive separately as explicit session artifact file

---

## D) Execution protocol going forward (for this feature)

1. No “done” claim until one end-to-end run passes all 3 criteria.
2. Every progress update includes:
   - changed files
   - commit hash
   - criterion status [1/3, 2/3, 3/3]
3. If a criterion fails, publish root-cause + exact next patch target before coding.

---

## E) Immediate next implementation targets

1. Rework `TranscriptEngine` to immutable-final model:
   - one active partial per speaker
   - append final only, never mutate older finals
2. Speaker mapping order:
   - source-based first
   - diarization as optional correction
3. Stop finalization:
   - force close partials
   - persist full session payload to file

---

Owner: Orchestrator
Date: 2026-03-04
