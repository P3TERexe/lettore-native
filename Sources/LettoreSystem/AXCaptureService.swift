import Foundation
@preconcurrency import ApplicationServices
import CoreGraphics
import AppKit
import LettoreCore

/// Servizio di cattura del testo nativo macOS basato su Accessibility APIs (AXUIElement).
public actor AXCaptureService {

    /// Sessione AX aperta dalla modalità di lettura continua. Vive solo
    /// all'interno dell'attore: gli elementi AX non sono `Sendable`.
    var continuousSession: ContinuousAXSession?

    /// Sessione di highlight nativa registrata alla cattura.
    var highlightSession: SourceHighlightSession?
    var selectionObserverHandle: AXSelectionObserverHandle?
    /// Token del debounce delle notifiche di selezione.
    var selectionNotificationGeneration = 0
    /// Token dell'installazione corrente dell'observer. Serve a scartare
    /// un'installazione che termina dopo uno stop o una nuova osservazione
    /// (il passaggio sul MainActor per aggiungere la source è un punto di
    /// reentrancy dell'attore).
    var selectionObservationGeneration = 0

    /// Una cattura clipboard è già in corso. Due richieste sovrapposte
    /// (hotkey + Studio) leggerebbero e ripristinarebbero lo stesso
    /// pasteboard incrociandosi: la seconda attende che la prima finisca e
    /// poi procede, così la richiesta non va persa.
    ///
    /// La cattura può restare sospesa dopo un `await` (attivazione dell'app,
    /// polling del cambio, ripristino del focus): lo snapshot invece è
    /// sincrono nell'attore e materializza i dati di ogni item, quindi può
    /// bloccare l'attore per il tempo di lettura dei provider (nessun timeout
    /// su quella fase). Oltre `clipboardCaptureStaleInterval` una cattura
    /// rimasta ferma su un `await` si considera bloccata e viene invalidata
    /// da quella nuova. L'invalidazione cambia la generazione: la vecchia
    /// cattura se ne accorge al primo controllo dopo un `await` ed esce senza
    /// altri Cmd+C né ripristini, perché gli appunti appartengono alla nuova.
    var isClipboardCaptureInFlight = false
    /// Generazione della cattura clipboard: il `defer` azzera la guardia solo
    /// se è ancora la propria, non quella di una cattura che l'ha sostituita.
    var clipboardCaptureGeneration = 0
    /// Istante di avvio della cattura in corso, per riconoscere quella bloccata.
    var clipboardCaptureStartedAt: Date?

    static let clipboardCaptureStaleInterval: TimeInterval = 5
    /// Attesa massima di una cattura sovrapposta prima di rinunciare.
    ///
    /// Deve superare `clipboardCaptureStaleInterval`: con 4 s la seconda
    /// richiesta rinunciava mentre la prima era ancora considerata valida
    /// (stale a 5 s), perdendo la cattura senza invalidare nulla. A 6 s la
    /// cattura in corso o completa, oppure viene invalidata perché ferma
    /// oltre la soglia e la richiesta nuova parte con una cattura fresca.
    static let clipboardCaptureWaitTimeout: TimeInterval = 6
    /// Passo di attesa usato mentre un'altra cattura occupa il pasteboard.
    static let clipboardCaptureWaitPoll: UInt64 = 20_000_000
    /// Passo del polling sul cambio di `changeCount`.
    static let clipboardPollInterval: UInt64 = 10_000_000
    /// Tick di conferma dopo la prima osservazione della copia: una seconda
    /// scrittura poco dopo è dell'utente e non va sovrascritta.
    static let clipboardCopyConfirmationTicks = 3
    /// Grazia dopo un cambio appunti senza testo: una copia in due fasi
    /// (`clearContents`, poi il testo qualche decina di ms dopo) espone un
    /// primo cambio senza stringa. Uscire subito lascerebbe la selezione
    /// copiata al posto degli appunti originali.
    static let clipboardNonTextGraceInterval: TimeInterval = 0.4
    /// Osservazione breve della copia tardiva quando la cattura è annullata.
    static let clipboardCancelSettleTicks = 6
    static let clipboardCancelSettleInterval: UInt64 = 30_000_000

    public init() {}
    
    /// Verifica se l'applicazione ha i permessi di Accessibilità concessi nelle Preferenze di Sistema.
    public func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Apre direttamente la pagina Privacy & Sicurezza -> Accessibilità nelle Impostazioni di macOS.
    @MainActor
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Richiede al sistema operativo di mostrare il prompt per concedere i permessi di Accessibilità.
    public func requestAccessibilityPrompt() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// Cattura il testo attualmente selezionato nell'applicazione attiva in primo piano.
    public func captureSelectedText() async -> CapturedSelection? {
        await captureSelectedText(from: nil)
    }

    /// Cattura il testo selezionato nell'app indicata, oppure nell'app in primo
    /// piano se il PID è `nil`.
    ///
    /// Con un PID esplicito il fallback clipboard consegna Cmd+C direttamente
    /// all'app di origine (`postToPid`): quel primo tentativo non sposta il
    /// focus. Solo il ripiego con attivazione lo cambia, temporaneamente.
    public func captureSelectedText(from applicationPID: pid_t?) async -> CapturedSelection? {
        if !AXIsProcessTrusted() {
            print("[AXCapture] ⚠️ Accessibilità NON concessa dal sistema operativo (AXIsProcessTrusted == false).")
            requestAccessibilityPrompt()
        }

        if let applicationPID {
            switch captureSelectedText(fromApplication: applicationPID) {
            case .selection(let selection):
                return selection
            case .noSelection:
                // L'app espone l'attributo e risponde con testo vuoto: non
                // c'è selezione. Il fallback clipboard attiverebbe l'app e
                // sposterebbe il focus (in VS Code copierebbe la riga col
                // cursore), quindi va saltato.
                print("[AXCapture] Selezione vuota nell'app target (PID \(applicationPID)): fallback clipboard saltato.")
                return nil
            case .unavailable:
                // L'app target non espone la selezione via AX: il Cmd+C mirato
                // normalmente non sposta il focus e permette comunque di
                // leggere la selezione. Il ripiego con attivazione invece sì
                // (temporaneo).
                clearHighlightSession()
                return await captureViaClipboardFallback(targeting: applicationPID)
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppValue: AnyObject?
        
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppValue
        )
        
        var appName: String? = nil
        if appResult == .success, let appElement = focusedAppValue as! AXUIElement? {
            var titleValue: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &titleValue) == .success,
               let titleStr = titleValue as? String {
                appName = titleStr
            }
        } else {
            print("[AXCapture] Nota: kAXFocusedApplicationAttribute restituito con codice \(appResult.rawValue)")
        }
        
        var focusedElementValue: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        
        if elemResult == .success, let focusedElement = focusedElementValue as! AXUIElement? {
            // Distingue la selezione vuota (risposta valida dell'app, nessun
            // fallback) dall'attributo non disponibile (fallback clipboard).
            let (readout, _) = selectionReadout(of: focusedElement)

            switch readout {
            case .text(let selectedStr):
                let registration = registerSelectionHighlight(
                    focused: focusedElement,
                    sourcePID: processIdentifier(of: focusedElement)
                )
                return CapturedSelection(
                    text: selectedStr,
                    sourceDocumentID: registration.documentID,
                    sourceRange: registration.sourceRange,
                    sourcePID: registration.sourcePID
                )
            case .empty:
                print("[AXCapture] L'app in primo piano (app: \(appName ?? "?")) espone una selezione vuota: fallback clipboard saltato.")
                return nil
            case .unavailable:
                print("[AXCapture] Focused element senza selezione leggibile (app: \(appName ?? "?")). Provo il fallback clipboard.")
            }
        } else {
            print("[AXCapture] kAXFocusedUIElementAttribute fallito (codice \(elemResult.rawValue)). Provo il fallback clipboard.")
        }
        
        // Fallback su simulazione Cmd+C via clipboard se AX non espone il testo selezionato
        clearHighlightSession()
        return await captureViaClipboardFallback()
    }

    /// Cattura la selezione dall'app target leggendo solo l'AX, senza inviare
    /// eventi di tastiera.
    ///
    /// Distingue `noSelection` (l'app espone `kAXSelectedTextAttribute` e
    /// risponde con testo vuoto) da `unavailable` (elemento focalizzato
    /// assente o attributo non supportato): solo `unavailable` autorizza il
    /// fallback clipboard, che copia e può spostare il focus.
    private func captureSelectedText(fromApplication pid: pid_t) -> ApplicationSelectionProbe {
        let appElement = AXUIElementCreateApplication(pid)

        guard let focusedElement = focusedElement(in: appElement) else {
            print("[AXCapture] App target (PID \(pid)) senza elemento focalizzato: nessuna cattura AX.")
            return .unavailable
        }

        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )

        let readout = SelectionReadout.classify(
            focusedElementAvailable: true,
            attributeSucceeded: textResult == .success,
            selectedText: selectedTextValue as? String
        )

        switch readout {
        case .text(let selectedStr):
            let registration = registerSelectionHighlight(
                focused: focusedElement,
                sourcePID: pid
            )
            return .selection(CapturedSelection(
                text: selectedStr,
                sourceDocumentID: registration.documentID,
                sourceRange: registration.sourceRange,
                sourcePID: registration.sourcePID
            ))
        case .empty:
            print("[AXCapture] L'app target (PID \(pid)) espone una selezione vuota: nessun fallback.")
            return .noSelection
        case .unavailable:
            print("[AXCapture] Nessuna selezione AX disponibile nell'app target (PID \(pid), textResult: \(textResult.rawValue)).")
            return .unavailable
        }
    }

    /// Legge `kAXSelectedTextAttribute` distinguendo una selezione vuota (l'app
    /// risponde con una stringa vuota) da un attributo non disponibile. `raw`
    /// conserva la stringa così com'è, spazi compresi.
    func selectionReadout(of element: AXUIElement) -> (readout: SelectionReadout, raw: String) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        let selectedText = value as? String
        return (
            SelectionReadout.classify(
                focusedElementAvailable: true,
                attributeSucceeded: result == .success,
                selectedText: selectedText
            ),
            selectedText ?? ""
        )
    }

    /// Elemento focalizzato nell'app target, con fallback alla finestra
    /// focalizzata/principale quando il focused element non è disponibile.
    private func focusedElement(in application: AXUIElement) -> AXUIElement? {
        let attributes = [
            kAXFocusedUIElementAttribute,
            kAXFocusedWindowAttribute,
            kAXMainWindowAttribute
        ]

        for attribute in attributes {
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(
                application,
                attribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID() else {
                continue
            }
            return (value as! AXUIElement)
        }

        return nil
    }

    private func applicationName(for application: AXUIElement, pid: pid_t) -> String? {
        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(application, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String,
           !title.isEmpty {
            return title
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
    
    /// Fallback clipboard: copia la selezione con Cmd+C e la legge dagli
    /// appunti, ripristinando poi il contenuto precedente.
    ///
    /// Con `targetPID` esplicito l'evento viene consegnato direttamente
    /// all'app di origine invece che alla finestra in primo piano: quel primo
    /// tentativo non sposta il focus. Se la consegna mirata non produce una
    /// copia entro ~300 ms si attiva temporaneamente l'app di origine e si
    /// ripete il Cmd+C a livello globale: l'attivazione cambia il focus (e con
    /// un'app a schermo intero può cambiare Space) e viene annullata alla fine.
    ///
    /// Una cattura già in corso viene attesa (fino a `clipboardCaptureWaitTimeout`,
    /// ~6 s, oltre la soglia di stale) e poi eseguita:
    /// due richieste ravvicinate completano in serie sullo stesso pasteboard.
    /// Il ripristino avviene solo se gli appunti contengono ancora la copia
    /// che abbiamo letto: una copia dell'utente nel frattempo resta intatta.
    ///
    /// `pasteboard`, `copyAction` e la finestra di polling sono iniettabili per
    /// i test: la produzione usa gli appunti generali, gli eventi di tastiera
    /// sintetici e ~1 s di osservazione.
    ///
    /// Una copia può arrivare in due fasi (`clearContents` e testo poco dopo):
    /// dopo un cambio senza testo si attende `nonTextGraceInterval` prima di
    /// considerarla fallita, e in quel caso lo snapshot viene comunque
    /// ripristinato. Uno snapshot parziale (item o tipi non materializzabili)
    /// non è invece ripristinabile: in quel caso non si invia alcun Cmd+C e gli
    /// appunti restano intatti. Limite noto: se una seconda cattura invalida questa
    /// (stale > 5 s) il ripristino spetta solo alla cattura nuova, che però
    /// ha già fotografato gli appunti con la nostra copia parziale.
    func captureViaClipboardFallback(
        targeting targetPID: pid_t? = nil,
        pasteboard: ClipboardPasteboard = ClipboardPasteboard(),
        copyAction: any ClipboardCopyAction = SystemClipboardCopyAction(),
        totalTicks: Int = 100,
        activationTick: Int = 30,
        nonTextGraceInterval: TimeInterval = AXCaptureService.clipboardNonTextGraceInterval,
        staleInterval: TimeInterval = AXCaptureService.clipboardCaptureStaleInterval
    ) async -> CapturedSelection? {
        // Task già annullato: niente Cmd+C, il pasteboard resta com'è.
        guard !Task.isCancelled else {
            print("[AXCapture] Cattura clipboard annullata prima della copia: nessun Cmd+C.")
            return nil
        }

        // Cattura sovrapposta: si aspetta che finisca invece di rinunciare.
        guard await waitForClipboardCaptureSlot(staleInterval: staleInterval) else {
            print("[AXCapture] Fallback clipboard occupato da un'altra cattura: richiesta ignorata.")
            return nil
        }

        clipboardCaptureGeneration &+= 1
        let generation = clipboardCaptureGeneration
        isClipboardCaptureInFlight = true
        clipboardCaptureStartedAt = Date()
        defer {
            // Una cattura nuova può averci invalidato: in quel caso lo stato
            // appartiene a lei e non va azzerato.
            if clipboardCaptureGeneration == generation {
                isClipboardCaptureInFlight = false
                clipboardCaptureStartedAt = nil
            }
        }

        let board = pasteboard.raw
        let previousChangeCount = board.changeCount
        let snapshot = makePasteboardSnapshot(of: board)

        // Uno snapshot parziale non è ripristinabile: dopo il Cmd+C la copia
        // resterebbe negli appunti al posto del contenuto dell'utente. Si
        // rinuncia alla cattura prima di toccare appunti, focus o eventi.
        guard !snapshot.hasPartialMaterialization else {
            print("[AXCapture] Snapshot appunti parziale: nessun Cmd+C, appunti lasciati intatti.")
            return nil
        }

        /// Copia attribuita al nostro Cmd+C: testo letto e `changeCount` che
        /// l'ha prodotta. Il ripristino avviene solo se gli appunti contengono
        /// ancora esattamente quella copia: se nel frattempo l'utente ha
        /// copiato altro, la sua copia resta.
        var observedCopy: (changeCount: Int, text: String)?
        /// Cambio appunti senza testo (fase `clearContents` di una copia in due
        /// fasi oppure copia non testuale): se resta l'ultimo, lo snapshot va
        /// ripristinato per non lasciare la selezione copiata negli appunti.
        var nonTextChangeCount: Int?
        defer {
            // Una cattura nuova può averci sostituito (stale > 5 s): in quel
            // caso gli appunti sono suoi e questa non deve toccarli.
            if clipboardCaptureGeneration == generation {
                if let observedCopy {
                    if board.changeCount == observedCopy.changeCount,
                       clipboardText(board) == observedCopy.text {
                        restorePasteboardSnapshot(snapshot, to: board)
                    } else {
                        print("[AXCapture] Appunti cambiati dopo la copia: copia dell'utente preservata.")
                    }
                } else if let nonTextChangeCount,
                          board.changeCount == nonTextChangeCount {
                    print("[AXCapture] Copia senza testo: ripristino gli appunti originali.")
                    restorePasteboardSnapshot(snapshot, to: board)
                }
            } else {
                print("[AXCapture] Cattura clipboard sostituita: nessun ripristino della cattura vecchia.")
            }
        }

        await copyAction.copy(from: targetPID)

        // Il cambio può arrivare oltre i 150 ms (app lente): si osserva fino a
        // ~1 s. Dopo i primi ~300 ms senza copia si prova ad attivare l'app di
        // origine per un Cmd+C globale. La copia osservata va confermata per
        // qualche tick: una seconda scrittura poco dopo è dell'utente.
        var activationAttempted = false
        var stableTicks = 0
        var nonTextGraceDeadline: Date?

        for tick in 1...max(totalTicks, 1) {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: Self.clipboardPollInterval)
            if Task.isCancelled { break }

            // Una cattura più nuova può averci invalidato mentre eravamo
            // sospesi su un `await`: esce senza altri Cmd+C né ripristini.
            guard clipboardCaptureGeneration == generation else {
                print("[AXCapture] Cattura clipboard sostituita: esco senza altre azioni.")
                return nil
            }

            if let observed = observedCopy {
                guard board.changeCount == observed.changeCount,
                      clipboardText(board) == observed.text else {
                    print("[AXCapture] L'utente ha copiato altro durante l'osservazione: la sua copia resta.")
                    break
                }
                stableTicks += 1
                if stableTicks >= Self.clipboardCopyConfirmationTicks { break }
                continue
            }

            if board.changeCount != previousChangeCount {
                if let copied = clipboardText(board) {
                    observedCopy = (board.changeCount, copied)
                    nonTextChangeCount = nil
                    nonTextGraceDeadline = nil
                    stableTicks = 0
                    continue
                }

                // Cambio senza testo: può essere il `clearContents` di una
                // copia in due fasi, con il testo qualche decina di ms dopo.
                // Non si esce al primo cambio: si aspetta la grazia breve.
                if let tracked = nonTextChangeCount {
                    if board.changeCount != tracked {
                        // Un'altra scrittura non testuale: non è la seconda
                        // fase della nostra copia, il contenuto è dell'utente.
                        print("[AXCapture] Scrittura senza testo non nostra: gli appunti restano.")
                        break
                    }
                } else {
                    print("[AXCapture] Cambio appunti senza testo: attendo il testo della copia.")
                    nonTextChangeCount = board.changeCount
                    nonTextGraceDeadline = Date().addingTimeInterval(nonTextGraceInterval)
                }

                if let nonTextGraceDeadline, Date() >= nonTextGraceDeadline {
                    print("[AXCapture] Nessun testo entro la grazia: ripristino gli appunti originali.")
                    break
                }
                continue
            }

            if !activationAttempted, tick >= activationTick, let targetPID {
                activationAttempted = true
                print("[AXCapture] Cmd+C mirato senza copia: attivo temporaneamente l'app \(targetPID).")
                await copyAction.copyActivatingTarget(targetPID)
            }
        }

        // La copia può atterrare dopo l'ultimo tick o mentre il task viene
        // cancellato. In quel caso si osserva ancora per un breve tratto: il
        // `Task.sleep` di un task cancellato ritorna subito, quindi serve
        // un'attesa che la cancellazione non interrompa.
        if observedCopy == nil {
            let extraTicks = Task.isCancelled ? Self.clipboardCancelSettleTicks : 1
            for _ in 0..<extraTicks {
                await Self.settleIgnoringCancellation(Self.clipboardCancelSettleInterval)
                guard clipboardCaptureGeneration == generation else {
                    print("[AXCapture] Cattura clipboard sostituita: esco senza altre azioni.")
                    return nil
                }
                if board.changeCount != previousChangeCount {
                    if let copied = clipboardText(board) {
                        observedCopy = (board.changeCount, copied)
                    } else if nonTextChangeCount == nil || nonTextChangeCount == board.changeCount {
                        nonTextChangeCount = board.changeCount
                    } else {
                        // Scrittura non testuale diversa dalla nostra: non va
                        // sovrascritta con lo snapshot.
                        nonTextChangeCount = nil
                    }
                    break
                }
            }
        }

        guard let observedCopy else {
            print("[AXCapture] Fallback clipboard senza risultato (nessun testo copiato).")
            return nil
        }

        print("[AXCapture] Fallback clipboard riuscito (\(observedCopy.text.count) caratteri).")
        return CapturedSelection(text: observedCopy.text)
    }

    /// Attende che l'eventuale cattura clipboard in corso termini.
    ///
    /// Due catture sovrapposte (hotkey + Studio) condividono lo stesso
    /// pasteboard: la seconda aspetta invece di rinunciare. Oltre
    /// `clipboardCaptureWaitTimeout` restituisce `false`; una cattura ferma
    /// oltre `staleInterval` viene considerata bloccata e invalidata (la
    /// vecchia se ne accorge dalla generazione e non tocca più gli appunti).
    /// Il timeout supera `staleInterval`, quindi di norma la cattura
    /// bloccata viene invalidata e sostituita prima di rinunciare.
    private func waitForClipboardCaptureSlot(staleInterval: TimeInterval) async -> Bool {
        var waited: TimeInterval = 0
        while isClipboardCaptureInFlight {
            if let startedAt = clipboardCaptureStartedAt,
               Date().timeIntervalSince(startedAt) >= staleInterval {
                print("[AXCapture] Cattura clipboard precedente bloccata: la invalido.")
                break
            }
            guard waited < Self.clipboardCaptureWaitTimeout, !Task.isCancelled else {
                return false
            }
            try? await Task.sleep(nanoseconds: Self.clipboardCaptureWaitPoll)
            waited += TimeInterval(Self.clipboardCaptureWaitPoll) / 1_000_000_000
        }
        return true
    }

    /// Attesa che sopravvive alla cancellazione: `try? await Task.sleep` in un
    /// task cancellato ritorna immediatamente.
    private static func settleIgnoringCancellation(_ nanoseconds: UInt64) async {
        let sleeper = Task.detached { try? await Task.sleep(nanoseconds: nanoseconds) }
        _ = await sleeper.value
    }

    /// Testo copiato utilizzabile, oppure `nil` se gli appunti non contengono
    /// testo non vuoto.
    private func clipboardText(_ board: NSPasteboard) -> String? {
        guard let copied = board.string(forType: .string),
              !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return copied
    }
}

extension AXCaptureService: SelectedTextCapturing {}

/// Lettura dell'attributo `kAXSelectedTextAttribute`, isolata dalla cattura
/// AX per poter essere verificata senza app reali.
enum SelectionReadout: Equatable {
    case text(String)
    /// L'attributo è supportato e la risposta è una stringa vuota: non c'è
    /// selezione, non è un'app che non espone la selezione.
    case empty
    /// Elemento focalizzato assente o attributo non supportato/non leggibile.
    case unavailable

    /// Solo "non disponibile" autorizza il fallback clipboard: una selezione
    /// vuota è una risposta valida dell'app e non deve trasformarsi in Cmd+C
    /// con attivazione e furto del focus.
    var requiresClipboardFallback: Bool {
        self == .unavailable
    }

    /// Nome compatto per i log diagnostici.
    var logName: String {
        switch self {
        case .text: return "text"
        case .empty: return "empty"
        case .unavailable: return "unavailable"
        }
    }

    static func classify(
        focusedElementAvailable: Bool,
        attributeSucceeded: Bool,
        selectedText: String?
    ) -> SelectionReadout {
        guard focusedElementAvailable else { return .unavailable }
        guard attributeSucceeded, let selectedText else { return .unavailable }
        if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        return .text(selectedText)
    }
}

/// Esito della cattura AX nell'app target.
enum ApplicationSelectionProbe {
    case selection(CapturedSelection)
    case noSelection
    case unavailable
}

/// Snapshot del contenuto del pasteboard come dati puri.
///
/// `NSPasteboardItem` è legato al pasteboard che lo contiene: riscrivere gli
/// item letti da `pasteboardItems` dopo un `clearContents` solleva
/// un'`NSException` in `writeObjects`. Conservare solo tipi e dati rende lo
/// snapshot riusabile: ogni ripristino ricostruisce item nuovi.
struct PasteboardSnapshot {
    /// Dati per item, nell'ordine del pasteboard di origine. Gli item senza
    /// dati materializzabili sono omessi.
    let items: [[NSPasteboard.PasteboardType: Data]]
    /// Item presenti nel pasteboard di origine, anche quelli i cui provider
    /// promised/lazy non hanno fornito alcun dato.
    let sourceItemCount: Int
    /// Tipi dichiarati da ogni item materializzato, nello stesso ordine di
    /// `items`: un provider può fornire solo una parte dei tipi promessi.
    let expectedTypes: [Set<NSPasteboard.PasteboardType>]
    /// Lo snapshot è stato interrotto perché il contenuto supera il budget in
    /// byte: gli item successivi non sono stati letti.
    let isTruncatedForByteBudget: Bool

    /// Budget predefinito per lo snapshot.
    ///
    /// `data(forType:)` materializza il dato prima che il budget possa essere
    /// controllato: il budget limita quindi l'accumulo totale dello snapshot,
    /// non la singola allocazione (un tipo più grande del budget viene
    /// comunque letto interamente e poi scartato insieme all'item).
    static let defaultByteBudget = 64 * 1024 * 1024

    /// Tipi effettivamente materializzati, per il log diagnostico.
    var materializedTypeCount: Int {
        items.reduce(0) { $0 + $1.count }
    }

    /// Tipi dichiarati dagli item materializzati, per il log diagnostico.
    var expectedTypeCount: Int {
        expectedTypes.reduce(0) { $0 + $1.count }
    }

    /// Tipi testuali derivati che AppKit dichiara accanto al contenuto
    /// principale (RTF/HTML/stringa) ma che alla prima lettura possono
    /// restituire `nil` da `data(forType:)`. La loro assenza non rende
    /// parziale lo snapshot: riscrivendo il contenuto principale il sistema
    /// li rigenera.
    ///
    /// `NSPasteboard.PasteboardType.string` coincide con
    /// `public.utf8-plain-text`; i nomi legacy sono inclusi per gli appunti
    /// scritti da applicazioni vecchie.
    static let ignorableTextAliasTypes: Set<NSPasteboard.PasteboardType> = [
        .init("public.utf8-plain-text"),
        .init("public.utf16-external-plain-text"),
        .init("public.utf16-plain-text"),
        .init("NSStringPboardType")
    ]

    /// Tipi che rappresentano lo stesso testo in forme alternative: se almeno
    /// uno è materializzato, gli altri possono mancare senza perdita del
    /// contenuto (il sistema può derivarli dal principale).
    static let textualContentTypes: Set<NSPasteboard.PasteboardType> =
        ignorableTextAliasTypes.union([.rtf, .html])

    /// Tipi testuali primari "forti": contengono il formato e permettono al
    /// sistema di rigenerare gli alias di testo semplice. Una `.string` da
    /// sola non basta: è testo piatto e non ricostruisce un RTF o un HTML
    /// dichiarato ma non materializzato.
    static let strongTextualContentTypes: Set<NSPasteboard.PasteboardType> = [.rtf, .html]

    /// Una parte del contenuto di origine non è stata materializzata: item
    /// mancanti, tipi promessi ma non forniti o budget superato. Riscrivere
    /// solo una parte perderebbe silenziosamente il resto.
    ///
    /// Possono mancare solo gli alias di testo semplice
    /// (`ignorableTextAliasTypes`), e solo quando l'item ha materializzato una
    /// forma primaria forte (`.rtf` o `.html`) da cui il sistema li rigenera.
    /// Qualsiasi tipo non-alias mancante — RTF, HTML, immagine, fileURL —
    /// rende lo snapshot parziale, anche se una `.string` è presente.
    var hasPartialMaterialization: Bool {
        if isTruncatedForByteBudget { return true }
        guard items.count == sourceItemCount, items.count == expectedTypes.count else {
            return true
        }
        return zip(items, expectedTypes).contains { data, expected in
            let materialized = Set(data.keys)
            let missing = expected.subtracting(materialized)
            if missing.isEmpty { return false }
            let hasStrongTextualContent = !materialized.isDisjoint(with: Self.strongTextualContentTypes)
            if hasStrongTextualContent, missing.isSubset(of: Self.ignorableTextAliasTypes) {
                return false
            }
            return true
        }
    }
}

func makePasteboardSnapshot(
    of pasteboard: NSPasteboard,
    byteBudget: Int = PasteboardSnapshot.defaultByteBudget
) -> PasteboardSnapshot {
    let pasteboardItems = pasteboard.pasteboardItems ?? []
    var items: [[NSPasteboard.PasteboardType: Data]] = []
    var expectedTypes: [Set<NSPasteboard.PasteboardType>] = []
    var totalBytes = 0
    var isTruncatedForByteBudget = false

    outer: for item in pasteboardItems {
        let expected = Set(item.types)
        var data: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            guard let value = item.data(forType: type) else { continue }
            // Oltre il budget l'item in corso viene scartato per intero: una
            // sua parte verrebbe riscritta come se fosse completa.
            if totalBytes + value.count > byteBudget {
                isTruncatedForByteBudget = true
                data.removeAll()
                break outer
            }
            totalBytes += value.count
            data[type] = value
        }
        // Un item senza dati non è trasferibile: scriverlo farebbe fallire
        // `writeObjects` con un'eccezione.
        if !data.isEmpty {
            items.append(data)
            expectedTypes.append(expected)
        }
    }

    if isTruncatedForByteBudget {
        print("[AXCapture] Snapshot appunti oltre il budget di \(byteBudget) byte: ripristino non eseguibile.")
    }

    return PasteboardSnapshot(
        items: items,
        sourceItemCount: pasteboardItems.count,
        expectedTypes: expectedTypes,
        isTruncatedForByteBudget: isTruncatedForByteBudget
    )
}

func restorePasteboardSnapshot(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
    // Il contenuto di origine non era materializzabile (provider promised o
    // lazy) o è stato troncato dal budget: un `clearContents` qui
    // distruggerebbe gli appunti dell'utente. Lo stesso vale per uno snapshot
    // parziale: riscrivere i soli item/tipi materializzati perderebbe
    // silenziosamente il resto.
    guard !snapshot.hasPartialMaterialization else {
        print("[AXCapture] Appunti di origine non ripristinabili (item \(snapshot.items.count)/\(snapshot.sourceItemCount), tipi \(snapshot.materializedTypeCount)/\(snapshot.expectedTypeCount)\(snapshot.isTruncatedForByteBudget ? ", budget superato" : "")): ripristino saltato.")
        return
    }

    pasteboard.clearContents()
    guard !snapshot.items.isEmpty else { return }

    // Item nuovi a ogni ripristino: quelli di `pasteboardItems` restano legati
    // al pasteboard di origine e non sono riscrivibili.
    let rebuilt = snapshot.items.map { data -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, value) in data {
            item.setData(value, forType: type)
        }
        return item
    }
    if !pasteboard.writeObjects(rebuilt) {
        print("[AXCapture] ⚠️ Ripristino degli appunti non riuscito.")
    }
}

/// Appunti usati dal fallback clipboard.
///
/// Il wrapper è `Sendable` per attraversare l'isolamento dell'attore: le
/// operazioni di `NSPasteboard` sono sicure da qualsiasi thread. Nei test si
/// passa un pasteboard dedicato, in produzione `NSPasteboard.general`.
struct ClipboardPasteboard: @unchecked Sendable {
    let raw: NSPasteboard

    init(_ raw: NSPasteboard = .general) {
        self.raw = raw
    }
}

/// Invio del comando di copia del fallback clipboard.
///
/// Iniettabile per rendere i test deterministici: la produzione usa eventi
/// sintetici, i test una finta scrittura su un pasteboard dedicato.
protocol ClipboardCopyAction: Sendable {
    /// Primo tentativo: Cmd+C mirato all'app di origine (`targetPID`) oppure
    /// globale quando il PID non è noto. Il `postToPid` non sposta il focus.
    func copy(from targetPID: pid_t?) async

    /// Ripiego quando il Cmd+C mirato non produce una copia: attiva
    /// temporaneamente l'app di origine, verifica che sia davvero in primo
    /// piano, invia un Cmd+C globale e restituisce il focus all'app che era in
    /// primo piano. L'attivazione sposta il focus (e può cambiare Space con
    /// un'app a schermo intero); se il focus non arriva, il Cmd+C globale non
    /// viene inviato.
    func copyActivatingTarget(_ targetPID: pid_t) async
}

extension ClipboardCopyAction {
    func copyActivatingTarget(_ targetPID: pid_t) async {
        await copy(from: targetPID)
    }
}

/// Implementazione di produzione: eventi di tastiera sintetici.
///
/// Attivazione, app in primo piano, ripristino del focus e invio di Cmd+C sono
/// iniettabili: i test verificano il percorso reale senza toccare app vere.
struct SystemClipboardCopyAction: ClipboardCopyAction {
    typealias FrontmostPIDProvider = @Sendable () async -> pid_t?
    typealias Activator = @Sendable (_ pid: pid_t) async -> Bool
    typealias FocusRestorer = @Sendable (_ pid: pid_t) async -> Void
    typealias CommandPoster = @Sendable (_ targetPID: pid_t?) async -> Void

    private let frontmostPIDProvider: FrontmostPIDProvider
    private let activator: Activator
    private let focusRestorer: FocusRestorer
    private let commandPoster: CommandPoster

    /// Tempo massimo concesso all'app target per diventare in primo piano.
    private let frontmostTimeoutNanoseconds: UInt64
    private let frontmostPollNanoseconds: UInt64
    /// Attese attorno al Cmd+C globale (focus e materializzazione della copia).
    private let activationSettleNanoseconds: UInt64
    private let copySettleNanoseconds: UInt64

    init(
        frontmostPID: @escaping FrontmostPIDProvider = {
            await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
        },
        activate: @escaping Activator = { pid in
            await MainActor.run {
                NSRunningApplication(processIdentifier: pid)?.activate() ?? false
            }
        },
        restoreFocus: @escaping FocusRestorer = { pid in
            await MainActor.run {
                _ = NSRunningApplication(processIdentifier: pid)?.activate()
            }
        },
        postCommandC: @escaping CommandPoster = { targetPID in
            SystemClipboardCopyAction.postSyntheticCommandC(to: targetPID)
        },
        frontmostTimeoutNanoseconds: UInt64 = 500_000_000,
        frontmostPollNanoseconds: UInt64 = 25_000_000,
        activationSettleNanoseconds: UInt64 = 120_000_000,
        copySettleNanoseconds: UInt64 = 300_000_000
    ) {
        self.frontmostPIDProvider = frontmostPID
        self.activator = activate
        self.focusRestorer = restoreFocus
        self.commandPoster = postCommandC
        self.frontmostTimeoutNanoseconds = frontmostTimeoutNanoseconds
        self.frontmostPollNanoseconds = frontmostPollNanoseconds
        self.activationSettleNanoseconds = activationSettleNanoseconds
        self.copySettleNanoseconds = copySettleNanoseconds
    }

    func copy(from targetPID: pid_t?) async {
        // Una cattura annullata non deve lasciare un Cmd+C in volo: la
        // copia arriverebbe quando il chiamante ha già rinunciato.
        guard !Task.isCancelled else {
            print("[AXCapture] Cattura annullata: Cmd+C non inviato.")
            return
        }
        await commandPoster(targetPID)
    }

    func copyActivatingTarget(_ targetPID: pid_t) async {
        guard !Task.isCancelled else {
            print("[AXCapture] Cattura annullata: attivazione dell'app \(targetPID) non eseguita.")
            return
        }

        let previousPID = await frontmostPIDProvider()
        let activated = await activator(targetPID)
        guard activated else {
            print("[AXCapture] Attivazione dell'app \(targetPID) non riuscita: Cmd+C globale non inviato.")
            return
        }

        // `activate()` può non riuscire senza restituire `false`: senza questa
        // verifica il Cmd+C globale finirebbe sull'app ancora in primo piano
        // (lo Studio) copiando il testo sbagliato.
        guard await isFrontmost(targetPID) else {
            print("[AXCapture] L'app \(targetPID) non è passata in primo piano: Cmd+C globale non inviato.")
            await restoreFocus(to: previousPID, from: targetPID)
            return
        }

        // Lascia al sistema il tempo di spostare il focus prima del Cmd+C.
        try? await Task.sleep(nanoseconds: activationSettleNanoseconds)

        // La cattura può essere stata annullata mentre aspettavamo il focus:
        // niente Cmd+C globale, ma il focus va comunque riportato indietro
        // perché l'attivazione è già avvenuta.
        guard !Task.isCancelled else {
            print("[AXCapture] Cattura annullata: Cmd+C globale non inviato, ripristino il focus.")
            await restoreFocus(to: previousPID, from: targetPID)
            return
        }

        // Durante il settle il focus può tornare su un'altra app (attivazione
        // annullata dal sistema o interazione dell'utente): un Cmd+C globale
        // finirebbe sull'app sbagliata. Si ricontrolla prima di postare.
        guard await isFrontmost(targetPID) else {
            print("[AXCapture] L'app \(targetPID) non è più in primo piano dopo il settle: Cmd+C globale non inviato.")
            await restoreFocus(to: previousPID, from: targetPID)
            return
        }

        await commandPoster(nil)

        // Se la cattura è stata annullata durante l'attesa, il focus viene
        // ripristinato subito: la guardia evita solo di aspettare oltre.
        if Task.isCancelled {
            print("[AXCapture] Cattura annullata dopo il Cmd+C: ripristino immediato del focus.")
        } else {
            // Attende che l'app materializzi la copia prima di restituire il focus.
            try? await Task.sleep(nanoseconds: copySettleNanoseconds)
        }

        await restoreFocus(to: previousPID, from: targetPID)
    }

    /// Polling di `NSWorkspace.frontmostApplication` fino al timeout.
    private func isFrontmost(_ pid: pid_t) async -> Bool {
        var elapsed: UInt64 = 0
        while elapsed < frontmostTimeoutNanoseconds {
            if await frontmostPIDProvider() == pid { return true }
            try? await Task.sleep(nanoseconds: frontmostPollNanoseconds)
            elapsed += frontmostPollNanoseconds
        }
        return await frontmostPIDProvider() == pid
    }

    private func restoreFocus(to previousPID: pid_t?, from targetPID: pid_t) async {
        guard let previousPID, previousPID != targetPID else { return }
        // Il focus è stato spostato dall'attivazione: va riportato indietro
        // anche se la cattura è stata annullata, altrimenti l'utente
        // resterebbe su un'altra app. La cancellazione blocca i Cmd+C, non
        // questa pulizia.
        await focusRestorer(previousPID)
    }

    static func postSyntheticCommandC(to targetPID: pid_t?) {
        // Il gate evita che il monitor degli input della lettura continua
        // interpreti questo evento sintetico come interazione utente.
        ProgrammaticInputGate.suppress()
        let source = CGEventSource(stateID: .hidSystemState)
        let keyC: CGKeyCode = 8 // Codice per tasto 'C' su tastiera Mac

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else {
            return
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        if let targetPID {
            cmdDown.postToPid(targetPID)
            cmdUp.postToPid(targetPID)
        } else {
            cmdDown.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
        }
    }
}
