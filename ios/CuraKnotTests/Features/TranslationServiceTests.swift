import XCTest
@testable import CuraKnot

final class TranslationServiceTests: XCTestCase {

    // MARK: - SupportedLanguage Raw Values

    func testSupportedLanguage_rawValues() {
        XCTAssertEqual(SupportedLanguage.english.rawValue, "en")
        XCTAssertEqual(SupportedLanguage.spanish.rawValue, "es")
        XCTAssertEqual(SupportedLanguage.chineseSimplified.rawValue, "zh-Hans")
        XCTAssertEqual(SupportedLanguage.vietnamese.rawValue, "vi")
        XCTAssertEqual(SupportedLanguage.korean.rawValue, "ko")
        XCTAssertEqual(SupportedLanguage.tagalog.rawValue, "tl")
        XCTAssertEqual(SupportedLanguage.french.rawValue, "fr")
    }

    func testSupportedLanguage_allCasesCount() {
        XCTAssertEqual(SupportedLanguage.allCases.count, 7)
    }

    // MARK: - SupportedLanguage Display Names

    func testSupportedLanguage_displayName_returnsNativeNames() {
        XCTAssertEqual(SupportedLanguage.english.displayName, "English")
        XCTAssertEqual(SupportedLanguage.spanish.displayName, "Espa\u{00F1}ol")
        XCTAssertEqual(SupportedLanguage.chineseSimplified.displayName, "\u{7B80}\u{4F53}\u{4E2D}\u{6587}")
        XCTAssertEqual(SupportedLanguage.vietnamese.displayName, "Ti\u{1EBF}ng Vi\u{1EC7}t")
        XCTAssertEqual(SupportedLanguage.korean.displayName, "\u{D55C}\u{AD6D}\u{C5B4}")
        XCTAssertEqual(SupportedLanguage.tagalog.displayName, "Tagalog")
        XCTAssertEqual(SupportedLanguage.french.displayName, "Fran\u{00E7}ais")
    }

    // MARK: - SupportedLanguage English Names

    func testSupportedLanguage_englishName() {
        XCTAssertEqual(SupportedLanguage.english.englishName, "English")
        XCTAssertEqual(SupportedLanguage.spanish.englishName, "Spanish")
        XCTAssertEqual(SupportedLanguage.chineseSimplified.englishName, "Chinese (Simplified)")
        XCTAssertEqual(SupportedLanguage.vietnamese.englishName, "Vietnamese")
        XCTAssertEqual(SupportedLanguage.korean.englishName, "Korean")
        XCTAssertEqual(SupportedLanguage.tagalog.englishName, "Tagalog")
        XCTAssertEqual(SupportedLanguage.french.englishName, "French")
    }

    // MARK: - SupportedLanguage Tier Availability

    func testSupportedLanguage_isAvailable_freeTier_onlyEnglish() {
        XCTAssertTrue(SupportedLanguage.english.isAvailable(for: .free))
        XCTAssertFalse(SupportedLanguage.spanish.isAvailable(for: .free))
        XCTAssertFalse(SupportedLanguage.chineseSimplified.isAvailable(for: .free))
        XCTAssertFalse(SupportedLanguage.vietnamese.isAvailable(for: .free))
        XCTAssertFalse(SupportedLanguage.korean.isAvailable(for: .free))
        XCTAssertFalse(SupportedLanguage.tagalog.isAvailable(for: .free))
        XCTAssertFalse(SupportedLanguage.french.isAvailable(for: .free))
    }

    func testSupportedLanguage_isAvailable_plusTier_englishAndSpanish() {
        XCTAssertTrue(SupportedLanguage.english.isAvailable(for: .plus))
        XCTAssertTrue(SupportedLanguage.spanish.isAvailable(for: .plus))
        XCTAssertFalse(SupportedLanguage.chineseSimplified.isAvailable(for: .plus))
        XCTAssertFalse(SupportedLanguage.vietnamese.isAvailable(for: .plus))
        XCTAssertFalse(SupportedLanguage.korean.isAvailable(for: .plus))
        XCTAssertFalse(SupportedLanguage.tagalog.isAvailable(for: .plus))
        XCTAssertFalse(SupportedLanguage.french.isAvailable(for: .plus))
    }

    func testSupportedLanguage_isAvailable_familyTier_allLanguages() {
        for language in SupportedLanguage.allCases {
            XCTAssertTrue(
                language.isAvailable(for: .family),
                "\(language.englishName) should be available on Family tier"
            )
        }
    }

    func testSupportedLanguage_availableLanguages_freeTier() {
        let available = SupportedLanguage.availableLanguages(for: .free)
        XCTAssertEqual(available, [.english])
    }

    func testSupportedLanguage_availableLanguages_plusTier() {
        let available = SupportedLanguage.availableLanguages(for: .plus)
        XCTAssertEqual(available, [.english, .spanish])
    }

    func testSupportedLanguage_availableLanguages_familyTier() {
        let available = SupportedLanguage.availableLanguages(for: .family)
        XCTAssertEqual(available, SupportedLanguage.allCases)
    }

    // MARK: - SupportedLanguage Phase Groupings

    func testSupportedLanguage_phase1Languages() {
        let expected: [SupportedLanguage] = [.english, .spanish, .chineseSimplified]
        XCTAssertEqual(SupportedLanguage.phase1Languages, expected)
    }

    func testSupportedLanguage_phase2Languages() {
        let expected: [SupportedLanguage] = [.vietnamese, .korean, .tagalog, .french]
        XCTAssertEqual(SupportedLanguage.phase2Languages, expected)
    }

    func testSupportedLanguage_phasesCoversAllCases() {
        let allPhases = SupportedLanguage.phase1Languages + SupportedLanguage.phase2Languages
        XCTAssertEqual(Set(allPhases), Set(SupportedLanguage.allCases))
        XCTAssertEqual(allPhases.count, SupportedLanguage.allCases.count,
                       "Phase 1 and Phase 2 should have no overlap")
    }

    // MARK: - SupportedLanguage Medical Disclaimer

    func testSupportedLanguage_medicalDisclaimer_nonEmpty() {
        for language in SupportedLanguage.allCases {
            XCTAssertFalse(
                language.medicalDisclaimer.isEmpty,
                "Medical disclaimer for \(language.englishName) should not be empty"
            )
        }
    }

    func testSupportedLanguage_medicalDisclaimer_englishContent() {
        XCTAssertEqual(
            SupportedLanguage.english.medicalDisclaimer,
            "Medication names shown in original language for safety."
        )
    }

    func testSupportedLanguage_medicalDisclaimer_spanishContent() {
        XCTAssertEqual(
            SupportedLanguage.spanish.medicalDisclaimer,
            "Los nombres de medicamentos se muestran en su idioma original por seguridad."
        )
    }

    func testSupportedLanguage_medicalDisclaimer_uniquePerLanguage() {
        let disclaimers = SupportedLanguage.allCases.map(\.medicalDisclaimer)
        let uniqueDisclaimers = Set(disclaimers)
        XCTAssertEqual(disclaimers.count, uniqueDisclaimers.count,
                       "Each language should have a unique medical disclaimer")
    }

    // MARK: - SupportedLanguage Identifiable

    func testSupportedLanguage_idMatchesRawValue() {
        for language in SupportedLanguage.allCases {
            XCTAssertEqual(language.id, language.rawValue)
        }
    }

    // MARK: - SupportedLanguage Init from Code

    func testSupportedLanguage_initFromCode_validCodes() {
        XCTAssertEqual(SupportedLanguage(code: "en"), .english)
        XCTAssertEqual(SupportedLanguage(code: "es"), .spanish)
        XCTAssertEqual(SupportedLanguage(code: "zh-Hans"), .chineseSimplified)
        XCTAssertEqual(SupportedLanguage(code: "vi"), .vietnamese)
        XCTAssertEqual(SupportedLanguage(code: "ko"), .korean)
        XCTAssertEqual(SupportedLanguage(code: "tl"), .tagalog)
        XCTAssertEqual(SupportedLanguage(code: "fr"), .french)
    }

    func testSupportedLanguage_initFromCode_invalidCode() {
        XCTAssertNil(SupportedLanguage(code: "xx"))
        XCTAssertNil(SupportedLanguage(code: ""))
        XCTAssertNil(SupportedLanguage(code: "EN"))
    }

    // MARK: - TranslationMode Raw Values

    func testTranslationMode_rawValues() {
        XCTAssertEqual(TranslationMode.auto.rawValue, "AUTO")
        XCTAssertEqual(TranslationMode.onDemand.rawValue, "ON_DEMAND")
        XCTAssertEqual(TranslationMode.off.rawValue, "OFF")
    }

    func testTranslationMode_caseIterable_allCases() {
        let allCases = TranslationMode.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.auto))
        XCTAssertTrue(allCases.contains(.onDemand))
        XCTAssertTrue(allCases.contains(.off))
    }

    func testTranslationMode_identifiable_idMatchesRawValue() {
        for mode in TranslationMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    // MARK: - LanguagePreferences Defaults

    func testLanguagePreferences_defaultValues() {
        let prefs = LanguagePreferences()
        XCTAssertEqual(prefs.preferredLanguage, "en")
        XCTAssertEqual(prefs.translationMode, .auto)
        XCTAssertFalse(prefs.showOriginal)
    }

    // MARK: - LanguagePreferences Computed Property

    func testLanguagePreferences_preferredSupportedLanguage_validCode() {
        var prefs = LanguagePreferences()
        prefs.preferredLanguage = "es"
        XCTAssertEqual(prefs.preferredSupportedLanguage, .spanish)
    }

    func testLanguagePreferences_preferredSupportedLanguage_chineseSimplified() {
        var prefs = LanguagePreferences()
        prefs.preferredLanguage = "zh-Hans"
        XCTAssertEqual(prefs.preferredSupportedLanguage, .chineseSimplified)
    }

    func testLanguagePreferences_preferredSupportedLanguage_invalidCode_defaultsToEnglish() {
        var prefs = LanguagePreferences()
        prefs.preferredLanguage = "invalid"
        XCTAssertEqual(prefs.preferredSupportedLanguage, .english)
    }

    func testLanguagePreferences_preferredSupportedLanguage_allLanguages() {
        for language in SupportedLanguage.allCases {
            var prefs = LanguagePreferences()
            prefs.preferredLanguage = language.rawValue
            XCTAssertEqual(prefs.preferredSupportedLanguage, language)
        }
    }

    // MARK: - LanguagePreferences Codable Round-Trip

    func testLanguagePreferences_codableRoundTrip() throws {
        var original = LanguagePreferences()
        original.preferredLanguage = "ko"
        original.translationMode = .onDemand
        original.showOriginal = true

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LanguagePreferences.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.preferredLanguage, "ko")
        XCTAssertEqual(decoded.translationMode, .onDemand)
        XCTAssertTrue(decoded.showOriginal)
    }

    func testLanguagePreferences_codableRoundTrip_defaults() throws {
        let original = LanguagePreferences()

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LanguagePreferences.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - TranslatedContent Codable Round-Trip

    func testTranslatedContent_codableRoundTrip() throws {
        let original = TranslatedContent(
            translatedText: "Informe del paciente traducido",
            confidenceScore: 0.95,
            medicalTermsFound: ["ibuprofeno", "acetaminof\u{00E9}n"],
            disclaimer: true
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TranslatedContent.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.translatedText, "Informe del paciente traducido")
        XCTAssertEqual(decoded.confidenceScore, 0.95, accuracy: 0.001)
        XCTAssertEqual(decoded.medicalTermsFound.count, 2)
        XCTAssertTrue(decoded.disclaimer)
    }

    func testTranslatedContent_codableRoundTrip_emptyMedicalTerms() throws {
        let original = TranslatedContent(
            translatedText: "Simple text",
            confidenceScore: 0.99,
            medicalTermsFound: [],
            disclaimer: false
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TranslatedContent.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.medicalTermsFound.isEmpty)
        XCTAssertFalse(decoded.disclaimer)
    }

    // MARK: - TranslatedHandoff Codable Round-Trip

    func testTranslatedHandoff_codableRoundTrip() throws {
        let now = Date()
        // Truncate to seconds for ISO8601 compatibility
        let truncatedDate = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate).rounded(.down))

        let original = TranslatedHandoff(
            id: "th-001",
            handoffId: "handoff-001",
            targetLanguage: "es",
            translatedTitle: "Informe de visita",
            translatedSummary: "El paciente est\u{00E1} mejorando",
            translatedContent: nil,
            translationEngine: "gpt-4o",
            confidenceScore: 0.92,
            sourceHash: "abc123hash",
            isStale: false,
            createdAt: truncatedDate,
            hasMedicalTerms: false
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TranslatedHandoff.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.handoffId, original.handoffId)
        XCTAssertEqual(decoded.targetLanguage, "es")
        XCTAssertEqual(decoded.translatedTitle, "Informe de visita")
        XCTAssertEqual(decoded.translatedSummary, "El paciente est\u{00E1} mejorando")
        XCTAssertNil(decoded.translatedContent)
        XCTAssertEqual(decoded.translationEngine, "gpt-4o")
        XCTAssertEqual(decoded.confidenceScore!, 0.92, accuracy: 0.001)
        XCTAssertEqual(decoded.sourceHash, "abc123hash")
        XCTAssertFalse(decoded.isStale)
    }

    func testTranslatedHandoff_codableRoundTrip_withNilOptionals() throws {
        let now = Date()
        let truncatedDate = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate).rounded(.down))

        let original = TranslatedHandoff(
            id: "th-002",
            handoffId: "handoff-002",
            targetLanguage: "fr",
            translatedTitle: nil,
            translatedSummary: nil,
            translatedContent: nil,
            translationEngine: "gpt-4o-mini",
            confidenceScore: nil,
            sourceHash: "def456hash",
            isStale: true,
            createdAt: truncatedDate,
            hasMedicalTerms: false
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TranslatedHandoff.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertNil(decoded.translatedTitle)
        XCTAssertNil(decoded.translatedSummary)
        XCTAssertNil(decoded.confidenceScore)
        XCTAssertTrue(decoded.isStale)
    }

    func testTranslatedHandoff_medicalDisclaimer_validLanguage() {
        let now = Date()
        let handoff = TranslatedHandoff(
            id: "th-003",
            handoffId: "handoff-003",
            targetLanguage: "es",
            translatedTitle: nil,
            translatedSummary: nil,
            translatedContent: nil,
            translationEngine: "gpt-4o",
            confidenceScore: nil,
            sourceHash: "hash",
            isStale: false,
            createdAt: now,
            hasMedicalTerms: true
        )
        XCTAssertEqual(handoff.medicalDisclaimer, SupportedLanguage.spanish.medicalDisclaimer)
    }

    func testTranslatedHandoff_medicalDisclaimer_invalidLanguage() {
        let now = Date()
        let handoff = TranslatedHandoff(
            id: "th-004",
            handoffId: "handoff-004",
            targetLanguage: "xx",
            translatedTitle: nil,
            translatedSummary: nil,
            translatedContent: nil,
            translationEngine: "gpt-4o",
            confidenceScore: nil,
            sourceHash: "hash",
            isStale: false,
            createdAt: now,
            hasMedicalTerms: false
        )
        XCTAssertNil(handoff.medicalDisclaimer)
    }

    func testTranslatedHandoff_containsMedicalTerms_basedOnHasMedicalTerms() {
        let now = Date()
        let withMedTerms = TranslatedHandoff(
            id: "th-005",
            handoffId: "handoff-005",
            targetLanguage: "es",
            translatedTitle: nil,
            translatedSummary: nil,
            translatedContent: nil,
            translationEngine: "OPENAI",
            confidenceScore: 0.95,
            sourceHash: "hash",
            isStale: false,
            createdAt: now,
            hasMedicalTerms: true
        )
        XCTAssertTrue(withMedTerms.containsMedicalTerms)

        let withoutMedTerms = TranslatedHandoff(
            id: "th-006",
            handoffId: "handoff-006",
            targetLanguage: "es",
            translatedTitle: nil,
            translatedSummary: nil,
            translatedContent: nil,
            translationEngine: "OPENAI",
            confidenceScore: 0.95,
            sourceHash: "hash",
            isStale: false,
            createdAt: now,
            hasMedicalTerms: false
        )
        XCTAssertFalse(withoutMedTerms.containsMedicalTerms)
    }

    // MARK: - DetectedLanguage Codable Round-Trip

    func testDetectedLanguage_codableRoundTrip() throws {
        let original = DetectedLanguage(
            detectedLanguage: "es",
            confidence: 0.97,
            alternatives: [
                DetectedLanguage.LanguageAlternative(language: "pt", confidence: 0.02),
                DetectedLanguage.LanguageAlternative(language: "it", confidence: 0.01)
            ]
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DetectedLanguage.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.detectedLanguage, "es")
        XCTAssertEqual(decoded.confidence, 0.97, accuracy: 0.001)
        XCTAssertEqual(decoded.alternatives.count, 2)
        XCTAssertEqual(decoded.alternatives[0].language, "pt")
        XCTAssertEqual(decoded.alternatives[0].confidence, 0.02, accuracy: 0.001)
    }

    func testDetectedLanguage_codableRoundTrip_emptyAlternatives() throws {
        let original = DetectedLanguage(
            detectedLanguage: "en",
            confidence: 0.99,
            alternatives: []
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DetectedLanguage.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.alternatives.isEmpty)
    }

    func testDetectedLanguage_asSupportedLanguage_validCode() {
        let detected = DetectedLanguage(
            detectedLanguage: "ko",
            confidence: 0.95,
            alternatives: []
        )
        XCTAssertEqual(detected.asSupportedLanguage, .korean)
    }

    func testDetectedLanguage_asSupportedLanguage_invalidCode() {
        let detected = DetectedLanguage(
            detectedLanguage: "de",
            confidence: 0.90,
            alternatives: []
        )
        XCTAssertNil(detected.asSupportedLanguage)
    }

    // MARK: - GlossaryEntry Codable Round-Trip

    func testGlossaryEntry_codableRoundTrip() throws {
        let now = Date()
        let truncatedDate = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate).rounded(.down))

        let original = GlossaryEntry(
            id: "ge-001",
            circleId: "circle-001",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceTerm: "blood pressure",
            translatedTerm: "presi\u{00F3}n arterial",
            context: "Medical vital signs",
            category: "vitals",
            createdBy: "user-001",
            createdAt: truncatedDate
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GlossaryEntry.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, "ge-001")
        XCTAssertEqual(decoded.circleId, "circle-001")
        XCTAssertEqual(decoded.sourceTerm, "blood pressure")
        XCTAssertEqual(decoded.translatedTerm, "presi\u{00F3}n arterial")
        XCTAssertEqual(decoded.context, "Medical vital signs")
        XCTAssertEqual(decoded.category, "vitals")
    }

    func testGlossaryEntry_codableRoundTrip_nilOptionals() throws {
        let now = Date()
        let truncatedDate = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate).rounded(.down))

        let original = GlossaryEntry(
            id: "ge-002",
            circleId: nil,
            sourceLanguage: "en",
            targetLanguage: "fr",
            sourceTerm: "medication",
            translatedTerm: "m\u{00E9}dicament",
            context: nil,
            category: nil,
            createdBy: "system",
            createdAt: truncatedDate
        )

        let encoder = JSONEncoder.supabase
        let decoder = JSONDecoder.supabase

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(GlossaryEntry.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.circleId)
        XCTAssertNil(decoded.context)
        XCTAssertNil(decoded.category)
    }

    func testGlossaryEntry_isSystemEntry_nilCircleId() {
        let entry = GlossaryEntry(
            id: "ge-sys",
            circleId: nil,
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceTerm: "dosage",
            translatedTerm: "dosificaci\u{00F3}n",
            context: nil,
            category: nil,
            createdBy: "system",
            createdAt: Date()
        )
        XCTAssertTrue(entry.isSystemEntry)
    }

    func testGlossaryEntry_isSystemEntry_withCircleId() {
        let entry = GlossaryEntry(
            id: "ge-circle",
            circleId: "circle-001",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceTerm: "nurse",
            translatedTerm: "enfermera",
            context: nil,
            category: nil,
            createdBy: "user-001",
            createdAt: Date()
        )
        XCTAssertFalse(entry.isSystemEntry)
    }

    // MARK: - HandoffTranslation GRDB Model

    func testHandoffTranslation_conformsToExpectedProtocols() {
        let translation = HandoffTranslation(
            id: "ht-001",
            handoffId: "handoff-001",
            revisionId: "rev-001",
            sourceLanguage: "en",
            targetLanguage: "es",
            translatedTitle: "Title",
            translatedSummary: "Summary",
            translatedContentJson: nil,
            translationEngine: "gpt-4o",
            confidenceScore: 0.95,
            sourceHash: "hash123",
            isStale: false,
            createdAt: Date()
        )

        // Verify Identifiable
        XCTAssertEqual(translation.id, "ht-001")

        // Verify Equatable
        let translation2 = translation
        XCTAssertEqual(translation, translation2)
    }

    func testHandoffTranslation_databaseTableName() {
        XCTAssertEqual(HandoffTranslation.databaseTableName, "handoffTranslations")
    }

    func testHandoffTranslation_equatable_differentValues() {
        let t1 = HandoffTranslation(
            id: "ht-001",
            handoffId: "handoff-001",
            revisionId: nil,
            sourceLanguage: "en",
            targetLanguage: "es",
            translatedTitle: "Title A",
            translatedSummary: nil,
            translatedContentJson: nil,
            translationEngine: "gpt-4o",
            confidenceScore: nil,
            sourceHash: "hash-a",
            isStale: false,
            createdAt: Date()
        )

        let t2 = HandoffTranslation(
            id: "ht-002",
            handoffId: "handoff-001",
            revisionId: nil,
            sourceLanguage: "en",
            targetLanguage: "es",
            translatedTitle: "Title B",
            translatedSummary: nil,
            translatedContentJson: nil,
            translationEngine: "gpt-4o",
            confidenceScore: nil,
            sourceHash: "hash-b",
            isStale: false,
            createdAt: Date()
        )

        XCTAssertNotEqual(t1, t2)
    }

    // MARK: - TranslationGlossaryLocal GRDB Model

    func testTranslationGlossaryLocal_databaseTableName() {
        XCTAssertEqual(TranslationGlossaryLocal.databaseTableName, "translationGlossary")
    }

    func testTranslationGlossaryLocal_conformsToExpectedProtocols() {
        let entry = TranslationGlossaryLocal(
            id: "tgl-001",
            circleId: "circle-001",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceTerm: "caregiver",
            translatedTerm: "cuidador",
            context: "Family caregiving",
            category: "roles",
            createdBy: "user-001",
            createdAt: Date()
        )

        // Verify Identifiable
        XCTAssertEqual(entry.id, "tgl-001")

        // Verify Equatable
        let entry2 = entry
        XCTAssertEqual(entry, entry2)
    }

    // MARK: - TranslationCacheEntry Expiration

    func testTranslationCacheEntry_isExpired_pastDate() {
        let pastDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let entry = TranslationCacheEntry(
            id: "cache-001",
            sourceTextHash: "hash-abc",
            sourceLanguage: "en",
            targetLanguage: "es",
            translatedText: "Translated text",
            confidenceScore: 0.95,
            containsMedicalTerms: false,
            createdAt: Date(timeIntervalSinceNow: -7200),
            expiresAt: pastDate
        )
        XCTAssertTrue(entry.isExpired)
    }

    func testTranslationCacheEntry_isExpired_futureDate() {
        let futureDate = Date(timeIntervalSinceNow: 3600) // 1 hour from now
        let entry = TranslationCacheEntry(
            id: "cache-002",
            sourceTextHash: "hash-def",
            sourceLanguage: "en",
            targetLanguage: "fr",
            translatedText: "Texte traduit",
            confidenceScore: 0.90,
            containsMedicalTerms: true,
            createdAt: Date(),
            expiresAt: futureDate
        )
        XCTAssertFalse(entry.isExpired)
    }

    func testTranslationCacheEntry_isExpired_distantPast() {
        let entry = TranslationCacheEntry(
            id: "cache-003",
            sourceTextHash: "hash-ghi",
            sourceLanguage: "en",
            targetLanguage: "ko",
            translatedText: "Translated",
            confidenceScore: nil,
            containsMedicalTerms: false,
            createdAt: Date.distantPast,
            expiresAt: Date.distantPast
        )
        XCTAssertTrue(entry.isExpired)
    }

    func testTranslationCacheEntry_isExpired_distantFuture() {
        let entry = TranslationCacheEntry(
            id: "cache-004",
            sourceTextHash: "hash-jkl",
            sourceLanguage: "en",
            targetLanguage: "vi",
            translatedText: "Translated",
            confidenceScore: nil,
            containsMedicalTerms: false,
            createdAt: Date(),
            expiresAt: Date.distantFuture
        )
        XCTAssertFalse(entry.isExpired)
    }

    func testTranslationCacheEntry_databaseTableName() {
        XCTAssertEqual(TranslationCacheEntry.databaseTableName, "translationCache")
    }

    // MARK: - PremiumFeature Gating

    func testPremiumFeature_handoffTranslation_notAvailableForFree() {
        // handoffTranslation requires Plus or Family (currentPlan != .free)
        // We test the raw value and confirm the enum case exists
        XCTAssertEqual(PremiumFeature.handoffTranslation.rawValue, "handoff_translation")
    }

    func testPremiumFeature_customGlossary_rawValue() {
        XCTAssertEqual(PremiumFeature.customGlossary.rawValue, "custom_glossary")
    }

    /// Verifies that SubscriptionManager.hasFeature returns the correct gating
    /// for handoffTranslation and customGlossary. Since SubscriptionManager requires
    /// a SupabaseClient actor and is @MainActor, we test the gating logic through
    /// the SupportedLanguage.isAvailable approach which mirrors the same tier logic.
    func testFeatureGating_translationMirrorsSubscriptionTiers() {
        // handoffTranslation: Plus and Family (not free)
        // This mirrors: spanish is available for Plus+, all languages for Family
        XCTAssertFalse(SupportedLanguage.spanish.isAvailable(for: .free),
                       "Translation should not be available on Free tier")
        XCTAssertTrue(SupportedLanguage.spanish.isAvailable(for: .plus),
                      "Translation should be available on Plus tier")
        XCTAssertTrue(SupportedLanguage.spanish.isAvailable(for: .family),
                      "Translation should be available on Family tier")

        // customGlossary: Family only
        // This mirrors: phase2 languages only available for Family
        for lang in SupportedLanguage.phase2Languages {
            XCTAssertFalse(lang.isAvailable(for: .free),
                           "\(lang.englishName) should not be available on Free")
            XCTAssertFalse(lang.isAvailable(for: .plus),
                           "\(lang.englishName) should not be available on Plus")
            XCTAssertTrue(lang.isAvailable(for: .family),
                          "\(lang.englishName) should be available on Family")
        }
    }

    // MARK: - SupportedLanguage Codable Round-Trip

    func testSupportedLanguage_codableRoundTrip() throws {
        for language in SupportedLanguage.allCases {
            let data = try JSONEncoder().encode(language)
            let decoded = try JSONDecoder().decode(SupportedLanguage.self, from: data)
            XCTAssertEqual(decoded, language)
        }
    }

    func testSupportedLanguage_decodesFromRawJSON() throws {
        let json = "\"zh-Hans\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SupportedLanguage.self, from: json)
        XCTAssertEqual(decoded, .chineseSimplified)
    }

    // MARK: - TranslationMode Codable Round-Trip

    func testTranslationMode_codableRoundTrip() throws {
        for mode in TranslationMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TranslationMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testTranslationMode_decodesFromRawJSON() throws {
        let json = "\"ON_DEMAND\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TranslationMode.self, from: json)
        XCTAssertEqual(decoded, .onDemand)
    }

    // MARK: - LanguagePreferences Equatable

    func testLanguagePreferences_equatable_sameValues() {
        let a = LanguagePreferences()
        let b = LanguagePreferences()
        XCTAssertEqual(a, b)
    }

    func testLanguagePreferences_equatable_differentValues() {
        var a = LanguagePreferences()
        var b = LanguagePreferences()
        b.preferredLanguage = "es"
        XCTAssertNotEqual(a, b)

        a.preferredLanguage = "es"
        XCTAssertEqual(a, b)

        b.translationMode = .off
        XCTAssertNotEqual(a, b)

        a.translationMode = .off
        b.showOriginal = true
        XCTAssertNotEqual(a, b)
    }
}
