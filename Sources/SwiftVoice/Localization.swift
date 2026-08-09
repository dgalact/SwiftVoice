import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case english = "en"
    case russian = "ru"
    case ukrainian = "uk"

    var id: String { rawValue }

    func displayName(in current: AppLanguage = .system) -> String {
        switch self {
        case .system:
            switch current.resolvedCode {
            case "ru": return "Системный по умолчанию"
            case "uk": return "Системна за замовчуванням"
            default: return "System Default"
            }
        case .english: return "English"
        case .russian: return "Русский"
        case .ukrainian: return "Українська"
        }
    }

    var resolvedCode: String {
        if self != .system {
            return rawValue
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ru") {
            return "ru"
        } else if preferred.hasPrefix("uk") {
            return "uk"
        } else {
            return "en"
        }
    }
}

final class LocalizationManager: ObservableObject, @unchecked Sendable {
    static let shared = LocalizationManager()

    @Published private(set) var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        self.language = AppLanguage(rawValue: saved) ?? .system
    }

    @MainActor
    func setLanguage(_ newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        language = newLanguage
    }

    var currentCode: String {
        language.resolvedCode
    }

    nonisolated func string(_ key: String) -> String {
        guard let dict = translations[key] else { return key }
        return dict[currentCode] ?? dict["en"] ?? key
    }

    private let translations: [String: [String: String]] = [
        // Settings Window
        "app_settings_title": [
            "en": "SwiftVoice Settings",
            "ru": "Настройки SwiftVoice",
            "uk": "Налаштування SwiftVoice"
        ],
        "tab_general": [
            "en": "General",
            "ru": "Основные",
            "uk": "Основні"
        ],
        "tab_dictionary": [
            "en": "Dictionary",
            "ru": "Словарь",
            "uk": "Словник"
        ],
        "tab_recognition": [
            "en": "Recognition",
            "ru": "Распознавание",
            "uk": "Розпізнавання"
        ],
        "tab_transcription": [
            "en": "Transcription",
            "ru": "Расшифровка",
            "uk": "Транскрипція"
        ],
        "tab_about": [
            "en": "About",
            "ru": "О программе",
            "uk": "Про програму"
        ],
        "lbl_version": [
            "en": "Version",
            "ru": "Версия",
            "uk": "Версія"
        ],
        "desc_about": [
            "en": "Minimal, fast, and 100% private local voice dictation for macOS powered by whisper.cpp and Metal GPU acceleration.",
            "ru": "Минимальное, быстрое и 100% локальное приложение для голосовой диктовки на macOS на базе whisper.cpp с ускорением Metal.",
            "uk": "Мінімальний, швидкий та 100% локальний додаток для голосової диктовки на macOS на базі whisper.cpp з прискоренням Metal."
        ],
        "lbl_license": [
            "en": "Released under MIT License",
            "ru": "Распространяется по лицензии MIT",
            "uk": "Розповсюджується за ліцензією MIT"
        ],
        "menu_about": [
            "en": "About SwiftVoice",
            "ru": "О программе SwiftVoice",
            "uk": "Про програму SwiftVoice"
        ],

        // General Tab
        "sec_dictation": [
            "en": "Dictation",
            "ru": "Диктовка",
            "uk": "Диктовка"
        ],
        "lbl_language": [
            "en": "Interface Language",
            "ru": "Язык интерфейса",
            "uk": "Мова інтерфейсу"
        ],
        "lbl_push_to_talk": [
            "en": "Push-to-talk",
            "ru": "Push-to-talk",
            "uk": "Push-to-talk"
        ],
        "lbl_recording_hotkey": [
            "en": "Press key combination…",
            "ru": "Нажми сочетание клавиш…",
            "uk": "Натисни комбінацію клавіш…"
        ],
        "btn_reset_default": [
            "en": "Reset",
            "ru": "Сбросить",
            "uk": "Скинути"
        ],
        "warn_system_conflict": [
            "en": "⚠️ This shortcut may conflict with a macOS system hotkey (e.g. Spotlight or Copy).",
            "ru": "⚠️ Этот хоткей может конфликтовать с системным сокращением macOS (например, Spotlight или Копировать).",
            "uk": "⚠️ Ця комбінація може конфліктувати із системним скороченням macOS (наприклад, Spotlight або Копіювати)."
        ],
        "val_push_to_talk": [
            "en": "Hold right ⌥",
            "ru": "Удерживай правый ⌥",
            "uk": "Утримуй правий ⌥"
        ],
        "lbl_processing": [
            "en": "Processing",
            "ru": "Обработка",
            "uk": "Обробка"
        ],
        "val_processing": [
            "en": "Locally on this Mac",
            "ru": "Локально на этом Mac",
            "uk": "Локально на цьому Mac"
        ],
        "lbl_launch_at_login": [
            "en": "Launch SwiftVoice at macOS login",
            "ru": "Запускать SwiftVoice при входе в macOS",
            "uk": "Запускати SwiftVoice при вході в macOS"
        ],
        "lbl_show_overlay": [
            "en": "Show Floating Dictation Overlay",
            "ru": "Показывать плавающий индикатор диктовки",
            "uk": "Показувати плаваючий індикатор диктовки"
        ],
        "lbl_autostart_status": [
            "en": "Auto-launch",
            "ru": "Автозагрузка",
            "uk": "Автозавантаження"
        ],
        "sec_microphone": [
            "en": "Microphone",
            "ru": "Микрофон",
            "uk": "Мікрофон"
        ],
        "lbl_input_device": [
            "en": "Input Device",
            "ru": "Устройство ввода",
            "uk": "Пристрій введення"
        ],

        // Dictionary Tab
        "desc_dictionary": [
            "en": "Terms are prompted to Whisper and normalized before text insertion.",
            "ru": "Термины подсказываются Whisper и нормализуются перед вставкой.",
            "uk": "Терміни підказуються Whisper та нормалізуються перед вставкою."
        ],
        "col_canonical": [
            "en": "Canonical Spelling",
            "ru": "Правильное написание",
            "uk": "Правильне написання"
        ],
        "col_aliases": [
            "en": "Comma-separated spoken variants",
            "ru": "Варианты произношения через запятую",
            "uk": "Варіанти вимови через кому"
        ],
        "ph_canonical": [
            "en": "FortiGate",
            "ru": "FortiGate",
            "uk": "FortiGate"
        ],
        "ph_aliases": [
            "en": "fortigate, forti gate",
            "ru": "фортигейт, форти гейт",
            "uk": "фортігейт, форті гейт"
        ],
        "btn_add": [
            "en": "Add",
            "ru": "Добавить",
            "uk": "Додати"
        ],
        "btn_remove": [
            "en": "Remove",
            "ru": "Удалить",
            "uk": "Видалити"
        ],
        "btn_import": [
            "en": "Import…",
            "ru": "Импорт…",
            "uk": "Імпорт…"
        ],
        "btn_export": [
            "en": "Export…",
            "ru": "Экспорт…",
            "uk": "Експорт…"
        ],
        "dlg_import_title": [
            "en": "Import Dictionary",
            "ru": "Импорт словаря",
            "uk": "Імпорт словника"
        ],
        "dlg_export_title": [
            "en": "Export Dictionary",
            "ru": "Экспорт словаря",
            "uk": "Експорт словника"
        ],
        "msg_import_success": [
            "en": "Successfully imported terms into dictionary.",
            "ru": "Импорт терминов в словарь успешно завершен.",
            "uk": "Імпорт термінів у словник успішно завершено."
        ],
        "txt_terms_count": [
            "en": "terms",
            "ru": "терминов",
            "uk": "термінів"
        ],
        "txt_new_word": [
            "en": "New term",
            "ru": "Новое слово",
            "uk": "Нове слово"
        ],

        // Recognition Tab
        "sec_engine": [
            "en": "Engine",
            "ru": "Движок",
            "uk": "Двигун"
        ],
        "sec_model": [
            "en": "Model",
            "ru": "Модель",
            "uk": "Модель"
        ],
        "lbl_status_ready": [
            "en": "Ready",
            "ru": "Готова к работе",
            "uk": "Готова до роботи"
        ],
        "lbl_status_not_downloaded": [
            "en": "Not downloaded",
            "ru": "Не скачана",
            "uk": "Не завантажена"
        ],
        "btn_download_model": [
            "en": "Download Model",
            "ru": "Скачать модель",
            "uk": "Завантажити модель"
        ],
        "btn_cancel_download": [
            "en": "Cancel Download",
            "ru": "Отменить скачивание",
            "uk": "Скасувати завантаження"
        ],
        "sec_privacy": [
            "en": "Privacy",
            "ru": "Конфиденциальность",
            "uk": "Конфіденційність"
        ],
        "lbl_language_detect": [
            "en": "Language",
            "ru": "Язык",
            "uk": "Мова"
        ],
        "val_auto_detect": [
            "en": "Detected automatically",
            "ru": "Определяется автоматически",
            "uk": "Визначається автоматично"
        ],
        "desc_privacy": [
            "en": "Recording and recognition are performed locally. Network APIs are not used.",
            "ru": "Запись и распознавание выполняются локально. Сетевые API не используются.",
            "uk": "Запис та розпізнавання виконуються локально. Мережеві API не використовуються."
        ],
        "btn_choose": [
            "en": "Choose…",
            "ru": "Выбрать…",
            "uk": "Обрати…"
        ],
        "val_not_selected": [
            "en": "Not selected",
            "ru": "Не выбрано",
            "uk": "Не обрано"
        ],
        "dlg_choose_whisper": [
            "en": "Select whisper-cli executable",
            "ru": "Выбери исполняемый файл whisper-cli",
            "uk": "Обери виконуваний файл whisper-cli"
        ],
        "dlg_choose_model": [
            "en": "Select Whisper model file",
            "ru": "Выбери модель Whisper",
            "uk": "Обери модель Whisper"
        ],

        // File Transcription Tab
        "file_description": [
            "en": "Transcribe an audio file locally with the selected Whisper model. The personal dictation dictionary is not applied.",
            "ru": "Расшифровка аудиофайла выполняется локально выбранной моделью Whisper. Личный словарь диктовки не применяется.",
            "uk": "Транскрипція аудіофайлу виконується локально вибраною моделлю Whisper. Особистий словник диктування не застосовується."
        ],
        "file_drop_prompt": [
            "en": "Choose or drop an audio file here",
            "ru": "Выбери или перетащи сюда аудиофайл",
            "uk": "Обери або перетягни сюди аудіофайл"
        ],
        "file_choose": [
            "en": "Choose File…",
            "ru": "Выбрать файл…",
            "uk": "Обрати файл…"
        ],
        "file_choose_title": [
            "en": "Choose Audio File",
            "ru": "Выбери аудиофайл",
            "uk": "Обери аудіофайл"
        ],
        "file_transcribe": [
            "en": "Transcribe",
            "ru": "Расшифровать",
            "uk": "Транскрибувати"
        ],
        "file_copy": [
            "en": "Copy",
            "ru": "Скопировать",
            "uk": "Скопіювати"
        ],
        "file_save": [
            "en": "Save TXT…",
            "ru": "Сохранить TXT…",
            "uk": "Зберегти TXT…"
        ],
        "file_clear": [
            "en": "Clear",
            "ru": "Очистить",
            "uk": "Очистити"
        ],
        "file_save_title": [
            "en": "Save Transcription",
            "ru": "Сохранить расшифровку",
            "uk": "Зберегти транскрипцію"
        ],
        "file_status_preparing": [
            "en": "Preparing audio…",
            "ru": "Подготавливаю аудио…",
            "uk": "Готую аудіо…"
        ],
        "file_status_transcribing": [
            "en": "Transcribing audio…",
            "ru": "Распознаю аудио…",
            "uk": "Розпізнаю аудіо…"
        ],
        "file_status_ready": [
            "en": "Transcription ready",
            "ru": "Расшифровка готова",
            "uk": "Транскрипція готова"
        ],
        "err_file_unsupported": [
            "en": "Unsupported audio format. Choose WAV, M4A, MP3, or AAC.",
            "ru": "Формат аудио не поддерживается. Выбери WAV, M4A, MP3 или AAC.",
            "uk": "Формат аудіо не підтримується. Обери WAV, M4A, MP3 або AAC."
        ],
        "err_file_conversion": [
            "en": "Could not prepare the audio file for Whisper.",
            "ru": "Не удалось подготовить аудиофайл для Whisper.",
            "uk": "Не вдалося підготувати аудіофайл для Whisper."
        ],

        // Menu items
        "menu_checking": [
            "en": "Checking configuration…",
            "ru": "Проверяю конфигурацию…",
            "uk": "Перевіряю конфігурацію…"
        ],
        "menu_mic_detecting": [
            "en": "Microphone: detecting…",
            "ru": "Микрофон: определяю…",
            "uk": "Мікрофон: визначаю…"
        ],
        "menu_mic_prefix": [
            "en": "Microphone:",
            "ru": "Микрофон:",
            "uk": "Мікрофон:"
        ],
        "menu_mic_unknown": [
            "en": "unknown",
            "ru": "неизвестен",
            "uk": "невідомий"
        ],
        "menu_ready": [
            "en": "Ready for dictation",
            "ru": "Готов к диктовке",
            "uk": "Готовий до диктовки"
        ],
        "menu_recording": [
            "en": "Recording audio…",
            "ru": "Записываю аудио…",
            "uk": "Записую аудіо…"
        ],
        "menu_transcribing": [
            "en": "Transcribing audio…",
            "ru": "Распознаю аудио…",
            "uk": "Розпізнаю аудіо…"
        ],
        "menu_ptt_hint": [
            "en": "Push-to-talk",
            "ru": "Push-to-talk",
            "uk": "Push-to-talk"
        ],
        "menu_settings": [
            "en": "Settings…",
            "ru": "Настройки…",
            "uk": "Налаштування…"
        ],
        "menu_select_whisper": [
            "en": "Select whisper-cli…",
            "ru": "Выбрать whisper-cli…",
            "uk": "Обрати whisper-cli…"
        ],
        "menu_select_model": [
            "en": "Select model…",
            "ru": "Выбрать модель…",
            "uk": "Обрати модель…"
        ],
        "menu_quit": [
            "en": "Quit SwiftVoice",
            "ru": "Завершить SwiftVoice",
            "uk": "Завершити SwiftVoice"
        ],

        // Status Descriptions & Errors
        "status_enabled": [
            "en": "Enabled",
            "ru": "Включён",
            "uk": "Увімкнено"
        ],
        "status_requires_approval": [
            "en": "Requires approval in Login Items",
            "ru": "Требуется разрешение в Login Items",
            "uk": "Потрібен дозвіл у Login Items"
        ],
        "status_not_found": [
            "en": "SwiftVoice must be in Applications folder",
            "ru": "SwiftVoice должен находиться в папке Applications",
            "uk": "SwiftVoice повинен знаходитися в папці Applications"
        ],
        "status_disabled": [
            "en": "Disabled",
            "ru": "Выключен",
            "uk": "Вимкнено"
        ],
        "err_rec_failed": [
            "en": "Audio device failed to start recording.",
            "ru": "Аудиоустройство не начало запись.",
            "uk": "Аудіопристрій не розпочав запис."
        ],
        "err_mic_perm": [
            "en": "Grant SwiftVoice microphone access in Privacy & Security → Microphone.",
            "ru": "Разреши SwiftVoice доступ к микрофону в Privacy & Security → Microphone.",
            "uk": "Надай SwiftVoice дозвіл на доступ до мікрофона в Privacy & Security → Microphone."
        ],
        "err_rec_short": [
            "en": "Recording shorter than 0.5s. Pause slightly between starting and stopping.",
            "ru": "Запись короче 0,5 секунды. Удерживай паузу между включением и выключением диктовки.",
            "uk": "Запис коротший за 0,5 секунди. Утримуй паузу між увімкненням та вимкненням диктовки."
        ],
        "err_missing_config": [
            "en": "whisper-cli or model is not selected.",
            "ru": "Не выбраны whisper-cli или модель.",
            "uk": "Не обрано whisper-cli або модель."
        ],
        "err_transcription_failed": [
            "en": "whisper-cli failed with error:",
            "ru": "whisper-cli завершился с ошибкой:",
            "uk": "whisper-cli завершився з помилкою:"
        ],
        "err_empty_transcription": [
            "en": "Model returned no text.",
            "ru": "Модель не вернула текст.",
            "uk": "Модель не повернула текст."
        ],
        "err_acc_perm": [
            "en": "Grant SwiftVoice control access in Privacy & Security → Accessibility.",
            "ru": "Разреши SwiftVoice управлять компьютером в Privacy & Security → Accessibility.",
            "uk": "Надай SwiftVoice дозвіл на керування комп'ютером в Privacy & Security → Accessibility."
        ]
    ]
}
