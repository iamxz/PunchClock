import SwiftUI
import DakaCore

struct ControlCenterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: toolSelection) {
                ForEach(model.tools) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .tag(tool.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail(for: model.selectedTool)
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
