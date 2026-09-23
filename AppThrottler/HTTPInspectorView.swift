import SwiftUI

// MARK: - HTTP Inspector View

struct HTTPInspectorView: View {
    let app: AppProcess
    @ObservedObject var inspector: HTTPInspector
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    @State private var showReplay = false
    @State private var showCurlImport = false
    @State private var showMockEditor = false
    @State private var showDiffPicker = false
    @State private var diffLeft: HTTPTransaction?
    @State private var diffRight: HTTPTransaction?
    @State private var curlImportText = ""
    @State private var replayResult: HTTPTransaction?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            // Filter bar
            filterBar

            Divider()

            // Content
            HSplitView {
                // Request list
                requestList
                    .frame(minWidth: 300, idealWidth: 380)

                // Detail panel
                detailPanel
                    .frame(minWidth: 300, idealWidth: 400)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if inspector.isCapturing {
                Button { inspector.stopCapture() } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered).tint(theme.error)
            } else {
                Button { inspector.startCapture(pid: app.pid) } label: {
                    Label("开始捕获", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).tint(theme.success)
            }

            Divider().frame(height: 20)

            Button { showCurlImport = true } label: {
                Label("导入 cURL", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderless).font(.caption)

            Button { showMockEditor = true } label: {
                Label("Mock 规则", systemImage: "wand.and.stars")
                    .foregroundStyle(inspector.mockEnabled ? theme.warning : theme.textSecondary)
            }
            .buttonStyle(.borderless).font(.caption)

            Button {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "session_\(app.name).json"
                if panel.runModal() == .OK, let url = panel.url {
                    inspector.saveSession(to: url)
                }
            } label: {
                Label("保存会话", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless).font(.caption)

            Button {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url {
                    inspector.loadSession(from: url)
                }
            } label: {
                Label("加载会话", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless).font(.caption)

            Spacer()

            Text("\(inspector.transactions.count) 请求")
                .font(.caption.monospacedDigit()).foregroundStyle(theme.textSecondary)

            Button { inspector.clearTransactions() } label: {
                Text("清空").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 4) {
            // Text + Method + Status filter
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(theme.textSecondary)
                TextField("过滤 URL/Host...", text: $inspector.filterText)
                    .textFieldStyle(.plain).font(.caption)

                Picker("", selection: $inspector.filterMethod) {
                    Text("全部方法").tag("")
                    ForEach(["GET", "POST", "PUT", "DELETE", "PATCH"], id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .frame(width: 90).font(.caption)

                Picker("", selection: $inspector.filterStatus) {
                    Text("全部状态").tag("")
                    Text("2xx 成功").tag("2xx")
                    Text("3xx 重定向").tag("3xx")
                    Text("4xx 客户端错误").tag("4xx")
                    Text("5xx 服务端错误").tag("5xx")
                }
                .frame(width: 110).font(.caption)

                Picker("", selection: $inspector.filterType) {
                    Text("全部类型").tag("")
                    ForEach(ResourceType.allCases) { t in
                        HStack(spacing: 4) {
                            Image(systemName: t.icon).font(.caption2)
                            Text(t.rawValue)
                        }.tag(t.rawValue)
                    }
                }
                .frame(width: 120).font(.caption)
            }

            // Type count badges
            let counts = inspector.typeCounts()
            if !counts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        typeBadge("", label: "全部", count: inspector.transactions.count,
                                  active: inspector.filterType.isEmpty)
                        ForEach(counts, id: \.0) { type, count in
                            typeBadge(type.rawValue, label: type.rawValue, count: count,
                                      active: inspector.filterType == type.rawValue)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 22)
            }
        }
        .padding(.vertical, 6)
        .background(theme.surface)
    }

    private func typeBadge(_ type: String, label: String, count: Int, active: Bool) -> some View {
        Button {
            inspector.filterType = active ? "" : type
        } label: {
            HStack(spacing: 3) {
                if !type.isEmpty, let rt = ResourceType(rawValue: type) {
                    Image(systemName: rt.icon).font(.system(size: 9))
                }
                Text(label).font(.system(size: 10))
                Text("\(count)").font(.system(size: 9, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background((active ? theme.accent : theme.textSecondary).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(active ? theme.accent.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Request List

    private var requestList: some View {
        List(inspector.filteredTransactions, selection: $inspector.selectedTransaction) { tx in
            HTTPTransactionRow(tx: tx)
                .tag(tx)
                .contextMenu {
                    Button("复制 cURL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tx.curlCommand, forType: .string)
                    }
                    Button("重放请求") {
                        Task {
                            replayResult = await inspector.replay(tx)
                            showReplay = true
                        }
                    }
                    Divider()
                    Button("选为 Diff 左侧") { diffLeft = tx }
                    Button("选为 Diff 右侧") { diffRight = tx }
                }
        }
        .listStyle(.plain)
        .sheet(isPresented: $showCurlImport) {
            curlImportSheet
        }
        .sheet(isPresented: $showMockEditor) {
            mockEditorSheet
        }
        .sheet(isPresented: $showReplay) {
            replaySheet
        }
        .sheet(isPresented: $showDiffPicker) {
            diffSheet
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let tx = inspector.selectedTransaction {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Request info
                    GroupBox("请求") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(tx.method).font(.caption.bold().monospaced())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(methodColor(tx.method).opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(tx.fullURL).font(.caption).lineLimit(2)
                                Spacer()
                                if let code = tx.statusCode {
                                    Text("\(code)").font(.caption.bold().monospaced())
                                        .foregroundStyle(statusColor(code))
                                }
                            }
                            if tx.duration != nil {
                                Text("耗时: \(tx.formattedDuration)").font(.caption2).foregroundStyle(theme.textSecondary)
                            }
                        }.padding(4)
                    }

                    // Request headers
                    if !tx.requestHeaders.isEmpty {
                        GroupBox("请求头") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(tx.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                                    HStack(alignment: .top) {
                                        Text(key).font(.caption2.bold().monospaced())
                                            .frame(width: 100, alignment: .trailing)
                                            .foregroundStyle(theme.methodGET)
                                        Text(val).font(.caption2.monospaced())
                                            .textSelection(.enabled)
                                    }
                                }
                            }.padding(4)
                        }
                    }

                    // Request body
                    if let body = tx.requestBody, !body.isEmpty {
                        GroupBox("请求体") {
                            Text(body).font(.caption.monospaced())
                                .textSelection(.enabled).padding(4)
                        }
                    }

                    // Response
                    if let respHeaders = tx.responseHeaders {
                        GroupBox("响应头") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(respHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                                    HStack(alignment: .top) {
                                        Text(key).font(.caption2.bold().monospaced())
                                            .frame(width: 100, alignment: .trailing)
                                            .foregroundStyle(theme.methodPOST)
                                        Text(val).font(.caption2.monospaced())
                                            .textSelection(.enabled)
                                    }
                                }
                            }.padding(4)
                        }
                    }

                    if let respBody = tx.responseBody {
                        GroupBox("响应体") {
                            Text(respBody).font(.caption.monospaced())
                                .textSelection(.enabled).padding(4)
                        }
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tx.curlCommand, forType: .string)
                        } label: {
                            Label("复制 cURL", systemImage: "doc.on.doc")
                        }.buttonStyle(.bordered).font(.caption)

                        Button {
                            Task {
                                replayResult = await inspector.replay(tx)
                                showReplay = true
                            }
                        } label: {
                            Label("重放", systemImage: "arrow.clockwise")
                        }.buttonStyle(.bordered).font(.caption)

                        Button { diffLeft = tx; showDiffPicker = true } label: {
                            Label("Diff", systemImage: "arrow.left.arrow.right")
                        }.buttonStyle(.bordered).font(.caption)
                    }
                }.padding(12)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "network").font(.system(size: 48)).foregroundStyle(theme.textTertiary)
                Text("选择一个请求查看详情").font(.caption).foregroundStyle(theme.textSecondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sheets

    private var curlImportSheet: some View {
        VStack(spacing: 12) {
            Text("导入 cURL 命令").font(.headline)
            TextEditor(text: $curlImportText)
                .font(.caption.monospaced())
                .frame(height: 120)
                .border(theme.textSecondary.opacity(0.3))
            HStack {
                Button("取消") { showCurlImport = false }
                Spacer()
                Button("导入") {
                    if let tx = inspector.importFromCurl(curlImportText) {
                        inspector.transactions.append(tx)
                    }
                    curlImportText = ""
                    showCurlImport = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 420)
    }

    private var mockEditorSheet: some View {
        VStack(spacing: 12) {
            Text("Mock 响应规则").font(.headline)
            Toggle("启用 Mock", isOn: $inspector.mockEnabled)
            ForEach(inspector.mockRules) { rule in
                HStack {
                    Text(rule.urlPattern).font(.caption.monospaced())
                    Spacer()
                    Text("\(rule.statusCode)").font(.caption)
                }
            }
            HStack {
                Button("取消") { showMockEditor = false }
                Spacer()
                Button("添加规则") {
                    inspector.addMockRule(pattern: "/api/example", statusCode: 200, body: "{\"mock\": true}")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 400)
    }

    private var replaySheet: some View {
        VStack(spacing: 12) {
            Text("重放结果").font(.headline)
            if let result = replayResult {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(result.method) \(result.path)").font(.caption.monospaced())
                            Spacer()
                            if let code = result.statusCode {
                                Text("\(code)").font(.caption.bold())
                                    .foregroundStyle(statusColor(code))
                            }
                        }
                        if let dur = result.duration {
                            Text("耗时: \(String(format: "%.0fms", dur * 1000))").font(.caption2)
                        }
                        if let body = result.responseBody {
                            Text(body.prefix(500)).font(.caption2.monospaced())
                                .lineLimit(10)
                        }
                    }.padding(4)
                }
            } else {
                ProgressView("请求中...")
            }
            Button("关闭") { showReplay = false }
        }
        .padding(20).frame(width: 500)
    }

    private var diffSheet: some View {
        VStack(spacing: 12) {
            Text("请求 Diff 对比").font(.headline)
            if let left = diffLeft, let right = diffRight {
                let diffLines = inspector.diff(left, right)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("A: \(left.method) \(left.path)").font(.caption.bold())
                        Text("B: \(right.method) \(right.path)").font(.caption.bold())
                        Divider()
                        ForEach(diffLines) { line in
                            Text(line.content)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(diffBg(line.type))
                        }
                    }.padding(4)
                }
            } else if diffLeft != nil {
                Text("请在请求列表中右键选择第二个请求作为 Diff 右侧")
                    .font(.caption).foregroundStyle(theme.textSecondary)
            } else {
                Text("请先选择一个请求作为 Diff 左侧（右键菜单）")
                    .font(.caption).foregroundStyle(theme.textSecondary)
            }
            Button("关闭") { showDiffPicker = false }
        }
        .padding(20).frame(width: 600, height: 400)
    }

    // MARK: - Helpers

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return theme.methodGET
        case "POST": return theme.methodPOST
        case "PUT": return theme.methodPUT
        case "DELETE": return theme.methodDELETE
        case "PATCH": return theme.methodPATCH
        default: return theme.textTertiary
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return theme.statusSuccess
        case 300..<400: return theme.statusRedirect
        case 400..<500: return theme.statusClientError
        case 500..<600: return theme.statusServerError
        default: return theme.textTertiary
        }
    }

    private func diffBg(_ type: HTTPInspector.DiffLine.DiffType) -> Color {
        switch type {
        case .added: return theme.success.opacity(0.1)
        case .removed: return theme.error.opacity(0.1)
        case .context: return .clear
        }
    }
}

// MARK: - Transaction Row

struct HTTPTransactionRow: View {
    let tx: HTTPTransaction
    @EnvironmentObject var themeManager: ThemeManager
    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        let theme = themeManager.currentTheme
        HStack(spacing: 6) {
            // Type icon
            let rtype = tx.resourceType
            Image(systemName: rtype.icon)
                .font(.caption2)
                .foregroundStyle(typeColor(rtype))
                .frame(width: 14)

            Text(tx.method)
                .font(.caption2.bold().monospaced())
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(methodBg.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(tx.host).font(.caption).lineLimit(1)
                HStack(spacing: 4) {
                    Text(tx.path).font(.caption2.monospaced())
                        .foregroundStyle(theme.textSecondary).lineLimit(1)
                    Text(rtype.rawValue)
                        .font(.system(size: 8))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(typeColor(rtype).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .foregroundStyle(typeColor(rtype))
                }
            }

            Spacer()

            if let code = tx.statusCode {
                Text("\(code)")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(statusColor)
            } else {
                Text("...").font(.caption2).foregroundStyle(theme.textTertiary)
            }

            Text(tx.formattedDuration)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var methodBg: Color {
        switch tx.method {
        case "GET": return theme.methodGET
        case "POST": return theme.methodPOST
        case "PUT": return theme.methodPUT
        case "DELETE": return theme.methodDELETE
        default: return theme.textTertiary
        }
    }

    private var statusColor: Color {
        guard let code = tx.statusCode else { return theme.textTertiary }
        switch code {
        case 200..<300: return theme.statusSuccess
        case 300..<400: return theme.statusRedirect
        case 400..<600: return theme.statusClientError
        default: return theme.textTertiary
        }
    }

    private func typeColor(_ type: ResourceType) -> Color {
        switch type {
        case .document: return theme.typeDocument
        case .xhr: return theme.typeXHR
        case .css: return theme.typeCSS
        case .js: return theme.typeJS
        case .image: return theme.typeImage
        case .font: return theme.typeFont
        case .media: return theme.typeMedia
        case .websocket: return theme.typeWebSocket
        case .json: return theme.typeJSON
        case .xml: return theme.typeXML
        case .manifest, .text, .other: return theme.textTertiary
        }
    }
}
