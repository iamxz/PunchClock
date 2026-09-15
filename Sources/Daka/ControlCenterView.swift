import SwiftUI
import DakaCore

struct ControlCenterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: toolSelection) {
                ForEach(model.tools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tool.title, systemImage: tool.symbol)
                        Text(summary(for: tool.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(tool.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            detail(for: model.selectedTool)
        }
        .frame(minWidth: 720, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PetToolbarToggle(model: model)
            }
        }
    }

    private func summary(for id: ToolID) -> String {
        switch id {
        case .punch:
            let morning = model.record.morningDone ? "上班已完成" : "上班待打卡"
            let evening = model.isEveningComplete ? "下班已完成" : "下班待打卡"
            return "\(morning) · \(evening)"
        default:
            return "即将推出"
        }
    }

    private var toolSelection: Binding<ToolID?> {
        Binding(get: { model.selectedTool },
                set: { if let value = $0 { model.selectTool(value) } })
    }

    @ViewBuilder
    private func detail(for id: ToolID) -> some View {
        switch id {
        case .punch:
            PunchToolView(model: model)
        default:
            ComingSoonView(metadata: ToolCatalog.metadata(for: id))
        }
    }
}

private struct PetToolbarToggle: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.setPetVisible(!model.petVisible)
        } label: {
            Image(systemName: model.petVisible ? "pawprint.fill" : "pawprint")
        }
        .help(model.petVisible ? "隐藏桌宠" : "显示桌宠")
        .accessibilityLabel(model.petVisible ? "隐藏桌宠" : "显示桌宠")
    }
}
