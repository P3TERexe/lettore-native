import Foundation

/// Punto di partenza di una cattura continua.
///
/// `text` contiene il testo già disponibile al momento della cattura, a partire
/// dalla selezione o dal cursore. `selectedText` è conservato separatamente per
/// diagnostica e per il fallback "solo selezione".
public struct ContinuousCaptureStart: Sendable {
    public let text: String
    public let selectedText: String
    public let sourceAppName: String?
    public let canPage: Bool
    public let notice: String?

    public init(
        text: String,
        selectedText: String,
        sourceAppName: String? = nil,
        canPage: Bool = false,
        notice: String? = nil
    ) {
        self.text = text
        self.selectedText = selectedText
        self.sourceAppName = sourceAppName
        self.canPage = canPage
        self.notice = notice
    }
}

/// Una porzione successiva di testo ottenuta dopo lo scorrimento della pagina.
public struct ContinuousTextPage: Sendable {
    public let text: String
    public let isFinal: Bool
    public let notice: String?

    public init(text: String, isFinal: Bool, notice: String? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.notice = notice
    }

    public static let end = ContinuousTextPage(text: "", isFinal: true, notice: nil)
}

/// Astrazione della sorgente di testo continuo.
///
/// In produzione è implementata da `AXCaptureService`; nei test può essere
/// sostituita da una sorgente finta per verificare il coordinamento senza
/// dipendere dalle Accessibility API.
public protocol ContinuousTextSource: Sendable {
    /// Avvia una sessione e restituisce il testo catturato fino al bordo noto
    /// del documento (o della viewport corrente).
    func startContinuousCapture() async -> ContinuousCaptureStart

    /// Recupera la pagina successiva. Deve restituire `isFinal == true` quando
    /// non c'è più testo disponibile o quando la continuazione non è possibile.
    func nextContinuousPage() async -> ContinuousTextPage

    /// Chiude la sessione AX e libera i riferimenti agli elementi di sistema.
    func endContinuousCapture() async
}
