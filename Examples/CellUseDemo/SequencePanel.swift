import SwiftUI
import UIKit

struct SequencePanel: View {
    let model: ProbeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Two-step result: 0 to 7 to 77").font(.headline)
            Text("Sequence: \(model.sequence.status)").font(.callout)
            if let reason = model.sequence.stopReason {
                Text("Stopped: \(reason)").foregroundStyle(.orange)
            }
            Text("Two fixed taps with acknowledged delivery and a fresh screen between them. You verify the numbers; no OCR or reference matching is used.").font(.caption)
            ForEach(model.sequence.actions, id: \.step) { action in
                HStack {
                    Image(systemName: action.commandAccepted ? "checkmark.circle.fill" : "circle")
                    Text("Tap \(action.step): \(action.commandAccepted ? "accepted" : action.commandAttempted ? "attempted" : "not attempted")")
                    if let seconds = action.commandBackgroundSeconds {
                        Text("\(seconds, specifier: "%.2f") s").monospacedDigit()
                    }
                }.font(.callout)
            }
            if let intermediate = model.sequenceIntermediate {
                Text("Screenshot between taps - check for 7").font(.subheadline.bold())
                Image(uiImage: UIImage(cgImage: intermediate.image))
                    .resizable().scaledToFit().frame(maxHeight: 240).privacySensitive()
            }
            if let result = model.sequenceResult {
                Text("After the second tap - check for 77").font(.subheadline.bold())
                Image(uiImage: UIImage(cgImage: result.image))
                    .resizable().scaledToFit().frame(maxHeight: 300).privacySensitive()
                Button("I observed 0, then 7, then 77", action: model.confirmSequenceResult)
                    .buttonStyle(.borderedProminent)
                Text(model.sequence.userConfirmedZeroSevenSeventySeven
                     ? "Your confirmation is recorded. Send View report."
                     : "Confirm only if that sequence happened. A changed image alone does not prove 77.")
                    .font(.caption)
            }
        }
    }
}
