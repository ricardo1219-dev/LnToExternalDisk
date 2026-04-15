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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("软链接助手")
                    .font(.title2.weight(.semibold))
                Text("在主界面配置映射规则与目标卷路径后，拖拽目录即可批量处理。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 440, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
