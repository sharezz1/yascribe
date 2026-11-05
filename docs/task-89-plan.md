# TASK-89 plan: Transcribe zapisuje wybór korekty

Decyzja: (a). Po przyjęciu przebiegu (`model.transcribe` == true) okno zapisuje wybór korekty jako nadpisanie sesji
(`TranscriptModelsDraft.persistCorrectionChoice` → `NotesModel.saveCorrectionChoice` → `saveDraft`). `afterTranscription`
już czyta `modelOverrides.correction`, więc bez zmian w AppModel.
- Reguła `ModelsSheetRules.draft`: wybór == preset i brak nadpisania => `.preset` => `setOverride(nil)`; nie łamię jej.
- Pusty wybór (draft nil) => nic się nie zapisuje.
- Zapis PO przyjęciu transkrypcji (odmowa nie zostawia nadpisania), synchronicznie, przed końcem przebiegu.
- (b) odrzucone: ukrycie sekcji gubi możliwość wyboru modelu korekty przed transkrypcją.
Test: `TranscribeCorrectionChoiceTests` (wybór z draftu → model w żądaniu po `afterTranscription`; równy presetowi → brak nadpisania).
Mutacja: usunięcie wywołania `persistCorrectionChoice` / zapisu → test pada.
