import MystatCore
import SwiftUI

/// Small language menu under the panel and sidebar: shows the active language's name; clicking lists system language and languages.
struct LanguageMenu: View {
    var size: CGFloat = 12.5

    var body: some View {
        let label = HStack(spacing: 4) {
            Image(systemName: "globe").font(.system(size: size - 1))
            Text(L10n.current.name).font(.system(size: size))
        }
        .foregroundStyle(Theme.ink3)
        if let settings = LanguageSettings.current {
            Menu {
                Picker(selection: Binding(get: { settings.choice ?? "" }, set: { settings.select($0.isEmpty ? nil : $0) })) {
                    ForEach(settings.menuItems) { Text($0.title).tag($0.id) }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: { label }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        } else {
            label   // render mode: appearance only
        }
    }
}

/// Rebuilds the subtree from scratch when the language changes: strings are read from `L10n`, not observed.
struct LanguageRoot<Content: View>: View {
    let content: Content
    var body: some View {
        if let settings = LanguageSettings.current { content.id(settings.code) } else { content }
    }
}
