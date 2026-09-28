import DeviceHubClient
import DeviceHubCore
import DeviceHubMedia
import SwiftUI
import UIKit

struct TargetPicker: View {
    let frame: RemoteDisplayFrame
    let confirm: (Double, Double) -> Void
    @State private var point: CGPoint?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Check that this is Calculator showing 0. Tap the center of 7 in this image, then confirm.")
                    .font(.callout)
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / Double(frame.image.width),
                                    geometry.size.height / Double(frame.image.height))
                    let width = Double(frame.image.width) * scale
                    let height = Double(frame.image.height) * scale
                    Image(uiImage: UIImage(cgImage: frame.image))
                        .resizable().frame(width: width, height: height)
                        .overlay {
                            if let point {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title).foregroundStyle(.cyan)
                                    .position(x: point.x * width, y: point.y * height)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            let x = value.location.x / width, y = value.location.y / height
                            if (0.03...0.75).contains(x), (0.42...0.90).contains(y) {
                                point = CGPoint(x: x, y: y)
                            }
                        })
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .privacySensitive()
                }
                Button("Confirm 7 target") {
                    if let point { confirm(point.x, point.y); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(point == nil)
                Text("Saving the selection sends no input. Arm it from the main screen when connected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Select the test target")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
