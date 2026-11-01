import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct CustomCommand: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var command: String
}

struct PinnedApplication: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var path: String
}

final class ToolStore: ObservableObject {
    @Published private(set) var commands: [CustomCommand] = []
    @Published private(set) var applications: [PinnedApplication] = []
    @Published private(set) var commandMessage: String?
    private let commandsFile: URL
    private let appsFile: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPanel", isDirectory: true)
        commandsFile = base.appendingPathComponent("commands.json")
        appsFile = base.appendingPathComponent("applications.json")
        if let data = try? Data(contentsOf: commandsFile),
           let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data) {
            commands = decoded
        }
        if let data = try? Data(contentsOf: appsFile),
           let decoded = try? JSONDecoder().decode([PinnedApplication].self, from: data) {
            applications = decoded
        }
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !applications.contains(where: { $0.path == url.path }) {
            applications.append(PinnedApplication(name: url.deletingPathExtension().lastPathComponent,
                                                  path: url.path))
        }
        save(applications, at: appsFile)
    }

    func launch(_ app: PinnedApplication) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                            configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func deleteApplication(_ app: PinnedApplication) {
        applications.removeAll { $0.id == app.id }
        save(applications, at: appsFile)
    }

    func addCommand(name: String, line: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !content.isEmpty else { return }
        commands.append(CustomCommand(name: title, command: content))
        save(commands, at: commandsFile)
    }

    /// Interactive tools (for example ollama run) need a real terminal and stdin.
    /// A .command file passes user-authored shell text without AppleScript quoting.
    static func terminalScript(for command: CustomCommand) -> String {
        """
        #!/bin/zsh -l
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd -- "$HOME"
        \(command.command)
        macpanel_command_status=$?
        /bin/rm -f -- "$0"
        if (( macpanel_command_status != 0 )); then
            printf '\nMacPanel: команда завершилась с кодом %s\n' "$macpanel_command_status"
        fi
        exit "$macpanel_command_status"

        """
    }

    func execute(_ command: CustomCommand) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            commandMessage = "Не найдено приложение Терминал."
            return
        }
        do {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacPanelCommands", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let script = folder.appendingPathComponent(UUID().uuidString + ".command")
            try Self.terminalScript(for: command).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            commandMessage = "Открывается Терминал…"
            NSWorkspace.shared.open([script], withApplicationAt: terminal,
                                   configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.commandMessage = "Не удалось запустить команду: \(error.localizedDescription)"
                        try? FileManager.default.removeItem(at: script)
                    } else {
                        self?.commandMessage = "Команда открыта в Терминале."
                    }
                }
            }
        } catch {
            commandMessage = "Не удалось подготовить команду: \(error.localizedDescription)"
        }
    }

    func deleteCommand(_ command: CustomCommand) {
        commands.removeAll { $0.id == command.id }
        save(commands, at: commandsFile)
    }

    private func save<T: Encodable>(_ value: T, at url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let bytes = try? JSONEncoder().encode(value) else { return }
        try? bytes.write(to: url, options: .atomic)
    }
}
