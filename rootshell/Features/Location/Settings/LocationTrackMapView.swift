//
//  LocationTrackMapView.swift
//  rootshell
//
//  The Location Diary's recorded positions on a map: a static thumbnail for
//  the diary page, and a full interactive map opened from it.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Thumbnail

/// A square snapshot of the track. It is a still image (MKMapSnapshotter), not
/// a live map view, so the diary page costs about as much as with a plain row;
/// the interactive map exists only while its sheet is open.
struct LocationTrackThumbnail: View {
    let entries: [LocationDiaryEntry]
    var side: CGFloat = 112

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct SnapshotKey: Hashable {
        let coordinates: [Double]
        let accuracy: Double
        let isDark: Bool
        let scale: CGFloat
    }

    private var snapshotKey: SnapshotKey {
        SnapshotKey(
            coordinates: entries.flatMap { [$0.coordinate.latitude, $0.coordinate.longitude] },
            accuracy: entries.last?.horizontalAccuracy ?? -1,
            isDark: colorScheme == .dark,
            scale: displayScale
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: snapshotKey) {
            // Entries change several times a minute while the page is open
            // (new fixes, pruning): let a burst settle before rendering.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let rendered = await Self.render(
                entries: entries, side: side, isDark: colorScheme == .dark, scale: displayScale)
            guard !Task.isCancelled else { return }
            image = rendered
        }
    }

    private static func render(
        entries: [LocationDiaryEntry], side: CGFloat, isDark: Bool, scale: CGFloat
    ) async -> UIImage? {
        guard let latest = entries.last else { return nil }
        let mapRect = LocationTrackGeometry.framingRect(for: entries)

        let options = MKMapSnapshotter.Options()
        options.mapRect = mapRect
        options.size = CGSize(width: side, height: side)
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = isDark ? .dark : .light
            traits.displayScale = scale
        }
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let tint = UIColor.systemBlue
        return UIGraphicsImageRenderer(size: options.size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext

            if latest.horizontalAccuracy > 0 {
                let metersPerPoint = mapRect.width / MKMapPointsPerMeterAtLatitude(latest.coordinate.latitude)
                    / side
                let radius = latest.horizontalAccuracy / metersPerPoint
                let center = snapshot.point(for: latest.coordinate)
                let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                cg.setFillColor(tint.withAlphaComponent(0.12).cgColor)
                cg.fillEllipse(in: circle)
                cg.setStrokeColor(tint.withAlphaComponent(0.35).cgColor)
                cg.setLineWidth(1)
                cg.strokeEllipse(in: circle)
            }

            let points = entries.map { snapshot.point(for: $0.coordinate) }
            if points.count > 1 {
                cg.setStrokeColor(tint.cgColor)
                cg.setLineWidth(2.5)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.addLines(between: points)
                cg.strokePath()
            }

            cg.setFillColor(tint.cgColor)
            for point in points.dropLast() {
                cg.fillEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
            }
            if let last = points.last {
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12))
                cg.setFillColor(tint.cgColor)
                cg.fillEllipse(in: CGRect(x: last.x - 4.5, y: last.y - 4.5, width: 9, height: 9))
            }
        }
    }
}

enum LocationTrackGeometry {
    /// A square map rect that holds every point and the latest point's
    /// accuracy circle, at least a kilometer across.
    static func framingRect(for entries: [LocationDiaryEntry]) -> MKMapRect {
        guard let latest = entries.last else { return .world }
        let points = entries.map { MKMapPoint($0.coordinate) }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0

        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(latest.coordinate.latitude)
        let accuracyDiameter = max(latest.horizontalAccuracy, 0) * 2 * 1.15 * pointsPerMeter
        let side = max(max(maxX - minX, maxY - minY) * 1.3, accuracyDiameter, 1000 * pointsPerMeter)

        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        return MKMapRect(x: midX - side / 2, y: midY - side / 2, width: side, height: side)
    }
}

// MARK: - Full map

struct LocationTrackMapSheet: View {
    @ObservedObject var manager: LocationDiaryManager
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        let entries = manager.entries
        NavigationStack {
            Map(position: $position) {
                if let latest = entries.last, latest.horizontalAccuracy > 0 {
                    MapCircle(center: latest.coordinate, radius: latest.horizontalAccuracy)
                        .foregroundStyle(.blue.opacity(0.12))
                        .stroke(.blue.opacity(0.35), lineWidth: 1)
                }
                if entries.count > 1 {
                    MapPolyline(coordinates: entries.map(\.coordinate))
                        .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                ForEach(entries.dropLast()) { entry in
                    Annotation(entry.formattedTimestamp, coordinate: entry.coordinate) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 7, height: 7)
                    }
                    .annotationTitles(.hidden)
                }
                if let latest = entries.last {
                    Annotation(latest.formattedTimestamp, coordinate: latest.coordinate) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 12, height: 12)
                            .padding(3)
                            .background(Circle().fill(.white))
                            .shadow(radius: 2)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No locations recorded yet", systemImage: "mappin.slash")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Approximate positions from the last 5 minutes. Location Diary tracks at low accuracy to save battery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
            }
            .navigationTitle("Location Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { position = .automatic }
                    } label: {
                        Label("Show Entire Track", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
