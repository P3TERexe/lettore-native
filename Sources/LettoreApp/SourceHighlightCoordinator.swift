import Foundation
import Observation
import LettoreCore
import LettoreSystem

/// Compone la sessione di highlight nativa con i due percorsi di playback.
///
/// Il controller AX del ticket 03 gestisce già policy, sospensione e stop su
/// input. Qui restano le responsabilità dell'app:
/// - serializzare `begin` e `update`, perché un chunk può partire prima che
///   l'observer di selezione sia installato;
/// - conservare l'ultimo range in attesa e applicarlo una sola volta;
/// - tradurre gli esiti in un avviso discreto, senza fermare l'audio;
/// - fermare la lettura una sola volta sull'input dell'utente.
@MainActor
final class SourceHighlightCoordinator {

    static let accessibilityNotice =
        "Accessibilità non concessa: la frase non può essere evidenziata nell'app di origine. La lettura continua nello Studio."
    static let unsupportedNotice =
        "Questa app non consente di evidenziare la frase: la lettura continua nello Studio."

    private let appState: AppState
    private let highlighter: any SourceSelectionHighlighting
    private let isAccessibilityGranted: @MainActor () -> Bool
    private let stopReading: @MainActor () -> Void

    private lazy var selectionController = SourceSelectionController(
        highlighter: highlighter,
        isEnabled: { [weak self] in
            self?.appState.isSourceHighlightEnabled ?? false
        },
        onUserInteraction: { [weak self] in
            self?.handleUserInteraction()
        }
    )

    private var documentID: UUID?
    private var isSessionActive = false
    private var pendingRange: SourceTextRange?
    /// Metadati dell'ultima cattura quando la sessione non è stata aperta
    /// perché il toggle era spento o mancava l'accessibilità. Servono ad
    /// attivare l'highlight se l'utente riaccende il toggle durante la lettura.
    private var pendingSource: (documentID: UUID, sourcePID: pid_t)?
    private var operationTask: Task<Void, Never>?
    /// Invalida le operazioni accodate quando la sessione viene chiusa o
    /// sostituita.
    private var generation = 0
    private var didStopForUserInteraction = false

    init(
        appState: AppState,
        highlighter: any SourceSelectionHighlighting,
        isAccessibilityGranted: @escaping @MainActor () -> Bool,
        stopReading: @escaping @MainActor () -> Void
    ) {
        self.appState = appState
        self.highlighter = highlighter
        self.isAccessibilityGranted = isAccessibilityGranted
        self.stopReading = stopReading
        observeToggle()
    }

    // MARK: - Sessione

    /// Apre la sessione solo se documento e PID sono disponibili. La prima
    /// `update` può arrivare subito dopo: viene accodata dietro al `begin`.
    func begin(documentID: UUID, sourcePID: pid_t) {
        guard appState.isSourceHighlightEnabled else {
            end()
            pendingSource = (documentID, sourcePID)
            return
        }
        guard isAccessibilityGranted() else {
            end()
            pendingSource = (documentID, sourcePID)
            appState.sourceHighlightNotice = Self.accessibilityNotice
            return
        }

        appState.sourceHighlightNotice = nil
        pendingSource = nil
        generation &+= 1
        let generation = self.generation
        self.documentID = documentID
        self.isSessionActive = true
        self.didStopForUserInteraction = false

        // Se il chunk corrente appartiene già a questa sorgente, applicalo
        // subito: copre il toggle acceso a metà lettura e riduce la latenza
        // della prima selezione. Gli update successivi restano idempotenti.
        if let current = appState.currentChunk,
           current.sourceDocumentID == documentID,
           let range = current.sourceRange {
            self.pendingRange = range
        } else {
            self.pendingRange = nil
        }

        enqueue { [weak self] in
            guard let self,
                  self.generation == generation,
                  self.isSessionActive else {
                return
            }

            await self.selectionController.begin(
                documentID: documentID,
                sourcePID: sourcePID
            )

            guard self.generation == generation,
                  self.isSessionActive else {
                return
            }
            await self.applyPendingRange(generation: generation)
        }
    }

    /// Aggiorna la selezione al chunk corrente. I chunk senza range o di un
    /// altro documento vengono ignorati: resta il fallback Studio.
    func update(chunk: ReadingChunk) {
        guard appState.isSourceHighlightEnabled, isSessionActive else {
            return
        }

        guard let range = chunk.sourceRange,
              let chunkDocumentID = chunk.sourceDocumentID,
              chunkDocumentID == documentID else {
            // Il chunk corrente non è mappabile: invalida anche un eventuale
            // apply già accodato e dimentica l'ultimo range, così un ritorno
            // in primo piano non riapplica la frase precedente.
            pendingRange = nil
            selectionController.clearLastRange()
            return
        }

        pendingRange = range
        let generation = self.generation

        enqueue { [weak self] in
            guard let self,
                  self.generation == generation,
                  self.isSessionActive,
                  self.documentID == chunkDocumentID else {
                return
            }
            await self.applyPendingRange(generation: generation)
        }
    }

    /// Chiude la sessione senza deselezionare il testo nell'app di origine.
    func end() {
        appState.sourceHighlightNotice = nil
        pendingSource = nil
        guard isSessionActive else { return }
        isSessionActive = false
        documentID = nil
        pendingRange = nil
        didStopForUserInteraction = false
        generation &+= 1

        enqueue { [weak self] in
            await self?.selectionController.end()
        }
    }

    // MARK: - Toggle

    private func observeToggle() {
        withObservationTracking {
            _ = appState.isSourceHighlightEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleToggleChange()
                self?.observeToggle()
            }
        }
    }

    private func handleToggleChange() {
        guard appState.isSourceHighlightEnabled else {
            appState.sourceHighlightNotice = nil
            selectionController.suspend()
            return
        }

        guard isSessionActive else {
            // La cattura è arrivata con il toggle spento o senza permessi:
            // riapri la sessione ora che l'utente l'ha riattivato.
            if let pending = pendingSource {
                begin(documentID: pending.documentID, sourcePID: pending.sourcePID)
            }
            return
        }
        let generation = self.generation

        // Durante lo spegnimento il controller ha scartato gli aggiornamenti:
        // il range più recente è quello del chunk corrente. Se il chunk non è
        // mappabile non riapplicare il range precedente tramite `resume()`.
        guard let current = appState.currentChunk,
              current.sourceDocumentID == documentID,
              let range = current.sourceRange else {
            pendingRange = nil
            selectionController.clearLastRange()
            return
        }
        pendingRange = range

        enqueue { [weak self] in
            guard let self,
                  self.generation == generation,
                  self.isSessionActive else {
                return
            }

            await self.applyPendingRange(generation: generation)
        }
    }

    // MARK: - Input utente

    private func handleUserInteraction() {
        guard !didStopForUserInteraction else { return }
        didStopForUserInteraction = true
        stopReading()
    }

    // MARK: - Serializzazione

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = operationTask
        operationTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    private func applyPendingRange(generation: Int) async {
        guard let range = pendingRange, let documentID else { return }
        pendingRange = nil

        let outcome = await selectionController.update(
            range: range,
            documentID: documentID
        )

        guard generation == self.generation else { return }

        switch outcome {
        case .applied:
            appState.sourceHighlightNotice = nil
        case .unsupported, .failed:
            appState.sourceHighlightNotice = Self.unsupportedNotice
        case .suspended, .none:
            // La sospensione è normale: l'app di origine non è frontmost e
            // l'audio continua. Un nil è un no-op (toggle spento o sessione
            // sostituita).
            break
        }
    }
}
