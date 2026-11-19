import AppKit
import SwiftUI

/// Sekcja Settings „Agent access (MCP)" (TASK-31): zgoda na odczyt spotkań przez agentów.
/// Wzorzec jak reszta ustawień globalnych: przełącznik zmienia szkic, zapis idzie przyciskiem Save.
struct AgentAccessSettingsView: View {
    @Binding var agentAccess: Bool

    private var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/yascribe-cli").path
    }

    private var command: String {
        "claude mcp add --scope user yascribe -- \"\(cliPath)\" mcp"
    }

    var body: some View {
        SectionHeader("Agent access (MCP)")
        Card {
            FormRow(label: "Agent access",
                    caption: "Agents such as Claude Code or Codex can list meetings and read transcripts and notes through "
                        + "Yascribe's MCP server. What they read is sent to that agent's model provider under its terms. "
                        + "Read-only.") {
                Toggle("Allow AI agents to read meetings", isOn: $agentAccess)
                    .labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            FormRow(label: "Claude Code", caption: "Run this once in Terminal. The server only answers while Agent access is on.") {
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.mnText)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .buttonStyle(.pillSmall)
                    .help("Copy the command")
                }
            }
            RowDivider()
            FormRow(label: "Other agents") {
                Link("Setup for other agents",
                     destination: URL(string: "https://github.com/sharezz1/yascribe/blob/main/docs/readme/mcp.md")!)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}
