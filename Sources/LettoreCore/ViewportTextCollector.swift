import Foundation

/// Raccolta del testo visibile di una viewport di documento.
///
/// Il tipo possiede le decisioni di dominio della cattura: ruoli ammessi ed
/// esclusi, deduplica per chiave normalizzata, scarto di URL e marker di lista,
/// limite di sicurezza a 200.000 caratteri e formato dei blocchi. Il
/// attraversamento dell'albero AX resta all'adapter, che passa ogni elemento
/// come coppia `(role, value)`.
public struct ViewportTextCollector {

    /// Come trattare un elemento durante l'attraversamento.
    ///
    /// `text` indica un ruolo che può fornire un blocco di testo: se espone un
    /// valore non si scende nei figli, perché il valore di un contenitore
    /// include già i discendenti. `skipped` indica un sottoalbero da ignorare
    /// per intero; `container` va attraversato.
    public enum ElementKind: Sendable, Equatable {
        case text
        case skipped
        case container
    }

    /// Limite di sicurezza della viewport, allineato a quello della sessione
    /// continua.
    public static let characterLimit = 200_000

    private static let textRoles: Set<String> = [
        "AXStaticText",
        "AXHeading",
        "AXTextArea",
        "AXTextField",
        "AXWebArea",
        "AXCell",
        "AXRow",
        "AXListItem",
        "AXParagraph"
    ]

    private static let skippedRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuItem",
        "AXMenuBar",
        "AXMenu",
        "AXToolbar",
        "AXScrollBar",
        "AXSlider",
        "AXImage",
        "AXTabGroup",
        "AXTab",
        "AXComboBox",
        "AXDisclosureTriangle",
        "AXProgressIndicator",
        "AXColorWell",
        "AXSplitter",
        "AXGrowArea",
        "AXRuler",
        "AXRulerMarker"
    ]

    private var blocks: [String] = []
    private var seenKeys = Set<String>()
    private var totalCharacters = 0

    public init() {}

    /// Classifica il ruolo senza leggere altri attributi AX.
    public static func kind(of role: String?) -> ElementKind {
        let role = role ?? ""
        if skippedRoles.contains(role) { return .skipped }
        if textRoles.contains(role) { return .text }
        return .container
    }

    /// `true` quando il limite di caratteri è stato raggiunto: l'adapter deve
    /// smettere di leggere l'albero.
    public var isFull: Bool {
        totalCharacters >= Self.characterLimit
    }

    /// Aggiunge un elemento alla viewport. Gli elementi non testuali, i valori
    /// vuoti, i duplicati, gli URL e i soli marker di lista vengono ignorati.
    public mutating func add(role: String?, value: String?) {
        guard !isFull,
              Self.kind(of: role) == .text,
              let value else { return }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !Self.isURL(trimmed),
              !Self.isOnlyListMarker(trimmed) else { return }

        let key = Self.normalizedKey(trimmed)
        guard !key.isEmpty, seenKeys.insert(key).inserted else { return }

        blocks.append(trimmed)
        totalCharacters += trimmed.count
    }

    /// Testo della viewport, con un blocco per riga separato da una riga
    /// vuota; `nil` quando non è stato raccolto nulla.
    public var text: String? {
        let joined = blocks.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func normalizedKey(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("file://")
    }

    private static func isOnlyListMarker(_ text: String) -> Bool {
        guard text.count <= 2 else { return false }
        return text.allSatisfy { "•◦▪‣-–—·".contains($0) }
    }
}
