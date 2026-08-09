import AppKit
import SwiftUI
@preconcurrency import Translation

enum LiveTranslationSettings {
    static let enabledKey = "translateLiveTextToRussian"
    static let targetLanguageKey = "liveTranslationTargetLanguage"
    static let defaultTargetLanguage = "ru"
}

enum LiveTextAppearanceSettings {
    static let fontSizeKey = "liveTextFontSize"
    static let defaultFontSize = 16.0
    static let minimumFontSize = 11.0
    static let maximumFontSize = 32.0
}

@MainActor
final class LiveTranscriptionModel: ObservableObject {
    @Published var text = ""
    @Published var translatedText = ""
    @Published var translationRevision = 0
    @Published var translationError = ""
    @Published var targetLanguageIdentifier = LiveTranslationSettings.defaultTargetLanguage
    @Published var targetLanguageName = ""
    @Published var status = ""
    @Published var isRecording = false
    @Published var stopHint = ""
    @Published var fontSize = UserDefaults.standard.object(
        forKey: LiveTextAppearanceSettings.fontSizeKey
    ) as? Double ?? LiveTextAppearanceSettings.defaultFontSize
    var translationEnabled = false
    var rawText = ""

    private var completedTranslationRevision = 0
    private var translationWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func requestTranslation() -> Int? {
        guard translationEnabled,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        translationError = ""
        translationRevision += 1
        return translationRevision
    }

    func completeTranslation(_ translation: String, revision: Int) {
        guard revision == translationRevision else {
            resolveWaiter(revision)
            return
        }
        translatedText = LiveTextParagraphFormatter.format(translation)
        translationError = ""
        completedTranslationRevision = revision
        resolveWaiter(revision)
    }

    func failTranslation(_ error: Error, revision: Int) {
        guard revision == translationRevision else {
            resolveWaiter(revision)
            return
        }
        translationError = error.localizedDescription
        completedTranslationRevision = revision
        resolveWaiter(revision)
    }

    func waitForTranslation(revision: Int) async {
        guard completedTranslationRevision < revision else { return }
        await withCheckedContinuation { continuation in
            translationWaiters[revision] = continuation
        }
    }

    private func resolveWaiter(_ revision: Int) {
        translationWaiters.removeValue(forKey: revision)?.resume()
    }

    func changeFontSize(by delta: Double) {
        setFontSize(fontSize + delta)
    }

    func resetFontSize() {
        setFontSize(LiveTextAppearanceSettings.defaultFontSize)
    }

    private func setFontSize(_ size: Double) {
        fontSize = min(
            LiveTextAppearanceSettings.maximumFontSize,
            max(LiveTextAppearanceSettings.minimumFontSize, size)
        )
        UserDefaults.standard.set(fontSize, forKey: LiveTextAppearanceSettings.fontSizeKey)
    }
}

@MainActor
final class LiveTranscriptionWindowController: NSWindowController {
    let model = LiveTranscriptionModel()

    init() {
        let rootView = LiveTranscriptionView(model: model)
        let hosting = NSHostingController(rootView: rootView)
        let panel = NSPanel(contentViewController: hosting)
        panel.title = LocalizationManager.shared.string("live_title")
        panel.setContentSize(NSSize(width: 520, height: 280))
        panel.styleMask = [.titled, .closable, .resizable, .nonactivatingPanel]
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.center()
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func prepare(stopHint: String) {
        model.text = ""
        model.rawText = ""
        model.translatedText = ""
        model.translationError = ""
        model.translationEnabled = UserDefaults.standard.bool(
            forKey: LiveTranslationSettings.enabledKey
        )
        model.targetLanguageIdentifier = UserDefaults.standard.string(
            forKey: LiveTranslationSettings.targetLanguageKey
        ) ?? LiveTranslationSettings.defaultTargetLanguage
        let displayLocale = Locale(identifier: LocalizationManager.shared.currentCode)
        model.targetLanguageName = displayLocale.localizedString(
            forIdentifier: model.targetLanguageIdentifier
        ) ?? model.targetLanguageIdentifier
        window?.setContentSize(
            model.translationEnabled
                ? NSSize(width: 640, height: 520)
                : NSSize(width: 520, height: 280)
        )
        model.stopHint = "\(stopHint) / Esc"
        model.status = LocalizationManager.shared.string("live_loading")
        model.isRecording = false
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func begin() {
        model.status = LocalizationManager.shared.string("live_listening")
        model.isRecording = true
    }

    func append(_ chunk: String) {
        model.rawText = Self.merging(model.rawText, with: chunk)
        model.text = LiveTextParagraphFormatter.format(model.rawText)
        _ = model.requestTranslation()
        model.status = LocalizationManager.shared.string("live_listening")
    }

    func showProcessing() {
        model.status = LocalizationManager.shared.string("live_processing")
    }

    func finish() {
        model.isRecording = false
        model.status = LocalizationManager.shared.string("live_ready")
    }

    func finishTranslation() async -> String? {
        guard let revision = model.requestTranslation() else { return nil }
        await model.waitForTranslation(revision: revision)
        let translation = model.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return translation.isEmpty ? nil : translation
    }

    func present() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    private static func merging(_ existing: String, with incoming: String) -> String {
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return next }
        guard !next.isEmpty else { return current }

        let currentWords = current.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let nextWords = next.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let maximumOverlap = min(20, currentWords.count, nextWords.count)
        var overlap = 0
        if maximumOverlap > 0 {
            for count in stride(from: maximumOverlap, through: 1, by: -1) {
                let suffix = currentWords.suffix(count).map(normalizedWord)
                let prefix = nextWords.prefix(count).map(normalizedWord)
                if suffix == prefix {
                    overlap = count
                    break
                }
            }
        }
        let remainder = nextWords.dropFirst(overlap).joined(separator: " ")
        return remainder.isEmpty ? current : "\(current) \(remainder)"
    }

    private static func normalizedWord(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}

private struct LiveTranscriptionView: View {
    @ObservedObject var model: LiveTranscriptionModel
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(model.isRecording ? Color.red : Color.green)
                    .frame(width: 9, height: 9)
                Text(model.status)
                    .font(.headline)
                Spacer()
                Text(model.stopHint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button {
                    model.changeFontSize(by: -1)
                } label: {
                    Text("A−")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("-", modifiers: .command)
                .help(loc.string("live_decrease_font"))
                Button {
                    model.changeFontSize(by: 1)
                } label: {
                    Text("A+")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("+", modifiers: .command)
                .help(loc.string("live_increase_font"))
                Button("") {
                    model.resetFontSize()
                }
                .labelsHidden()
                .frame(width: 0, height: 0)
                .keyboardShortcut("0", modifiers: .command)
            }

            if model.translationEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.string("live_original"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    textPane(model.text, placeholder: loc.string("live_waiting_text"))

                    Text(
                        String(
                            format: loc.string("live_translation_format"),
                            model.targetLanguageName
                        )
                    )
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    textPane(
                        model.translatedText,
                        placeholder: model.translationError.isEmpty
                            ? loc.string("live_waiting_translation")
                            : model.translationError
                    )
                }
                .modifier(LiveTranslationModifier(model: model))
            } else {
                textPane(model.text, placeholder: loc.string("live_waiting_text"))
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 220)
    }

    private func textPane(_ text: String, placeholder: String) -> some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: model.fontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

@available(macOS 15.0, *)
private struct LiveTranslationModifier: ViewModifier {
    @ObservedObject var model: LiveTranscriptionModel
    @State private var configuration = TranslationSession.Configuration(
        source: nil,
        target: Locale.Language(identifier: LiveTranslationSettings.defaultTargetLanguage)
    )

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                let revision = model.translationRevision
                let source = model.rawText
                guard revision > 0, !source.isEmpty else { return }
                do {
                    let response = try await session.translate(source)
                    await MainActor.run {
                        model.completeTranslation(response.targetText, revision: revision)
                    }
                } catch {
                    await MainActor.run {
                        model.failTranslation(error, revision: revision)
                    }
                }
            }
            .onChange(of: model.translationRevision) { _, _ in
                configuration.invalidate()
            }
            .onChange(of: model.targetLanguageIdentifier, initial: true) { _, identifier in
                configuration = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: identifier)
                )
            }
    }
}

private enum LiveTextParagraphFormatter {
    private static let targetParagraphLength = 420
    private static let maximumSentencesPerParagraph = 4

    static func format(_ text: String) -> String {
        let normalized = text
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "" }

        let sentences = splitIntoSentences(normalized)
        guard sentences.count > 1 else { return normalized }

        var paragraphs: [String] = []
        var current: [String] = []
        var currentLength = 0

        for sentence in sentences {
            let wouldExceedLength = !current.isEmpty
                && currentLength + 1 + sentence.count > targetParagraphLength
            let reachedSentenceLimit = current.count >= maximumSentencesPerParagraph

            if wouldExceedLength || reachedSentenceLimit {
                paragraphs.append(current.joined(separator: " "))
                current = []
                currentLength = 0
            }

            current.append(sentence)
            currentLength += sentence.count + (current.count > 1 ? 1 : 0)
        }

        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var reachedEnding = false
        let endings: Set<Character> = [".", "!", "?", "…"]
        let trailingPunctuation: Set<Character> = ["\"", "'", "”", "’", ")", "]"]

        for character in text {
            if character.isWhitespace {
                if reachedEnding {
                    let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty {
                        sentences.append(sentence)
                    }
                    current = ""
                    reachedEnding = false
                } else if !current.isEmpty && current.last?.isWhitespace != true {
                    current.append(" ")
                }
                continue
            }

            current.append(character)
            if endings.contains(character) {
                reachedEnding = true
            } else if reachedEnding && !trailingPunctuation.contains(character) {
                reachedEnding = false
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }
        return sentences
    }
}
