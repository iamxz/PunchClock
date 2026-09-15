import SwiftUI

struct PunchToolView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                if model.record.skipped {
                    Button("恢复打卡提醒") { model.setSkipped(false) }
                } else {
                    Button("标记今天不打卡（休假）") { model.setSkipped(true) }
                }
                Spacer()
            }
            .padding(.top, 8)

            StatisticsView(model: model)
        }
    }
}
