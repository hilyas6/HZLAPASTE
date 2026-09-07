import SwiftUI
import AppKit

enum MainTab: String, CaseIterable, Identifiable {
    case preferences = "Preferences"
    case version = "Version"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .preferences: return "gearshape"
        case .version: return "info.circle"
        }
    }
}

@MainActor
final class MainViewModel: ObservableObject {
    @Published var selectedTab: MainTab = .preferences
}

/// The clipboard bar (⌘⇧V) is the app's primary surface — this window is just
/// Preferences/Version, reached via ⌘, from the bar or the menu bar item.
struct MainView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 0) {
            TopNavBar(selected: $viewModel.selectedTab)
            Divider().background(Theme.gold.opacity(0.25))

            switch viewModel.selectedTab {
            case .preferences: PreferencesView()
            case .version: VersionView()
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
    }
}

private struct TopNavBar: View {
    @Binding var selected: MainTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.symbol)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected == tab ? Theme.gold.opacity(0.22) : Color.clear)
                )
                .foregroundStyle(selected == tab ? Theme.gold : Theme.silverDim)
            }
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
    }
}

struct VersionView: View {
    @State private var checking = false
    @State private var message = "You're up to date."

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
            Text("HZLAPaste").font(Theme.headerFont).foregroundStyle(Theme.silver)
            Text("Version \(version) (\(build))").foregroundStyle(Theme.silverDim)

            Button(checking ? "Checking…" : "Check for Updates") { checkForUpdates() }
                .disabled(checking)
                .tint(Theme.gold)

            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.silverDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ponytail: no update server for this local-only build; wire to a real
    // appcast (e.g. Sparkle) if HZLAPaste ever ships outside this Mac.
    private func checkForUpdates() {
        checking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            checking = false
            message = "You're up to date — no update server is configured for this local build."
        }
    }
}
