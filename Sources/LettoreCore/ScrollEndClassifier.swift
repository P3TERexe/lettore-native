import Foundation

/// Esito della lettura della scroll bar verticale di un documento.
///
/// `unknown` copre sia l'assenza della scroll bar sia un range non leggibile
/// (per esempio in Safari `value`/`min`/`max` restano a zero su documenti
/// lunghi): non è una prova di fine documento e obbliga a tentare lo scroll.
public enum ScrollEndState: Sendable, Equatable {
    case atEnd
    case notAtEnd
    case unknown
}

/// Classificazione pura della posizione di una scroll bar.
public enum ScrollEndClassifier {

    /// Classifica lo stato della scroll bar a partire dai tre valori AX.
    ///
    /// La tolleranza è proporzionale al range (0,1%) con un minimo assoluto di
    /// 0,0001: assorbe gli arrotondamenti delle scroll bar senza dichiarare la
    /// fine quando resta spazio reale. Un range assente, nullo o invertito
    /// (`max <= min`) restituisce `unknown`, mai `atEnd`.
    public static func classify(value: Double?, minValue: Double?, maxValue: Double?) -> ScrollEndState {
        guard let value, let minValue, let maxValue else { return .unknown }
        guard maxValue > minValue else { return .unknown }

        let epsilon = max(0.000_1, (maxValue - minValue) * 0.001)
        return value >= maxValue - epsilon ? .atEnd : .notAtEnd
    }
}
