import SwiftUI
import AppKit

// MARK: - 主界面

struct ContentView: View {
    @EnvironmentObject var dm: DownloadManager
    @EnvironmentObject var l10n: L10n
    @State private var input: String = ""
    @State private var mode: DownloadMode = .auto
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            addBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 880, minHeight: 560)
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(dm).environmentObject(l10n)
        }
        .onAppear { inputFocused = true }
    }

    // MARK: 顶部状态栏

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("LDM Mac").font(.system(size: 16, weight: .bold))
                Text(l10n.t("app.subtitle") + " · v\(AppInfo.version)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(dm.engineReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(dm.engineReady ? l10n.t("engine.ready") : l10n.t("engine.starting"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let err = dm.engineError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "speedometer").font(.caption)
                Text(Fmt.speed(dm.globalSpeed))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(dm.globalSpeed > 0 ? Color.green : Color.secondary)

            Button(l10n.t("btn.pauseAll")) { dm.pauseAll() }.controlSize(.small)
            Button(l10n.t("btn.resumeAll")) { dm.resumeAll() }.controlSize(.small)
            Button(l10n.t("btn.clearFinished")) { dm.clearFinished() }.controlSize(.small)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .controlSize(.small)
            .help(l10n.t("btn.settings"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: 添加栏

    private var addBar: some View {
        HStack(spacing: 10) {
            TextField(l10n.t("placeholder.url"), text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { submit() }

            Picker("", selection: $mode) {
                ForEach(DownloadMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 270)
            .labelsHidden()

            Button {
                submit()
            } label: {
                Label(l10n.t("btn.download"), systemImage: "arrow.down")
                    .frame(minWidth: 82)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submit() {
        let value = input
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dm.add(value, mode: mode)
        input = ""
        inputFocused = true
    }

    // MARK: 任务列表

    private var content: some View {
        Group {
            if dm.tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text(l10n.t("empty.title")).font(.headline).foregroundStyle(.secondary)
                    Text(l10n.t("empty.hint"))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(dm.tasks) { task in
                            TaskRow(task: task)
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
            Text(dm.downloadDir)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(l10n.t("btn.openDir")) { dm.openDownloadDir() }.controlSize(.small)
            Spacer()
            if let toast = dm.toast {
                Text(toast).font(.caption).foregroundStyle(.green).transition(.opacity)
            }
            Text(l10n.t("tasks.count", dm.tasks.count))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 单条任务

struct TaskRow: View {
    @EnvironmentObject var dm: DownloadManager
    @EnvironmentObject var l10n: L10n
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: task.kind == .video ? "film" : "doc")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(task.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                statusChip

                Spacer(minLength: 8)

                if task.canPause {
                    Button { dm.pause(task) } label: { Image(systemName: "pause.fill") }
                        .help(l10n.t("row.pause")).controlSize(.small)
                }
                if task.canResume {
                    Button { dm.resume(task) } label: { Image(systemName: "play.fill") }
                        .help(l10n.t("row.resume")).controlSize(.small)
                }
                if task.status == .complete && !task.path.isEmpty {
                    Button { dm.openFile(task) } label: { Image(systemName: "play.rectangle") }
                        .help(l10n.t("row.openFile")).controlSize(.small)
                }
                if !task.path.isEmpty {
                    Button { dm.reveal(task) } label: { Image(systemName: "folder") }
                        .help(l10n.t("row.reveal")).controlSize(.small)
                }
                Button { dm.copyLink(task) } label: { Image(systemName: "doc.on.doc") }
                    .help(l10n.t("row.copyLink")).controlSize(.small)
                Button { dm.remove(task) } label: { Image(systemName: "trash") }
                    .help(l10n.t("row.remove")).controlSize(.small)
            }

            ProgressBar(value: task.progress,
                        tint: task.status == .error ? .red :
                              (task.status == .complete ? .green : .accentColor))

            HStack(spacing: 10) {
                if task.totalBytes > 0 {
                    Text("\(Fmt.bytes(task.doneBytes)) / \(Fmt.bytes(task.totalBytes))")
                } else {
                    Text(Fmt.bytes(task.doneBytes))
                }
                if task.kind == .file {
                    Text(Fmt.speed(task.speed))
                    Text(l10n.t("row.connections", task.connections))
                } else if task.speed > 0 {
                    Text(Fmt.speed(task.speed))
                }
                if !task.isFinished { Text(l10n.t("row.remaining", task.etaText)) }
                if task.status == .error && !task.message.isEmpty {
                    Text(task.message).foregroundStyle(.red).lineLimit(1)
                }
                Spacer()
                Text(String(format: "%.1f%%", task.progress * 100))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private var statusChip: some View {
        Text(task.status.label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(chipColor.opacity(0.16))
            .foregroundStyle(chipColor)
            .clipShape(Capsule())
    }

    private var chipColor: Color {
        switch task.status {
        case .active:   return .accentColor
        case .complete: return .green
        case .error:    return .red
        case .paused:   return .orange
        case .waiting:  return .secondary
        }
    }
}

// MARK: - 进度条

struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint.gradient)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .animation(.linear(duration: 0.3), value: value)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var dm: DownloadManager
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.t("settings.title")).font(.title3.bold()).padding(16)

            Form {
                Section(l10n.t("settings.general")) {
                    Picker(l10n.t("settings.language"), selection: $l10n.setting) {
                        ForEach(AppLang.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    Text(l10n.t("settings.languageHint"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(l10n.t("settings.downloads")) {
                    HStack {
                        Text(dm.downloadDir).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(l10n.t("settings.chooseDir")) { chooseDir() }
                    }
                    Stepper(l10n.t("settings.connections", dm.maxConnections), value: $dm.maxConnections, in: 1...64)
                    Text(l10n.t("settings.connectionsHint"))
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper(l10n.t("settings.concurrent", dm.maxConcurrent), value: $dm.maxConcurrent, in: 1...10)
                }

                Section(l10n.t("settings.video")) {
                    Picker(l10n.t("settings.quality"), selection: Binding(
                        get: { dm.videoQuality },
                        set: { dm.videoQuality = $0 }
                    )) {
                        ForEach(VideoQuality.allCases) { q in Text(q.label).tag(q) }
                    }
                }

                Section(l10n.t("settings.network")) {
                    Toggle(l10n.t("settings.proxyToggle"), isOn: $dm.proxyEnabled)
                    TextField(l10n.t("settings.proxyAddr"), text: $dm.proxyURL)
                        .disabled(!dm.proxyEnabled)
                    Text(l10n.t("settings.proxyHint"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(l10n.t("settings.extension")) {
                    if dm.apiPort > 0 {
                        Label(l10n.t("settings.extStatus", dm.apiPort), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(l10n.t("settings.extNotRunning"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if dm.extensionFolder != nil {
                        Button(l10n.t("settings.extOpenFolder")) { dm.openExtensionFolder() }
                    } else {
                        Text(l10n.t("settings.extMissing"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(l10n.t("settings.extHint"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(l10n.t("settings.deps")) {
                    let missing = dm.missingDependencies
                    if missing.isEmpty {
                        Label(l10n.t("settings.depsOk"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(l10n.t("settings.depsMissing", missing.joined(separator: ", ")),
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button(l10n.t("settings.installDeps")) { dm.installDependencies() }
                        Text(l10n.t("settings.installDepsHint", missing.joined(separator: " ")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(l10n.t("settings.engine")) {
                    LabeledContent("aria2c", value: AriaEngine.findBinary(named: "aria2c") ?? "—")
                        .font(.caption)
                    LabeledContent("yt-dlp", value: VideoEngine.findYtDlp() ?? "—")
                        .font(.caption)
                    if let err = dm.engineError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Button(l10n.t("settings.restart")) { dm.restartEngine() }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(l10n.t("btn.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 580, height: 680)
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: dm.downloadDir)
        if panel.runModal() == .OK, let url = panel.url {
            dm.downloadDir = url.path
            dm.restartEngine()
        }
    }
}
