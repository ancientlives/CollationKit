import Foundation

// MARK: - Built-in sample witness set (the six-edition literary scenario)
//
// The canonical worked example used by the demo and tests: a short two-page passage as it might evolve
// across the witnesses a literary work accrues — manuscript, typescript, proofs, GB & US first editions, and
// a later Uniform edition. It exercises every variant type: a single-word substantive revision (tired→weary,
// cold→bitter), GB/US accidental spelling (grey/gray, harbour/harbor, travellers/travelers), and a sentence
// MOVED across a page boundary (the proofs pull "the lamps were lit…" up before the page break).
//
// Exposed from the library (not just the demo) so the same fixtures drive unit tests and the CLI preview.

public enum Samples {

    public static let sixEditions: [Witness] = [
        Witness(id: "MS", text: """
        The travellers reached the grey harbour at dusk.
        They were tired and the road had been long.

        <!-- page break -->

        The lamps were lit along the quay one by one.
        A cold wind came in from the open sea.
        """),
        Witness(id: "TS", text: """
        The travellers reached the grey harbour at dusk.
        They were weary and the road had been long.

        <!-- page break -->

        The lamps were lit along the quay one by one.
        A cold wind came in from the open sea.
        """),
        Witness(id: "PR", text: """
        The travellers reached the grey harbour at dusk.
        The lamps were lit along the quay one by one.
        They were weary and the road had been long.

        <!-- page break -->

        A cold wind came in from the open sea.
        """),
        Witness(id: "GB1", text: """
        The travellers reached the grey harbour at dusk.
        The lamps were lit along the quay one by one.
        They were weary and the road had been long.

        <!-- page break -->

        A cold wind came in from the open sea.
        """),
        Witness(id: "US1", text: """
        The travelers reached the gray harbor at dusk.
        The lamps were lit along the quay one by one.
        They were weary and the road had been long.

        <!-- page break -->

        A cold wind came in from the open sea.
        """),
        Witness(id: "UNI", text: """
        The travelers reached the gray harbor at dusk.
        The lamps were lit along the quay one by one.
        They were weary and the road had been long.

        <!-- page break -->

        A bitter wind came in from the open sea.
        """),
    ]

    /// The normalizer that treats GB/US spelling as the same reading (so the two first editions don't read as
    /// wall-to-wall substitutions).
    public static let gbUSNormalizer = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
}
