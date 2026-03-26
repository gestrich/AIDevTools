import SwiftUI

struct OutputPanel: View {
    let title: String?
    let text: String
    var autoScroll: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                        .id("output-end")
                }
                .frame(minHeight: 200, maxHeight: 400)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: text) {
                    if autoScroll {
                        proxy.scrollTo("output-end", anchor: .bottom)
                    }
                }
            }
        }
    }
}
