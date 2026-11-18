//
//  InfoPopoverButton.swift
//  rootshell
//
//  An ⓘ button that explains a setting in a popover, also on iPhone.
//

import SwiftUI

struct InfoPopoverButton: View {
    @Environment(\.sheetThemeColors) private var sheetThemeColors
    @State private var isPresented = false

    private let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        // Borderless keeps a List row from turning into one big button.
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("More Info", comment: "Accessibility label of a setting's info button"))
        .popover(isPresented: $isPresented) {
            Text(text)
                .font(.subheadline)
                // A fixed width lets the popover size itself to the wrapped
                // text; with only a maximum it cut the text off.
                .frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .themedSubSheet(sheetThemeColors)
                .presentationCompactAdaptation(.popover)
        }
    }
}
