//
//  ContentView.swift
//  LnToExternalDisk
//
//  Created by Ricardo on 13/4/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = BatchListViewModel()
    @State private var showRuleEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            dropSection
            listSection
            logSection
        }
        .padding(22)
        .frame(minWidth: 1080, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if viewModel.isRunning {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .scaleEffect(1.05)
                        Text("正在执行软链接任务，请稍候…")
                            .font(.title3.weight(.semibold))
                        Text("窗口保持可响应，可查看列表状态与日志。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(minWidth: 320)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                }
            }
        }
        .sheet(isPresented: $showRuleEditor) {
            ruleEditorSheet
        }
    }

    private var headerSection: some View {
        panelCard(title: "卷与路径", subtitle: "指定外置卷根目录，再导入或拖拽待处理文件夹") {
            HStack(alignment: .center, spacing: 14) {
                Text("卷路径")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("/Volumes/YourDisk", text: $viewModel.volumeRoot)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit { viewModel.saveRules() }
                Button {
                    viewModel.chooseVolumeRoot()
                } label: {
                    Label("选择卷", systemImage: "externaldrive")
                }
                .help("选择外置磁盘卷")
                Button {
                    showRuleEditor = true
                } label: {
                    Label("路径映射规则", systemImage: "arrow.triangle.swap")
                }
                Button {
                    viewModel.pickFolders()
                } label: {
                    Label("导入文件夹", systemImage: "folder.badge.plus")
                }
                Toggle(isOn: $viewModel.stopOnFailure) {
                    Label("失败即停", systemImage: "exclamationmark.octagon")
                }
                .toggleStyle(.checkbox)
                Spacer(minLength: 12)
                Button {
                    viewModel.runBatch()
                } label: {
                    Label(viewModel.isRunning ? "执行中…" : "开始批量执行", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.items.isEmpty || viewModel.isRunning)
            }
        }
    }

    private var dropSection: some View {
        panelCard(title: "添加任务", subtitle: "将 Finder 中的目录拖入下方区域") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [9, 6]))
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text("拖拽目录到这里可批量追加")
                        .font(.body.weight(.semibold))
                    Text("也可使用上方「导入文件夹」")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
            .frame(height: 100)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                handleDrop(providers)
            }
        }
    }

    private var listSection: some View {
        panelCard(title: "批量任务", subtitle: "编辑路径、冲突策略后可逐条或整批执行") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Toggle("sudo", isOn: Binding(
                        get: { viewModel.sudoEnabled },
                        set: { viewModel.setSudoEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .frame(width: 110)
                    Spacer()
                    Button {
                        viewModel.removeSelectedItems()
                    } label: {
                        Label("移除选中", systemImage: "minus.circle")
                    }
                    Button(role: .destructive) {
                        viewModel.clearItems()
                    } label: {
                        Label("清空列表", systemImage: "trash")
                    }
                }
                batchColumnHeader
                ScrollView(.vertical) {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            batchRow(index: index, item: item)
                        }
                    }
                }
                .frame(minHeight: 300, maxHeight: 360)
            }
        }
    }

    private var batchColumnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 28)
            Text("原始路径")
                .frame(minWidth: 260, alignment: .leading)
            Text("目标路径")
                .frame(minWidth: 300, alignment: .leading)
            Text("冲突策略")
                .frame(width: 160, alignment: .leading)
            Text("目标")
                .frame(width: 100, alignment: .leading)
            Text("权限")
                .frame(width: 70, alignment: .leading)
            Text("状态")
                .frame(width: 88, alignment: .leading)
            Text("信息")
                .frame(minWidth: 80, alignment: .leading)
            Spacer()
                .frame(width: 72)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .separatorColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func batchRow(index: Int, item: BatchLinkItem) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleSelection(id: item.id)
            } label: {
                Image(systemName: viewModel.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .frame(width: 28)

            TextField("原始路径", text: Binding(
                get: { viewModel.items[index].sourcePath },
                set: {
                    viewModel.items[index].sourcePath = $0
                    viewModel.refreshTargetState(for: index)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
            .frame(minWidth: 260)

            TextField("目标路径", text: Binding(
                get: { viewModel.items[index].targetPath },
                set: {
                    viewModel.items[index].targetPath = $0
                    viewModel.refreshTargetState(for: index)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
            .frame(minWidth: 300)

            Picker("", selection: Binding(
                get: { viewModel.items[index].conflictPolicy },
                set: { viewModel.items[index].conflictPolicy = $0 }
            )) {
                ForEach(ConflictPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .labelsHidden()
            .frame(width: 160)
            .disabled(!item.targetExists)

            Text(item.targetExists ? "目标已存在" : "目标不存在")
                .font(.caption.weight(.medium))
                .foregroundStyle(item.targetExists ? .orange : .secondary)
                .frame(width: 100, alignment: .leading)

            Text(item.requiresPrivileged ? "需提权" : "普通")
                .font(.caption.weight(.medium))
                .foregroundStyle(item.requiresPrivileged ? .red : .secondary)
                .frame(width: 70, alignment: .leading)

            statusBadge(item.status)
                .frame(width: 88, alignment: .leading)

            Text(item.message)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)

            Spacer(minLength: 0)
            Button {
                viewModel.runSingle(id: item.id)
            } label: {
                Label("执行", systemImage: "play.circle")
            }
            .labelStyle(.titleOnly)
            .disabled(viewModel.isRunning)
            .frame(width: 72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }

    private var ruleEditorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("路径映射规则")
                        .font(.title2.weight(.semibold))
                    Text("将源路径前缀替换为目标前缀，保存后主界面生效")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.appendRule()
                } label: {
                    Label("新增规则", systemImage: "plus.circle.fill")
                }
                Button {
                    viewModel.saveRules()
                    showRuleEditor = false
                } label: {
                    Label("保存并关闭", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.rules) { rule in
                        if let ruleBinding = ruleBinding(for: rule.id) {
                            HStack(spacing: 12) {
                                TextField("源前缀", text: ruleBinding.sourcePrefix)
                                    .textFieldStyle(.roundedBorder)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                TextField("替换前缀", text: ruleBinding.replacementPrefix)
                                    .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    viewModel.removeRule(id: rule.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 260)
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func ruleBinding(for id: UUID) -> Binding<PathMappingRule>? {
        guard let index = viewModel.rules.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $viewModel.rules[index]
    }

    private var logSection: some View {
        panelCard(title: "执行日志", subtitle: "输出与错误信息") {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.sipHintMessage.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(viewModel.sipHintMessage)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 120)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
                else { return }
                Task { @MainActor in
                    viewModel.addDroppedFolders(urls: [url])
                }
            }
        }
        return true
    }

    private func panelCard<Content: View>(title: LocalizedStringKey, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    private func statusBadge(_ status: BatchItemStatus) -> some View {
        let color = statusColor(status)
        return Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func statusColor(_ status: BatchItemStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }
}
