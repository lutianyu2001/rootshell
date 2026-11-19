//
//  EmptyWindowBackground.swift
//  rootshell
//
//  What the empty window shows once every tab is closed, while the Empty
//  Window Background setting is on: the mark of the app icon the user
//  picked, drawn faintly as a watermark, and a line on how to open a
//  connection. It draws only; the gestures it describes belong to
//  EmptyStateView, which lies on top of it.
//

import SwiftUI

struct EmptyWindowBackground: View {
    /// A + button is on screen in a tab bar, so the hint can point at it.
    let showsAddButton: Bool
    let textColor: Color
    let isLightTheme: Bool

    @ObservedObject private var iconManager = AppIconManager.shared

    var body: some View {
        VStack(spacing: 28) {
            mark

            Text(hint)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(textColor)
                .frame(maxWidth: 320)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// The mark of the app icon the user picked, as a flat silhouette faint
    /// enough to read as a watermark rather than content, as editors draw
    /// their logo on an empty editor area. A light theme gets it darker than
    /// the background, a dark one lighter: darkening a near-black background
    /// leaves nothing to see.
    private var mark: some View {
        let shape = AppIconMark(kind: iconManager.selectedVariant.mark)
        let size = shape.size(fitting: 160)
        return shape
            .fill(isLightTheme ? Color.black.opacity(0.18) : Color.white.opacity(0.10), style: FillStyle(eoFill: true))
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }

    private var hint: String {
        #if targetEnvironment(macCatalyst)
        showsAddButton
            ? String(localized: "Double-click or click and hold anywhere, or click + in the tab bar, to open a connection.",
                     comment: "Hint on the empty window once every tab is closed (Mac)")
            : String(localized: "Double-click or click and hold anywhere to open a connection.",
                     comment: "Hint on the empty window once every tab is closed, tab bar hidden (Mac)")
        #else
        showsAddButton
            ? String(localized: "Double-tap or touch and hold anywhere, or tap + in the tab bar, to open a connection.",
                     comment: "Hint on the empty window once every tab is closed")
            : String(localized: "Double-tap or touch and hold anywhere to open a connection.",
                     comment: "Hint on the empty window once every tab is closed, tab bar hidden")
        #endif
    }
}
