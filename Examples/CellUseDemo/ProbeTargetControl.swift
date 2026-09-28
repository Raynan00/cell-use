import PhoneProbeCore
import SwiftUI
import UIKit

/// Read the actual control synchronously, rather than a SwiftUI preference
/// cached during a different layout pass or a window from another scene.
@MainActor
final class ProbeTargetControl {
    weak var button: UIButton?

    func measure() -> ProbeTargetGeometry {
        guard let button, let window = button.window,
              window.windowScene?.activationState == .foregroundActive else {
            return ProbeTargetGeometry(unavailable: .unavailable)
        }
        let screenSpace = window.screen.coordinateSpace
        let target = button.convert(button.bounds, to: screenSpace)
        var visibleArea = window.convert(window.bounds, to: screenSpace)
        var ancestor: UIView? = button
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else {
                return ProbeTargetGeometry(unavailable: .occluded)
            }
            if view.clipsToBounds {
                visibleArea = visibleArea.intersection(view.convert(view.bounds, to: screenSpace))
            }
            ancestor = view.superview
        }
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
        let hit = window.hitTest(point, with: nil)
        return ProbeTargetGeometry(target: target, screen: screenSpace.bounds,
            visibleArea: visibleArea,
            hitTestMatches: hit === button || (hit?.isDescendant(of: button) ?? false))
    }
}

struct ProbeTargetButton: UIViewRepresentable {
    let control: ProbeTargetControl
    let activated: Bool
    let onActivate: () -> Void

    @MainActor final class Coordinator: NSObject {
        var onActivate: () -> Void
        init(onActivate: @escaping () -> Void) { self.onActivate = onActivate }
        @objc func tapped() { onActivate() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onActivate: onActivate) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        control.button = button
        configure(button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        control.button = button
        context.coordinator.onActivate = onActivate
        configure(button)
    }

    private func configure(_ button: UIButton) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = activated ? "Activation observed" : "Test target"
        configuration.image = UIImage(systemName: "scope")
        configuration.imagePadding = 8
        configuration.buttonSize = .large
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = activated ? .systemGreen : .systemIndigo
        button.configuration = configuration
        button.accessibilityIdentifier = "probe.testTarget"
    }
}
