import SwiftUI
import UIKit

struct AgentRunnerPanel: View {
    let run: OnDeviceAgentRun
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent runner: \(run.demo)").font(.headline)
            Text("Status: \(run.report.runner.status.rawValue)")
            Text("Execution: \(run.report.executionMode) · first decision after \(run.report.minimumBackgroundSeconds, specifier: "%.0f") seconds")
                .font(.caption)
            Text("Screens offered: \(run.report.runner.observations.count) · Inputs accepted: \(run.report.runner.acceptedInputCount) · Waits: \(run.report.runner.waitCount)")
                .font(.caption)
            if let reason = run.report.runner.stopReason { Text("Stopped: \(reason)").foregroundStyle(.orange) }
            Text("The scripted client exercises the runtime. Inspect the result yourself; it does not interpret screenshots.")
                .font(.caption)
            if run.demo == "calculator", let image = run.intermediateImage {
                Text("After the first tap - check for 7")
                Image(uiImage: UIImage(cgImage: image.image))
                    .resizable().scaledToFit().frame(maxHeight: 240).privacySensitive()
            }
            if let image = run.finalImage {
                Text(run.demo == "calculator" ? "After the second tap - check for 77" : "After input - inspect the resulting screen")
                Image(uiImage: UIImage(cgImage: image.image))
                    .resizable().scaledToFit().frame(maxHeight: 240).privacySensitive()
                if run.demo == "calculator" {
                    Button("I observed 0, then 7, then 77", action: run.confirmDemoResult)
                        .buttonStyle(.borderedProminent).disabled(run.report.runner.status != .completed)
                } else {
                    Button(run.demo == "swipe" ? "The Settings list scrolled" : "The draft contains the exact test text", action: run.confirmControlResult)
                        .buttonStyle(.borderedProminent).disabled(run.report.runner.status != .completed)
                }
            }
            if run.report.userConfirmedZeroSevenSeventySeven || run.report.userConfirmedControlResult { Text("Your confirmation is recorded. Send View report.").font(.caption) }
        }
    }
}
