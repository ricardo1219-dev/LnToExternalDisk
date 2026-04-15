//
//  LnToExternalDiskApp.swift
//  LnToExternalDisk
//
//  Created by Ricardo on 13/4/2026.
//

import AppKit
import SwiftUI

@main
struct LnToExternalDiskApp: App {
    @AppStorage("isDarkModeEnabled") private var isDarkModeEnabled = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var preferredColorScheme: ColorScheme {
        isDarkModeEnabled ? .dark : .light
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 980, height: 720)
        Settings {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("软链接助手")
                            .font(.title2.weight(.semibold))
                        Text("在主界面配置映射规则与目标卷路径后，拖拽目录即可批量处理。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("外观")
                            .font(.headline)
                        Toggle("启动暗黑模式", isOn: $isDarkModeEnabled)
                            .toggleStyle(.switch)
                    }
                }
                .padding(24)
                .frame(minWidth: 300, idealWidth: 420, maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(preferredColorScheme)
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时，退出应用
        return true
    }
}
