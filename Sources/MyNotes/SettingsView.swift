import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var theme = Theme.shared
    @ObservedObject private var sync = SyncService.shared

    @State private var portText = ""
    @State private var portMessage: String?
    @State private var passphrase = ""
    @State private var passphraseMessage: String?

    @State private var launchAtLogin = false
    @State private var launchMessage: String?
    @State private var needsApproval = false

    private let lightDefault = NSColor.white
    private let darkDefault = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)

    var body: some View {
        Form {
            Section("Запуск") {
                Toggle("Запускать MyNotes при входе в систему", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if needsApproval {
                    HStack {
                        Text("Нужно разрешение в Системных настройках.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Открыть") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let launchMessage {
                    Text(launchMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Основной цвет экранов") {
                colorRow(
                    title: "День (светлая тема)",
                    active: !theme.systemIsDark,
                    binding: binding(\.lightHex, fallback: lightDefault),
                    isCustom: theme.lightHex != nil,
                    reset: { theme.lightHex = nil }
                )
                colorRow(
                    title: "Ночь (тёмная тема)",
                    active: theme.systemIsDark,
                    binding: binding(\.darkHex, fallback: darkDefault),
                    isCustom: theme.darkHex != nil,
                    reset: { theme.darkHex = nil }
                )
                Text("Цвет применяется к окну заметок, вкладкам и боковой панели. Тема переключается вместе с системной (Системные настройки → Оформление). Если выбран тёмный цвет, текст и элементы окна автоматически становятся светлыми, и наоборот.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Синхронизация в локальной сети") {
                Toggle("Принимать запросы синхронизации", isOn: Binding(
                    get: { sync.enabled },
                    set: { sync.setEnabled($0) }
                ))

                HStack {
                    Text("Порт")
                    Spacer()
                    TextField("", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit(applyPort)
                    Button("Применить", action: applyPort)
                }
                if let portMessage {
                    Text(portMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Text(sync.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Пароль синхронизации")
                    Spacer()
                    SecureField("не задан", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(savePassphrase)
                    Button("Сохранить", action: savePassphrase)
                }
                if let passphraseMessage {
                    Text(passphraseMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Имя этого компьютера", value: SyncIdentity.deviceName)

                Text("Порт должен совпадать на всех устройствах (по умолчанию \(SyncConst.defaultPort)). Если задан пароль, данные при передаче шифруются (AES-256-GCM); пароль должен быть одинаковым на обоих устройствах. Пароль хранится в связке ключей macOS. Запрос от другого компьютера выполняется только после вашего подтверждения.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            refreshLaunchState()
            portText = String(sync.port)
            passphrase = SyncSecrets.passphrase
        }
    }

    private func applyPort() {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), sync.apply(port: value) else {
            portMessage = "Укажите число от 1024 до 65535."
            return
        }
        portMessage = nil
        portText = String(value)
    }

    private func savePassphrase() {
        SyncSecrets.passphrase = passphrase
        passphraseMessage = passphrase.isEmpty ? "Пароль удалён: данные передаются без шифрования." : "Пароль сохранён."
    }

    private func colorRow(
        title: String, active: Bool, binding: Binding<Color>, isCustom: Bool, reset: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if active {
                    Text("Сейчас используется")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Сбросить", action: reset)
                .disabled(!isCustom)
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Theme, String?>, fallback: NSColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: theme[keyPath: keyPath].flatMap { NSColor(hex: $0) } ?? fallback) },
            set: { theme[keyPath: keyPath] = NSColor($0).hexString }
        )
    }

    // MARK: - Автозапуск

    private func refreshLaunchState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        needsApproval = status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchMessage = "Не удалось изменить автозапуск: \(error.localizedDescription). Автозапуск работает, когда приложение запущено из папки «Программы»."
        }
        refreshLaunchState()
    }
}
