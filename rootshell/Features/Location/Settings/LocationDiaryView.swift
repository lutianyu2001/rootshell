import SwiftUI
import UIKit
import CoreLocation

struct LocationDiaryView: View {
    @Environment(\.sheetThemeColors) private var sheetThemeColors
    @ObservedObject var manager = LocationDiaryManager.shared
    @State private var showingTrackMap = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location Diary Mode")
                        .font(.headline)

                    Text("Continuously tracks location to keep SSH and Screen Sharing connections and long-running local tasks alive in the background. Shows locations from the last 5 minutes.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "battery.25")
                            .foregroundStyle(.orange)
                        Text("Continuous location tracking increases battery use.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .themedRow()
            }

            Section("Status") {
                HStack {
                    Text("Tracking")
                    Spacer()
                    Text(manager.isEnabled ? String(localized: "Active", comment: "Location tracking status: active") : String(localized: "Inactive", comment: "Location tracking status: inactive"))
                        .foregroundColor(manager.isEnabled ? .green : .secondary)
                }
                .themedRow()

                if manager.isEnabled {
                    HStack {
                        Text("Authorization")
                        Spacer()
                        Text(authorizationStatusText)
                            .foregroundColor(authorizationColor)
                    }
                    .themedRow()

                    if let currentLocation = manager.currentLocation {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currentLocation)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                        .themedRow()
                    }
                }
            }

            if manager.isEnabled {
                Section("Location History (Last 5 Minutes)") {
                    if manager.entries.isEmpty {
                        Text("No locations recorded yet")
                            .foregroundColor(.secondary)
                            .italic()
                            .themedRow()
                    } else {
                        trackMapRow

                        ForEach(manager.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.formattedTimestamp)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if entry.retryCount > 0 {
                                        Text("Retry \(entry.retryCount)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }

                                switch entry.addressState {
                                case .resolved(let address):
                                    Text(address)
                                        .font(.body)

                                case .resolving:
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Resolving address...")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }

                                case .failed:
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.formattedCoordinateString)
                                            .font(.body)
                                        Text("Address unavailable")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .italic()
                                    }
                                }

                                Text(entry.coordinateString)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .themedRow()
                        }
                    }
                }
            }

            if manager.mode == .off || manager.authorizationStatus == .notDetermined {
                Section {
                    Button("Enable Location Tracking") {
                        if manager.authorizationStatus == .notDetermined {
                            manager.requestPermission()
                        }
                        // Default to auto mode when enabling from this view
                        if manager.mode == .off {
                            manager.mode = .autoForRemote
                        }
                    }
                    .themedRow()
                }
            }
        }
        .themedList()
        .navigationTitle("Location Diary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTrackMap) {
            LocationTrackMapSheet(manager: manager)
                .frame(idealWidth: Self.halfWindowWidth)
                .themedSubSheet(sheetThemeColors)
                // On iPad: as tall as a page sheet, half the window wide.
                // iPhone ignores the sizing and shows a sheet as tall as Settings.
                .presentationSizing(.page.fitted(horizontal: true, vertical: false))
        }
    }

    /// Half the width of the foreground window, not below a readable minimum.
    private static var halfWindowWidth: CGFloat? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.keyWindow ?? scene?.windows.first else { return nil }
        let width = window.bounds.width
        return max(width / 2, 360)
    }

    private var trackMapRow: some View {
        Button {
            showingTrackMap = true
        } label: {
            HStack(spacing: 12) {
                LocationTrackThumbnail(entries: manager.entries)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Track")
                    pointCountText
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show Track on Map"))
        .padding(.vertical, 4)
        .themedRow()
    }

    private var pointCountText: Text {
        let count = manager.entries.count
        return count == 1 ? Text("1 point") : Text("\(count) points")
    }

    private var authorizationStatusText: String {
        switch manager.authorizationStatus {
        case .notDetermined:
            return String(localized: "Not Requested", comment: "Location Diary authorization status")
        case .restricted:
            return String(localized: "Restricted", comment: "Location Diary authorization status")
        case .denied:
            return String(localized: "Denied", comment: "Location Diary authorization status")
        #if !os(visionOS)
        case .authorizedAlways:
            return String(localized: "Always", comment: "Location Diary authorization status")
        #endif
        case .authorizedWhenInUse:
            return String(localized: "When In Use", comment: "Location Diary authorization status")
        @unknown default:
            return String(localized: "Unknown", comment: "Location Diary authorization status")
        }
    }

    private var authorizationColor: Color {
        switch manager.authorizationStatus {
        #if os(visionOS)
        case .authorizedWhenInUse:
            return .green
        #else
        case .authorizedAlways, .authorizedWhenInUse:
            return .green
        #endif
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .secondary
        }
    }
}
