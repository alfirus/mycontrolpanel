# Chat grounding pipeline (Farah — ML)

## What
`lib/services/chat_context.dart` (stdlib only: `dart:math`) adds the
grounding layer the AI Chatbox was missing:

- `ChatContextBuilder.build(...)` — deterministic server-context block from
  live state (servers + metrics + alerts + crons + apps + recent logs),
  with per-section caps and a 6k-char ceiling. Drop-in replacement for the
  inline `_aiSystemPrompt` builder in `control_center_screen.dart`.
- `ChatRetriever.retrieve(query, docs, k)` — on-device keyword retrieval
  (IDF-lite + prefix fallback + exact-phrase bonus) over status/log/alert
  evidence. No embeddings, no network, deterministic.
- `ChatEvalSet` — offline eval (6 queries over 8 docs, recall bar 0.8),
  enforced by `test/chat_context_test.dart` in the `flutter test` gate.

## Wiring notes for Nadia (serving/ops)
- No serving changes: everything runs on-device in the Flutter app.
- Suggested wiring: in `_sendChat`, run `ChatRetriever.retrieve` on the user
  query over the current alerts + last-N log tails, prepend the top-k hits
  to the system prompt built by `ChatContextBuilder.build`.
- Eval: `flutter test test/chat_context_test.dart`. To extend coverage, add
  `ChatDoc`s to `ChatEvalSet.docs` and `ChatEvalCase`s to `cases`; keep
  recall >= `minRecall`.
