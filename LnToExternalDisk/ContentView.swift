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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = BatchListViewModel()
    @State private var showRuleEditor = false
    @State private var isBatchDropTargeted = false

    private var theme: Theme {
        Theme(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    listSection
                    logSection
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: LayoutMetrics.windowMinWidth, minHeight: LayoutMetrics.windowMinHeight)
        .background(theme.windowBackground)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isBatchDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if viewModel.isRunning {
                ZStack {
                    theme.overlayScrim
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
                            .strokeBorder(theme.overlayBorder, lineWidth: 1)
                    }
                    .shadow(color: theme.overlayShadowColor, radius: 24, y: 8)
                }
            }
        }
        .sheet(isPresented: $showRuleEditor) {
            ruleEditorSheet
        }
    }

    private var headerSection: some View {
        panelCard(title: "卷与路径", subtitle: "指定外置卷根目录，再导入或拖拽待处理文件夹") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    volumePathLabel
                    volumePathField
                }
                ViewThatFits(in: .horizontal) {
                    headerActionWideLayout
                    headerActionCompactLayout
                }
            }
        }
    }

    private var listSection: some View {
        panelCard(title: "批量任务", subtitle: "编辑路径、冲突策略后可逐条或整批执行") {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    listToolbarWideLayout
                    listToolbarCompactLayout
                }
                batchDropArea
                if viewModel.items.isEmpty {
                    emptyBatchState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            batchCard(index: index, item: item)
                        }
                    }
                }
            }
        }
    }

    private var batchDropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.dropZoneFill(isTargeted: isBatchDropTargeted).top,
                            theme.dropZoneFill(isTargeted: isBatchDropTargeted).bottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    theme.dropZoneBorder(isTargeted: isBatchDropTargeted),
                    style: StrokeStyle(lineWidth: isBatchDropTargeted ? 2 : 1.5, dash: [9, 6])
                )
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isBatchDropTargeted ? theme.accentStrong : .secondary)
                Text(isBatchDropTargeted ? "松手即可追加目录到批量任务" : "拖拽目录到这里可批量追加，也可使用上方“导入文件夹”")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isBatchDropTargeted ? theme.accentStrong : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func batchCard(index: Int, item: BatchLinkItem) -> some View {
        let liveItem = itemSnapshot(for: item.id) ?? item

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 8) {
                    Text("任务 \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                    statusBadge(liveItem.status)
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Button {
                        viewModel.toggleSelection(id: liveItem.id)
                    } label: {
                        Image(systemName: viewModel.selectedIDs.contains(liveItem.id) ? "checkmark.circle.fill" : "circle")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.selectedIDs.contains(liveItem.id) ? Color.accentColor : .secondary)

                    Button {
                        viewModel.runSingle(id: liveItem.id)
                    } label: {
                        Label("执行", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isRunning)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    compactFieldGroup(title: "源路径") {
                        TextField("原始路径", text: itemTextBinding(for: liveItem.id, keyPath: \.sourcePath))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                    }
                    compactFieldGroup(title: "目标路径") {
                        TextField("目标路径", text: itemTextBinding(for: liveItem.id, keyPath: \.targetPath))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    compactFieldGroup(title: "源路径") {
                        TextField("原始路径", text: itemTextBinding(for: liveItem.id, keyPath: \.sourcePath))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                    }
                    compactFieldGroup(title: "目标路径") {
                        TextField("目标路径", text: itemTextBinding(for: liveItem.id, keyPath: \.targetPath))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    conflictPolicyPicker(for: liveItem.id, fallback: liveItem.conflictPolicy, isEnabled: liveItem.targetExists)
                    statusChip(
                        title: liveItem.targetExists ? "目标已存在" : "目标不存在",
                        color: liveItem.targetExists ? .orange : .secondary
                    )
                    statusChip(
                        title: liveItem.requiresPrivileged ? "需提权" : "普通权限",
                        color: liveItem.requiresPrivileged ? .red : .secondary
                    )
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    conflictPolicyPicker(for: liveItem.id, fallback: liveItem.conflictPolicy, isEnabled: liveItem.targetExists)
                    HStack(spacing: 8) {
                        statusChip(
                            title: liveItem.targetExists ? "目标已存在" : "目标不存在",
                            color: liveItem.targetExists ? .orange : .secondary
                        )
                        statusChip(
                            title: liveItem.requiresPrivileged ? "需提权" : "普通权限",
                            color: liveItem.requiresPrivileged ? .red : .secondary
                        )
                    }
                }
            }

            if !liveItem.message.isEmpty {
                Text(liveItem.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.secondaryCardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.secondaryCardBorder, lineWidth: 1)
        }
        .shadow(color: theme.secondaryCardShadowColor, radius: 7, y: 2)
        .overlay {
            if viewModel.selectedIDs.contains(liveItem.id) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(theme.selectionOutline, lineWidth: 1.2)
            }
        }
    }

    private var ruleEditorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                ruleEditorHeaderWideLayout
                ruleEditorHeaderCompactLayout
            }
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.rules) { rule in
                        if let ruleBinding = ruleBinding(for: rule.id) {
                            ViewThatFits(in: .horizontal) {
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
                                VStack(alignment: .leading, spacing: 12) {
                                    TextField("源前缀", text: ruleBinding.sourcePrefix)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("替换前缀", text: ruleBinding.replacementPrefix)
                                        .textFieldStyle(.roundedBorder)
                                    HStack {
                                        Spacer(minLength: 0)
                                        Button(role: .destructive) {
                                            viewModel.removeRule(id: rule.id)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.secondaryCardBackground)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(theme.secondaryCardBorder, lineWidth: 1)
                            }
                            .shadow(color: theme.secondaryCardShadowColor.opacity(0.85), radius: 5, y: 1)
                        }
                    }
                }
            }
            .frame(minHeight: 220, idealHeight: 280)
        }
        .padding(22)
        .frame(minWidth: LayoutMetrics.ruleEditorMinWidth, minHeight: LayoutMetrics.ruleEditorMinHeight)
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
                    .background(theme.warningBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.warningBorder, lineWidth: 1)
                    }
                    .shadow(color: theme.warningShadowColor, radius: 8, y: 2)
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
                .frame(minHeight: 120, idealHeight: 180)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.logBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.logBorder, lineWidth: 1)
                }
                .shadow(color: theme.logShadowColor, radius: 8, y: 2)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.logHighlight)
                        .frame(height: 1)
                        .padding(.horizontal, 1)
                        .blendMode(.screen)
                        .opacity(colorScheme == .dark ? 1 : 0)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                let resolvedURL: URL?

                switch data {
                case let url as URL:
                    resolvedURL = url
                case let nsURL as NSURL:
                    resolvedURL = nsURL as URL
                case let data as Data:
                    resolvedURL = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
                case let string as String:
                    resolvedURL = URL(string: string)
                case let nsString as NSString:
                    resolvedURL = URL(string: nsString as String)
                default:
                    resolvedURL = nil
                }

                guard let url = resolvedURL else { return }
                let standardizedURL = url.standardizedFileURL
                guard standardizedURL.hasDirectoryPath else { return }

                Task { @MainActor in
                    viewModel.addDroppedFolders(urls: [standardizedURL])
                }
            }
        }
        return accepted
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.panelGradient.top,
                            theme.panelGradient.bottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.panelBorder, lineWidth: 1)
        }
        .shadow(color: theme.panelShadowColor, radius: 12, y: 6)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.panelHighlight)
                .frame(height: 1)
                .padding(.horizontal, 1)
                .blendMode(.screen)
                .opacity(colorScheme == .dark ? 1 : 0)
        }
    }

    private func statusBadge(_ status: BatchItemStatus) -> some View {
        let color = statusColor(status)
        let background = theme.badgeBackground(for: color)
        return Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
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

    private var volumePathLabel: some View {
        Text("卷路径")
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 56, alignment: .leading)
    }

    private var volumePathField: some View {
        TextField("/Volumes/YourDisk", text: $viewModel.volumeRoot)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .onSubmit { viewModel.saveRules() }
    }

    private var chooseVolumeButton: some View {
        Button {
            viewModel.chooseVolumeRoot()
        } label: {
            Label("选择卷", systemImage: "externaldrive")
        }
        .help("选择外置磁盘卷")
    }

    private var ruleEditorButton: some View {
        Button {
            showRuleEditor = true
        } label: {
            Label("路径映射规则", systemImage: "arrow.triangle.swap")
        }
    }

    private var importFoldersButton: some View {
        Button {
            viewModel.pickFolders()
        } label: {
            Label("导入文件夹", systemImage: "folder.badge.plus")
        }
    }

    private var stopOnFailureToggle: some View {
        Toggle(isOn: $viewModel.stopOnFailure) {
            Label("失败即停", systemImage: "exclamationmark.octagon")
        }
        .toggleStyle(.checkbox)
    }

    private var runBatchButton: some View {
        Button {
            viewModel.runBatch()
        } label: {
            Label(viewModel.isRunning ? "执行中…" : "开始批量执行", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.items.isEmpty || viewModel.isRunning)
    }

    private var headerActionWideLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            chooseVolumeButton
            ruleEditorButton
            importFoldersButton
            stopOnFailureToggle
            Spacer(minLength: 12)
            runBatchButton
        }
    }

    private var headerActionCompactLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                chooseVolumeButton
                ruleEditorButton
                importFoldersButton
            }
            HStack(alignment: .center, spacing: 14) {
                stopOnFailureToggle
                Spacer(minLength: 12)
                runBatchButton
            }
        }
    }

    private var sudoToggle: some View {
        Toggle("sudo", isOn: Binding(
            get: { viewModel.sudoEnabled },
            set: { viewModel.setSudoEnabled($0) }
        ))
        .toggleStyle(.switch)
        .frame(width: 110)
    }

    private var removeSelectedButton: some View {
        Button {
            viewModel.removeSelectedItems()
        } label: {
            Label("移除选中", systemImage: "minus.circle")
        }
    }

    private var clearItemsButton: some View {
        Button(role: .destructive) {
            viewModel.clearItems()
        } label: {
            Label("清空列表", systemImage: "trash")
        }
    }

    private var listToolbarWideLayout: some View {
        HStack(spacing: 16) {
            sudoToggle
            Spacer(minLength: 12)
            removeSelectedButton
            clearItemsButton
        }
    }

    private var listToolbarCompactLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            sudoToggle
            HStack(spacing: 12) {
                removeSelectedButton
                clearItemsButton
            }
        }
    }

    private var emptyBatchState: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
            Text("还没有批量任务")
                .font(.headline)
            Text("拖拽目录到上方区域，或使用“导入文件夹”来创建任务卡片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var ruleEditorTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("路径映射规则")
                .font(.title2.weight(.semibold))
            Text("将源路径前缀替换为目标前缀，保存后主界面生效")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var addRuleButton: some View {
        Button {
            viewModel.appendRule()
        } label: {
            Label("新增规则", systemImage: "plus.circle.fill")
        }
    }

    private var saveRulesButton: some View {
        Button {
            viewModel.saveRules()
            showRuleEditor = false
        } label: {
            Label("保存并关闭", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
    }

    private var ruleEditorHeaderWideLayout: some View {
        HStack {
            ruleEditorTitleBlock
            Spacer(minLength: 12)
            addRuleButton
            saveRulesButton
        }
    }

    private var ruleEditorHeaderCompactLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            ruleEditorTitleBlock
            HStack(spacing: 12) {
                addRuleButton
                saveRulesButton
            }
        }
    }

    private func batchCardSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func compactFieldGroup<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func fieldGroup<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func conflictPolicyPicker(for id: UUID, fallback: ConflictPolicy, isEnabled: Bool) -> some View {
        Picker("冲突策略", selection: Binding(
            get: { itemSnapshot(for: id)?.conflictPolicy ?? fallback },
            set: { newValue in
                guard let index = itemIndex(for: id) else { return }
                viewModel.items[index].conflictPolicy = newValue
            }
        )) {
            ForEach(ConflictPolicy.allCases) { policy in
                Text(policy.title).tag(policy)
            }
        }
        .pickerStyle(.menu)
        .disabled(!isEnabled)
    }

    private func statusChip(title: String, color: Color) -> some View {
        let background = theme.chipBackground(for: color)
        return Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: Capsule())
            .foregroundStyle(color)
    }

    private struct Theme {
        let colorScheme: ColorScheme

        var windowBackground: Color {
            colorScheme == .dark
                ? Color(red: 0.10, green: 0.10, blue: 0.11)
                : Color(nsColor: .windowBackgroundColor)
        }

        var accentStrong: Color {
            colorScheme == .dark ? Color.accentColor.opacity(0.92) : Color.accentColor
        }

        var panelGradient: (top: Color, bottom: Color) {
            if colorScheme == .dark {
                return (
                    Color(red: 0.16, green: 0.16, blue: 0.17),
                    Color(red: 0.13, green: 0.13, blue: 0.14)
                )
            }
            return (
                Color(nsColor: .controlBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.96)
            )
        }

        var panelBorder: Color {
            colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color(nsColor: .separatorColor).opacity(0.32)
        }

        var panelShadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.36) : Color.black.opacity(0.03)
        }

        var panelHighlight: Color {
            colorScheme == .dark ? Color.white.opacity(0.015) : Color.clear
        }

        var secondaryCardBackground: Color {
            colorScheme == .dark
                ? Color(red: 0.18, green: 0.18, blue: 0.19)
                : Color(nsColor: .controlBackgroundColor)
        }

        var secondaryCardBorder: Color {
            colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color(nsColor: .separatorColor).opacity(0.42)
        }

        var secondaryCardShadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.012)
        }

        var overlayScrim: Color {
            colorScheme == .dark ? Color.black.opacity(0.34) : Color.black.opacity(0.18)
        }

        var overlayBorder: Color {
            colorScheme == .dark ? Color.white.opacity(0.12) : Color.primary.opacity(0.08)
        }

        var overlayShadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.12)
        }

        func dropZoneFill(isTargeted: Bool) -> (top: Color, bottom: Color) {
            if colorScheme == .dark {
                return isTargeted
                    ? (Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.16))
                    : (Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.08))
            }
            return isTargeted
                ? (Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.08))
                : (Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.04))
        }

        func dropZoneBorder(isTargeted: Bool) -> Color {
            if colorScheme == .dark {
                return Color.accentColor.opacity(isTargeted ? 0.9 : 0.55)
            }
            return Color.accentColor.opacity(isTargeted ? 0.7 : 0.35)
        }

        var selectionOutline: Color {
            colorScheme == .dark ? Color.accentColor.opacity(0.6) : Color.accentColor.opacity(0.28)
        }

        var warningBackground: Color {
            colorScheme == .dark ? Color.orange.opacity(0.18) : Color.orange.opacity(0.12)
        }

        var warningBorder: Color {
            colorScheme == .dark ? Color.orange.opacity(0.45) : Color.orange.opacity(0.35)
        }

        var warningShadowColor: Color {
            colorScheme == .dark ? Color.orange.opacity(0.12) : Color.clear
        }

        var logBackground: Color {
            colorScheme == .dark
                ? Color(red: 0.13, green: 0.13, blue: 0.14)
                : Color(nsColor: .textBackgroundColor).opacity(0.92)
        }

        var logBorder: Color {
            colorScheme == .dark ? Color.white.opacity(0.07) : Color(nsColor: .separatorColor).opacity(0.45)
        }

        var logShadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.24) : Color.clear
        }

        var logHighlight: Color {
            colorScheme == .dark ? Color.white.opacity(0.015) : Color.clear
        }

        func badgeBackground(for color: Color) -> Color {
            colorScheme == .dark ? color.opacity(0.24) : color.opacity(0.16)
        }

        func chipBackground(for color: Color) -> Color {
            colorScheme == .dark ? color.opacity(0.2) : color.opacity(0.12)
        }

        private func tinted(_ base: NSColor, white: Double, black: Double) -> Color {
            let adjusted = base.blended(withFraction: CGFloat(white), of: .white)?.blended(withFraction: CGFloat(black), of: .black) ?? base
            return Color(nsColor: adjusted)
        }
    }

    private func itemIndex(for id: UUID) -> Int? {
        viewModel.items.firstIndex { $0.id == id }
    }

    private func itemSnapshot(for id: UUID) -> BatchLinkItem? {
        guard let index = itemIndex(for: id) else { return nil }
        return viewModel.items[index]
    }

    private func itemTextBinding(for id: UUID, keyPath: WritableKeyPath<BatchLinkItem, String>) -> Binding<String> {
        Binding(
            get: { itemSnapshot(for: id)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = itemIndex(for: id) else { return }
                viewModel.items[index][keyPath: keyPath] = newValue
                viewModel.refreshTargetState(for: index)
            }
        )
    }

    private enum LayoutMetrics {
        static let windowMinWidth: CGFloat = 760
        static let windowMinHeight: CGFloat = 560
        static let ruleEditorMinWidth: CGFloat = 560
        static let ruleEditorMinHeight: CGFloat = 360
    }
}
