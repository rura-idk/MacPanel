import AppKit
import Combine
import Foundation
import ServiceManagement

final class PanelModel: ObservableObject {
    let clipboard = ClipboardStore()
    let system = SystemMonitor()
    let tools = ToolStore()
    let keepAwake = KeepAwakeController()

    @Published var message: String?
    @Published private(set) var startOnLogin = false
    @Published private(set) var loginItemNeedsApproval = false
    @Published private(set) var needsInstallation = false
    private let firstLaunchSetupKey = "setup.launchAtLoginWasConfigured"
    private var timer: Timer?
    private var elapsedTicks = 0

    init() {
        refreshLoginItemStatus()
    }

    /// One-time registration on the first launch from /Applications.
    /// macOS remains in control: approval may be required in System Settings.
    func configureFirstLaunch() {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path + "/"
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(userApps)
        needsInstallation = !installed
        refreshLoginItemStatus()

        guard installed else { return }
        guard UserDefaults.standard.object(forKey: firstLaunchSetupKey) == nil else { return }
        // Do not override an earlier macOS approval or an existing login item.
        if SMAppService.mainApp.status == .notRegistered {
            do {
                try SMAppService.mainApp.register()
            } catch {
                message = "Автозапуск не настроен автоматически: \(error.localizedDescription). " +
                          "Его можно включить в настройках панели."
            }
        }
        UserDefaults.standard.set(true, forKey: firstLaunchSetupKey)
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        startOnLogin = status == .enabled
        loginItemNeedsApproval = status == .requiresApproval
    }

    func showLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func start() {
        configureFirstLaunch()
        system.update()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.clipboard.captureIfChanged()
            self.elapsedTicks += 1
            if self.elapsedTicks % 4 == 0 {
                self.system.update()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        keepAwake.setEnabled(false)
    }

    func setStartOnLogin(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: firstLaunchSetupKey)
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Не удалось изменить автозапуск: \(error.localizedDescription)"
        }
        refreshLoginItemStatus()
    }
}
