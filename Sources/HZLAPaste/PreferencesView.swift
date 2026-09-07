import SwiftUI
import ServiceManagement
import AppKit

struct PreferencesView: View {
    @AppStorage("historyLimit") private var historyLimit = 200
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showInDock = AppSettings.showInDock
    @State private var fetchLinkPreviews = AppSettings.fetchLinkPreviews
    @State private var snippetExpansionEnabled = AppSettings.snippetExpansionEnabled
    @State private var archiveAfterDays = AppSettings.archiveAfterDays
    @State private var deleteAfterDays = AppSettings.deleteAfterDays
    @State private var excluded = ExcludedApps.list

    var body: some View {
        Form {
            Toggle(isOn: $launchAtLogin) { Label("Launch at login", systemImage: "power") }
                .onChange(of: launchAtLogin) {
                    try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }

            Toggle(isOn: $showInDock) { Label("Show in Dock", systemImage: "dock.rectangle") }
                .onChange(of: showInDock) {
                    AppSettings.showInDock = showInDock
                    NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
                    if showInDock { NSApp.activate(ignoringOtherApps: true) }
                }

            Toggle(isOn: $fetchLinkPreviews) { Label("Fetch link previews", systemImage: "photo.on.rectangle") }
                .onChange(of: fetchLinkPreviews) { AppSettings.fetchLinkPreviews = fetchLinkPreviews }

            Stepper(value: $historyLimit, in: 20...2000, step: 20) {
                Label("History size: \(historyLimit)", systemImage: "clock.arrow.circlepath")
            }

            Toggle(isOn: $snippetExpansionEnabled) { Label("Enable snippet expansion", systemImage: "text.badge.plus") }
                .onChange(of: snippetExpansionEnabled) { AppSettings.snippetExpansionEnabled = snippetExpansionEnabled }

            Section {
                Stepper(value: $archiveAfterDays, in: 1...90) {
                    Label("Archive after \(archiveAfterDays) day\(archiveAfterDays == 1 ? "" : "s")", systemImage: "archivebox")
                }
                .onChange(of: archiveAfterDays) {
                    AppSettings.archiveAfterDays = archiveAfterDays
                    if deleteAfterDays <= archiveAfterDays { deleteAfterDays = archiveAfterDays + 1 }
                }

                Stepper(value: $deleteAfterDays, in: 2...365) {
                    Label("Delete forever after \(deleteAfterDays) days", systemImage: "trash")
                }
                .onChange(of: deleteAfterDays) {
                    deleteAfterDays = max(deleteAfterDays, archiveAfterDays + 1)
                    AppSettings.deleteAfterDays = deleteAfterDays
                }
            } header: {
                Label("Clipboard retention", systemImage: "clock.badge.exclamationmark")
            } footer: {
                Text("Pinned items are never archived or deleted. Storage is always encrypted at rest.")
                    .font(.caption)
                    .foregroundStyle(Theme.silverDim)
            }

            Section {
                List {
                    ForEach(excluded, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                            Spacer()
                            Button("Remove") {
                                ExcludedApps.remove(bundleID)
                                excluded = ExcludedApps.list
                            }
                        }
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Add App…") { addApp() }
            } header: {
                Label("Excluded apps", systemImage: "eye.slash")
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 380)
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        ExcludedApps.add(bundleID)
        excluded = ExcludedApps.list
    }
}
