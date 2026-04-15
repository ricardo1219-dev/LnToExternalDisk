# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview
- This repository is a single-target macOS SwiftUI app named `LnToExternalDisk`, built from `LnToExternalDisk.xcodeproj`.
- The app helps users move a source directory to an external volume and replace the original path with a symlink. The main workflow is: configure a destination volume and path-mapping rules, import or drag folders into a batch list, choose a conflict policy, then run the symlink workflow.
- There are currently no test targets, no Swift Package Manager manifest, no CocoaPods/Cartfile setup, and no README / Cursor / Copilot instruction files in the repo.

## Common commands
- List schemes and targets:
  - `xcodebuild -list -project "LnToExternalDisk.xcodeproj"`
- Build the app from the command line:
  - `xcodebuild -project "LnToExternalDisk.xcodeproj" -scheme "LnToExternalDisk" -configuration Debug -sdk macosx build`
- Open the project in Xcode:
  - `open "LnToExternalDisk.xcodeproj"`
- Run the built app after a successful command-line build:
  - `open "$HOME/Library/Developer/Xcode/DerivedData/LnToExternalDisk-fgebeuvakdnwiccqaugvvkhliznz/Build/Products/Debug/LnToExternalDisk.app"`
- Show key build settings when you need the current DerivedData output path or bundle info:
  - `xcodebuild -project "LnToExternalDisk.xcodeproj" -scheme "LnToExternalDisk" -showBuildSettings`
- There is no test target yet, so `xcodebuild test` and single-test execution are not currently available in this repository.

## Architecture

### App entry and UI composition
- `LnToExternalDisk/LnToExternalDiskApp.swift` is the app entry point. It creates a single `WindowGroup` hosting `ContentView` and a lightweight Settings scene.
- `LnToExternalDisk/ContentView.swift` contains nearly all UI composition. The main screen is split into three functional sections:
  - header section for volume selection and path-rule management
  - batch task section for imported folders, conflict policy selection, sudo toggle, and execution controls
  - log section for runtime output and SIP / permission hints
- `ContentView` owns `@StateObject private var viewModel = BatchListViewModel()`, so almost all user actions route through the view model.

### State and orchestration layer
- `LnToExternalDisk/BatchListViewModel.swift` is the central coordinator for app behavior.
- It owns all mutable UI state: batch items, selected item IDs, logs, volume root, path rules, stop-on-failure flag, sudo state, cached admin password, and SIP hint text.
- It also orchestrates the workflow by composing four services:
  - `PathMappingService` for config persistence and target-path calculation
  - `SymlinkWorkflowService` for the actual filesystem migration + symlink creation logic
  - `SIPHintService` for translating permission failures into user-facing guidance
  - `PrivilegeCoordinator` for plain shell execution vs sudo execution
- Batch execution and single-item execution both eventually flow through `runItem(at:)`, which first tries non-privileged execution and then falls back to sudo when permission-denied errors are detected.

### Data model and batch semantics
- `LnToExternalDisk/BatchLinkModels.swift` defines the app’s core data model:
  - `PathMappingRule` describes source-prefix to replacement-prefix mapping
  - `PathMappingConfig` (declared in `PathMappingService.swift`) stores the selected volume root plus rule list
  - `BatchLinkItem` represents one folder migration job, including source path, target path, conflict strategy, privilege requirement flag, execution status, and last message
  - `ConflictPolicy` drives how existing target content is handled: overwrite, merge with overwrite, or merge and stop on collisions
- UI rendering in `ContentView` is a direct projection of `BatchLinkItem` state, so changes to workflow status or conflict behavior usually require coordinated edits across the model, view model, and card UI.

### Path mapping and persisted configuration
- `LnToExternalDisk/PathMappingService.swift` is responsible for turning a source path into a suggested target path on the external disk.
- The service stores configuration in `UserDefaults` under `pathMappingConfig.v1`.
- The mapping algorithm sorts rules by longest `sourcePrefix` first, applies the first matching prefix replacement, then joins the mapped path onto the configured volume root.
- It also computes whether an operation likely needs elevated privileges based on protected source/target prefixes such as `/Library`, `/Users/Shared`, `/private`, and `/System`.
- Default config is generated dynamically from the current user name and the first removable or non-internal mounted volume.

### Filesystem workflow and privilege model
- `LnToExternalDisk/SymlinkWorkflowService.swift` contains the critical symlink workflow.
- For each item it:
  1. validates that the source exists and is not already a symlink
  2. creates a timestamped backup path next to the source
  3. builds a shell script that moves the source to the backup path, prepares the target directory, creates a symlink at the original source location, migrates data into the target according to the selected conflict policy, and rolls back on failure before commit
  4. executes that script through `PrivilegeCoordinator`
- Conflict behavior is implemented inside the generated shell script:
  - `overwrite` removes an existing target and moves the backup directly into place
  - `mergeOverwrite` uses `rsync -a` and then removes the backup
  - `mergeStopOnConflict` runs an embedded Python conflict scan first, aborts on duplicate file paths, then performs `rsync -a`
- `LnToExternalDisk/PrivilegeCoordinator.swift` is the shell boundary. It either runs the script directly with `/bin/zsh -lc` or wraps it in `sudo -S`, optionally impersonating the owning user with `sudo -u <user>`. It also validates sudo passwords before caching them in memory.
- Because this app executes shell commands that can move and delete directory trees, changes in `SymlinkWorkflowService` and `PrivilegeCoordinator` have the highest blast radius in the codebase.

### Permission guidance and platform settings
- `LnToExternalDisk/SIPHintService.swift` inspects execution errors and turns permission failures into actionable hints.
- It distinguishes between user-directory permission issues and likely SIP-protected system-path issues by checking whether failing paths are under `/Users` versus `/System` / `/Library`.
- The target has App Sandbox disabled in both the project settings and `LnToExternalDisk/LnToExternalDisk.entitlements`, which is necessary for the current filesystem-and-shell based workflow.
- Project build settings show a macOS app target with scheme `LnToExternalDisk`, bundle identifier `com.znyh.app.tool.LnToExternalDisk`, and deployment target `15.6`.

## What to read first for common tasks
- For UI or interaction changes, start with `LnToExternalDisk/ContentView.swift`, then trace the corresponding action into `BatchListViewModel.swift`.
- For behavior changes in batch execution, conflict handling, sudo fallback, or rollback semantics, read `BatchListViewModel.swift` together with `SymlinkWorkflowService.swift` and `PrivilegeCoordinator.swift`.
- For changes to how target paths are suggested or saved, read `PathMappingService.swift` and the rule-editor parts of `ContentView.swift`.
- For permission-related UX, inspect `SIPHintService.swift`, the `sipHintMessage` flow in `BatchListViewModel.swift`, and the log section in `ContentView.swift`.
