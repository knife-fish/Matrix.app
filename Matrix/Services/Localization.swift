import Foundation

nonisolated enum AppLanguage: String, Codable, CaseIterable {
    case system
    case zhCN
    case enUS

    var displayName: String {
        switch self {
        case .system: return "System"
        case .zhCN: return "简体中文"
        case .enUS: return "English"
        }
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.contains("zh") ? .zhCN : .enUS
    }

    var localizationIdentifier: String? {
        switch self.resolved {
        case .system:
            return nil
        case .zhCN:
            return "zh-Hans"
        case .enUS:
            return "en"
        }
    }
}

nonisolated enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        let bundle = bundle(for: language)
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }

    static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        let formatString = text(key, language: language)
        return String(format: formatString, locale: appLocale(for: language), arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let localization = language.localizationIdentifier,
              let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

nonisolated func appLocale(for language: AppLanguage) -> Locale {
    switch language.resolved {
    case .zhCN:
        return Locale(identifier: "zh_CN")
    case .enUS, .system:
        return Locale(identifier: "en_US")
    }
}
