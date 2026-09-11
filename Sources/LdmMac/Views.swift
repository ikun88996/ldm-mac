import SwiftUI
import AppKit

// MARK: - 主界面

struct ContentView: View {
    @EnvironmentObject var dm: DownloadManager
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
            SettingsView().environmentObject(dm)
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
                Text("Lightning Download Manager · v\(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(dm.engineReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(dm.engineReady ? "引擎就绪" : "引擎未就绪")
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

            Button("暂停全部") { dm.pauseAll() }.controlSize(.small)
            Button("继续全部") { dm.resumeAll() }.controlSize(.small)
            Button("清除已完成") { dm.clearFinished() }.controlSize(.small)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .controlSize(.small)
            .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: 添加栏

    private var addBar: some View {
        HStack(spacing: 10) {
            TextField("粘贴链接：直链文件 / YouTube / B站 / HuggingFace 大模型…", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { submit() }

            Picker("", selection: $mode) {
                ForEach(DownloadMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .labelsHidden()

            Button {
                submit()
            } label: {
                Label("下载", systemImage: "arrow.down")
                    .frame(minWidth: 78)
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
                    Text("还没有任务").font(.headline).foregroundStyle(.secondary)
                    Text("把文件直链或视频页面链接粘到上面的输入框，回车即可")
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
            Button("打开目录") { dm.openDownloadDir() }.controlSize(.small)
            Spacer()
            if let toast = dm.toast {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Text("\(dm.tasks.count) 个任务")
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
                        .help("暂停").controlSize(.small)
                }
                if task.canResume {
                    Button { dm.resume(task) } label: { Image(systemName: "play.fill") }
                        .help("继续").controlSize(.small)
                }
                if task.status == .complete && !task.path.isEmpty {
                    Button { dm.openFile(task) } label: { Image(systemName: "play.rectangle") }
                        .help("打开文件").controlSize(.small)
                }
                if !task.path.isEmpty {
                    Button { dm.reveal(task) } label: { Image(systemName: "folder") }
                        .help("在访达中显示").controlSize(.small)
                }
                Button { dm.copyLink(task) } label: { Image(systemName: "doc.on.doc") }
                    .help("复制链接").controlSize(.small)
                Button { dm.remove(task) } label: { Image(systemName: "trash") }
                    .help("删除任务").controlSize(.small)
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
                    Text("\(task.connections) 连接")
                } else if task.speed > 0 {
                    Text(Fmt.speed(task.speed))
                }
                if !task.isFinished { Text("剩余 \(task.etaText)") }
                if task.status != .complete && !task.message.isEmpty && task.status == .error {
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置").font(.title3.bold()).padding(16)

            Form {
                Section("下载") {
                    HStack {
                        Text(dm.downloadDir).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("选择目录…") { chooseDir() }
                    }
                    Stepper("每任务连接数：\(dm.maxConnections)", value: $dm.maxConnections, in: 1...64)
                    Text("服务器支持分段时，线程越多通常越快；8~16 线程已能跑满大多数带宽。")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("同时下载任务数：\(dm.maxConcurrent)", value: $dm.maxConcurrent, in: 1...10)
                }

                Section("视频") {
                    Picker("画质", selection: Binding(
                        get: { dm.videoQuality },
                        set: { dm.videoQuality = $0 }
                    )) {
                        ForEach(VideoQuality.allCases) { q in Text(q.label).tag(q) }
                    }
                }

                Section("网络") {
                    Toggle("使用代理（YouTube 等需要）", isOn: $dm.proxyEnabled)
                    TextField("代理地址", text: $dm.proxyURL)
                        .disabled(!dm.proxyEnabled)
                    Text("修改后点“重启引擎”生效。检测到本机 Clash 在 127.0.0.1:7897。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("引擎依赖") {
                    let missing = dm.missingDependencies
                    if missing.isEmpty {
                        Label("aria2c / yt-dlp / ffmpeg 已就绪", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("缺少：\(missing.joined(separator: "、"))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("用 Homebrew 一键安装") { dm.installDependencies() }
                        Text("会打开「终端」执行 brew install \(missing.joined(separator: " "))，装完回来点“重启引擎”。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("引擎") {
                    LabeledContent("aria2c", value: AriaEngine.findBinary(named: "aria2c") ?? "未找到")
                        .font(.caption)
                    LabeledContent("yt-dlp", value: VideoEngine.findYtDlp() ?? "未找到")
                        .font(.caption)
                    if let err = dm.engineError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Button("重启引擎（应用线程数/代理改动）") { dm.restartEngine() }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
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
