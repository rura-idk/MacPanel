import SwiftUI
import AppKit

struct PanelView: View {
    @EnvironmentObject private var model: PanelModel
    @State private var expandedSection: Int? = nil
    var onHeightChange: (CGFloat) -> Void

    private var height: CGFloat { expandedSection == nil ? 250 : 620 }

    private func expanded(_ index: Int) -> Binding<Bool> {
        Binding(get: { expandedSection == index },
                set: { expandedSection = $0 ? index : nil })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MacPanel").font(.headline)
                Spacer()
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Система", icon: "cpu", index: 0)
                    if expandedSection == 0 { SystemPage(monitor: model.system) }
                    Divider()
                    sectionHeader("Буфер обмена", icon: "doc.on.clipboard", index: 1)
                    if expandedSection == 1 { ClipboardPage(store: model.clipboard) }
                    Divider()
                    sectionHeader("Приложения", icon: "square.grid.2x2", index: 2)
                    if expandedSection == 2 {
                        ApplicationsPage(store: model.tools, keepAwake: model.keepAwake)
                    }
                    Divider()
                    sectionHeader("Настройки", icon: "gearshape", index: 3)
                    if expandedSection == 3 {
                        SettingsPage(model: model, clipboard: model.clipboard)
                    }
                }.padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Завершить MacPanel") { NSApp.terminate(nil) }
            }.padding(10)
        }
        .frame(width: 420, height: height)
        .onChange(of: expandedSection) { _, _ in onHeightChange(height) }
        .alert("MacPanel", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) { Button("OK") { model.message = nil } }
        message: { Text(model.message ?? "") }
    }

    private func sectionHeader(_ title: String, icon: String, index: Int) -> some View {
        Button {
            expandedSection = expandedSection == index ? nil : index
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: expandedSection == index ? "chevron.down" : "chevron.right")
                    .font(.caption)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityValue(expandedSection == index ? "Развёрнуто" : "Свёрнуто")
    }
}

/// Standard SwiftUI labeled value, so fonts, spacing, theme and accessibility
/// match native macOS controls instead of custom-drawn widgets.
private struct LabelValueRow: View {
    let name: String
    let icon: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } label: {
            Label(name, systemImage: icon)
        }
        .font(.system(size: 12))
        .padding(.vertical, 5)
    }
}

private struct SystemPage: View {
    @ObservedObject var monitor: SystemMonitor
    var body: some View {
        VStack(spacing: 3) {
            LabelValueRow(name: "Процессор", icon: "cpu",
                          value: String(format: "%.0f %%", monitor.cpuPercent))
            LabelValueRow(name: "Ядра / нагрузка", icon: "square.stack.3d.up",
                          value: String(format: "%d / %.2f", monitor.logicalCores, monitor.loadAverage))
            LabelValueRow(name: "GPU", icon: "cube.transparent",
                          value: monitor.gpuPercent.map { String(format: "%.0f %%", $0) } ?? "—")
                .help("Доступность загрузки GPU зависит от версии macOS")
            Divider().padding(.vertical, 4)
            LabelValueRow(name: "Оперативная память", icon: "memorychip",
                          value: "\(SystemMonitor.bytes(monitor.memoryUsed)) / \(SystemMonitor.bytes(monitor.memoryTotal))")
            LabelValueRow(name: "Swap", icon: "externaldrive",
                          value: monitor.swapUsed.map { SystemMonitor.bytes($0) } ?? "—")
            Divider().padding(.vertical, 4)
            LabelValueRow(name: "Температура", icon: "thermometer",
                          value: monitor.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—")
                .help("Датчик SoC/PMU; не обязательно температура самого горячего ядра")
            if monitor.fans.isEmpty {
                LabelValueRow(name: "Вентилятор", icon: "fanblades", value: "—")
                    .help("SMC может не предоставлять данные на данной версии macOS")
            } else {
                ForEach(monitor.fans) { fan in
                    LabelValueRow(name: monitor.fans.count == 1 ? "Вентилятор" : "Вентилятор \(fan.index + 1)",
                                  icon: "fanblades",
                                  value: String(format: "%.0f об/мин", fan.rpm))
                        .help(fan.target.map { String(format: "Целевая скорость: %.0f об/мин", $0) }
                            ?? "Фактическая скорость вентилятора")
                }
            }
            LabelValueRow(name: "Тепловое состояние", icon: "waveform.path",
                          value: monitor.thermalDescription)
            Divider().padding(.vertical, 4)
            LabelValueRow(name: "Сеть: загрузка", icon: "arrow.down.circle",
                          value: "\(SystemMonitor.bytes(monitor.networkDown))/с")
            LabelValueRow(name: "Сеть: отдача", icon: "arrow.up.circle",
                          value: "\(SystemMonitor.bytes(monitor.networkUp))/с")
            Divider().padding(.vertical, 4)
            LabelValueRow(name: "Хранилище", icon: "internaldrive",
                          value: "\(SystemMonitor.bytes(monitor.diskUsed)) / \(SystemMonitor.bytes(monitor.diskTotal))")
            LabelValueRow(name: "Диск: чтение", icon: "arrow.down.to.line",
                          value: monitor.diskRead.map { "\(SystemMonitor.bytes($0))/с" } ?? "—")
            LabelValueRow(name: "Диск: запись", icon: "arrow.up.to.line",
                          value: monitor.diskWrite.map { "\(SystemMonitor.bytes($0))/с" } ?? "—")
            LabelValueRow(name: "Время работы", icon: "clock",
                          value: SystemMonitor.uptimeString(monitor.uptime))
        }
    }
}

private struct ClipboardPage: View {
    @ObservedObject var store: ClipboardStore
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(store.entries.count) / 15")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Очистить") { confirmClear = true }
                    .disabled(store.entries.isEmpty)
                    .buttonStyle(.bordered)
            }.padding(.horizontal, 10)
            Divider()
            if store.entries.isEmpty {
                ContentUnavailableView("История пуста", systemImage: "doc.on.clipboard")
            }
            ForEach(store.entries) { clip in
                HStack(spacing: 9) {
                    Group {
                        if clip.kind == .image, let image = store.image(for: clip) {
                            Image(nsImage: image)
                                .resizable().scaledToFit().frame(width: 48, height: 38)
                        } else {
                            Image(systemName: clip.kind == .files ? "folder" : "doc.text")
                                .frame(width: 48, height: 38)
                        }
                    }
                    Button {
                        store.restore(clip)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(clip.preview).font(.system(size: 12))
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Text(clip.created, style: .time)
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .help("Скопировать снова")
                    Button { store.remove(clip) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered).help("Удалить запись")
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 53)
                if clip.id != store.entries.last?.id { Divider() }
            }
        }
        .confirmationDialog("Удалить всю историю буфера обмена?", isPresented: $confirmClear) {
            Button("Удалить 15 последних записей", role: .destructive) { store.clear() }
            Button("Отмена", role: .cancel) { }
        }
    }
}

private struct ApplicationsPage: View {
    @ObservedObject var store: ToolStore
    @ObservedObject var keepAwake: KeepAwakeController
    @State private var commandName = ""
    @State private var commandText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer")
                    .frame(width: 20)
                Toggle("Не засыпать", isOn: Binding(
                    get: { keepAwake.isEnabled },
                    set: { keepAwake.setEnabled($0) }
                ))
            }
            .padding(.horizontal, 10)
            Text("Предотвращает сон от бездействия. При закрытой крышке MacBook режим может работать только от сетевого питания и не гарантируется macOS. На аккумуляторе закрытая крышка может усыпить Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            if let error = keepAwake.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Программы").font(.headline)
                Spacer()
                Button { store.addApplication() } label: { Label("Добавить", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            if store.applications.isEmpty {
                Text("Добавьте приложения для быстрого запуска")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
            ForEach(store.applications) { item in
                HStack {
                    Button { store.launch(item) } label: {
                        Label(item.name, systemImage: "app")
                    }.buttonStyle(.bordered)
                    Spacer()
                    Button { store.deleteApplication(item) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.bordered).help("Удалить из панели")
                }.padding(.horizontal, 12).frame(height: 34)
            }
            Divider().padding(.vertical, 4)
            Text("Собственные команды").font(.headline).padding(.horizontal, 10)
            ForEach(store.commands) { command in
                HStack {
                    Button { store.execute(command) } label: {
                        Label(command.name, systemImage: "terminal")
                    }.buttonStyle(.bordered)
                    Spacer()
                    Button { store.deleteCommand(command) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.bordered)
                }.padding(.horizontal, 12).frame(height: 34)
            }
            Text("Команды открываются в Терминале — там видны вывод и запросы ввода.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.commandMessage {
                Text(message).font(.caption).textSelection(.enabled)
            }
            TextField("Название команды", text: $commandName)
                .textFieldStyle(.roundedBorder)
            TextField("Команда терминала", text: $commandText)
                .textFieldStyle(.roundedBorder)
            Button("Сохранить команду") {
                store.addCommand(name: commandName, line: commandText)
                commandName = ""; commandText = ""
            }
            .disabled(commandName.trimmingCharacters(in: .whitespaces).isEmpty ||
                      commandText.trimmingCharacters(in: .whitespaces).isEmpty)
            .buttonStyle(.bordered)
        }.padding(.horizontal, 6)
    }
}

private struct SettingsPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var clipboard: ClipboardStore
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.needsInstallation {
                Label("Для автозапуска перенесите MacPanel в папку «Программы» и запустите оттуда.",
                      systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Запускать при входе в macOS", isOn: Binding(
                get: { model.startOnLogin }, set: { model.setStartOnLogin($0) }
            ))
            if model.loginItemNeedsApproval {
                Label("macOS ожидает подтверждения автозапуска.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                Button("Открыть объекты входа") { model.showLoginItemsSettings() }
                    .buttonStyle(.bordered)
            }
            Toggle("Приостановить историю буфера", isOn: $clipboard.paused)
            Text("История хранится локально: не более 15 копирований, включая изображения. Защищённые записи с пометкой Concealed/Transient не сохраняются.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Удалить историю буфера") { confirmClear = true }
                .buttonStyle(.bordered)
            Divider()
            if let donationURL = ProjectLinks.donationURL {
                Link(destination: donationURL) {
                    Label("Пожертвовать автору", systemImage: "heart")
                }
                .buttonStyle(.bordered)
            }
            Button("Обновить статус автозапуска") { model.refreshLoginItemStatus() }
                .buttonStyle(.bordered)
            Text("MacPanel · для macOS 14+")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .confirmationDialog("Удалить историю?", isPresented: $confirmClear) {
            Button("Удалить", role: .destructive) { model.clipboard.clear() }
            Button("Отмена", role: .cancel) { }
        }
    }
}
