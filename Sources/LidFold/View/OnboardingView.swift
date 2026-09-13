import SwiftUI

/// The one window shown on first launch (and again from the menu, if
/// Screen Recording still needs to be granted). A single screen: what the
/// app does, the one permission it needs, done.
struct OnboardingView: View {
    let viewModel: OnboardingViewModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: viewModel.sensorAvailable ? "laptopcomputer" : "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(viewModel.sensorAvailable ? "Welcome to \(AppEnvironment.name)" : "This Mac can't fold")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            if viewModel.sensorAvailable {
                if viewModel.permissionGranted {
                    Label("Screen Recording is allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(viewModel.askedForPermission ? "Open System Settings" : "Allow Access") {
                        viewModel.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            Spacer(minLength: 0)
            Button(viewModel.sensorAvailable ? "Done" : "Close") {
                finish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(36)
        .frame(width: 460, height: 420)
        .onAppear { viewModel.probeSensor() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                viewModel.refreshPermissionStatus()
            }
        }
    }

    private var bodyText: String {
        guard viewModel.sensorAvailable else {
            return "\(AppEnvironment.name) needs the lid angle sensor found in MacBook Pro (16-inch, 2019 and later; 14-inch, 2021 and later) and MacBook Air (M2 and later). This Mac reports as \(MacHardwareInfo.identifier)."
        }
        return "When you close your MacBook, the display appears to swing shut over a desktop that hasn't actually moved, blurring and dimming the further it turns. To do that, \(AppEnvironment.name) needs to see the screen while the lid is moving — nothing is ever recorded or stored."
    }
}
