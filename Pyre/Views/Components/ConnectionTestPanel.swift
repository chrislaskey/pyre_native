import SwiftUI

// MARK: - ConnectionTestSection

/// Wraps the test button and debug panel. Uses @ObservedObject to directly
/// observe the tester, avoiding the nested-ObservableObject propagation issue.
struct ConnectionTestSection: View {
    @ObservedObject var tester: ConnectionTester
    let hasUrl: Bool
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActionButton(
                title: tester.isTesting ? "Testing..." : "Test Connection",
                icon: "antenna.radiowaves.left.and.right",
                type: .secondary,
                backgroundColor: .orange,
                isLoading: tester.isTesting,
                isDisabled: !hasUrl || tester.isTesting
            ) {
                onTest()
            }

            if !tester.logEntries.isEmpty {
                ConnectionTestPanel(tester: tester)
            }
        }
    }
}

// MARK: - ConnectionTestPanel

struct ConnectionTestPanel: View {
    @ObservedObject var tester: ConnectionTester
    @State private var expandedDetails: Set<UUID> = []
    @State private var copiedToClipboard = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                urlInfoRow
                Divider()
                logEntriesView
                Divider()
                actionRow
            }
            .padding(4)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 8) {
            if tester.isTesting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
            }

            Text("Connection Test")
                .font(.headline)

            Spacer()

            if tester.testComplete {
                Text(tester.testPassed ? "PASSED" : "FAILED")
                    .font(.caption.weight(.bold))
                    .foregroundColor(tester.testPassed ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill((tester.testPassed ? Color.green : Color.red).opacity(0.12))
                    )
            }
        }
    }

    private var statusIcon: String {
        guard tester.testComplete else { return "circle" }
        return tester.testPassed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        guard tester.testComplete else { return .secondary }
        return tester.testPassed ? .green : .red
    }

    // MARK: - URL Info

    @ViewBuilder
    private var urlInfoRow: some View {
        if let wsUrl = tester.resolvedWsUrl {
            VStack(alignment: .leading, spacing: 2) {
                Text("WebSocket URL")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(wsUrl)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Log Entries

    @ViewBuilder
    private var logEntriesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(tester.logEntries) { entry in
                        logEntryRow(entry)
                    }
                }
            }
            .frame(maxHeight: 350)
            .onChange(of: tester.logEntries.count) { _ in
                if let last = tester.logEntries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logEntryRow(_ entry: TestLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%5.3fs", entry.elapsed))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Image(systemName: iconName(for: entry.level))
                    .font(.system(size: 9))
                    .foregroundColor(color(for: entry.level))
                    .frame(width: 12)

                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(entry.level == .debug ? .secondary : .primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if entry.detail != nil {
                    Button {
                        toggleDetail(entry.id)
                    } label: {
                        Image(systemName: expandedDetails.contains(entry.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            .id(entry.id)

            if let detail = entry.detail, expandedDetails.contains(entry.id) {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 68)
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                copyLog()
            } label: {
                Label(copiedToClipboard ? "Copied!" : "Copy Log", systemImage: copiedToClipboard ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if tester.isTesting {
                Button {
                    tester.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button {
                    tester.reset()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private func iconName(for level: TestLogLevel) -> String {
        switch level {
        case .info:    return "arrow.right.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        case .debug:   return "ant.circle"
        }
    }

    private func color(for level: TestLogLevel) -> Color {
        switch level {
        case .info:    return .blue
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        case .debug:   return .secondary
        }
    }

    private func toggleDetail(_ id: UUID) {
        if expandedDetails.contains(id) {
            expandedDetails.remove(id)
        } else {
            expandedDetails.insert(id)
        }
    }

    private func copyLog() {
        let text = tester.logText
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif

        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
}
