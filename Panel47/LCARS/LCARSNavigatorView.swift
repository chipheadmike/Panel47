import SwiftUI

/// Browses a directory one level at a time — folders and files, sizes and
/// modified dates, OPEN drills into a folder or launches a file with its
/// default application. No rename, move or delete: this is a viewer, not a
/// file manager, so there's nothing here that can lose work.
struct LCARSNavigatorView: View {
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("NAVIGATOR")
                    .font(LCARSFont.antonio(44, weight: 700))
                    .foregroundStyle(LCARSColor.textOnBlack)

                controls

                if let notice = model.notice {
                    Text(notice.uppercased())
                        .font(LCARSFont.antonio(18, weight: 400))
                        .tracking(0.5)
                        .foregroundStyle(LCARSColor.alertRed)
                } else {
                    caption("\(model.entries.count) ITEM\(model.entries.count == 1 ? "" : "S")")
                }

                rows
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .background(LCARSColor.background)
        .onAppear { model.start() }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if model.canGoUp {
                pill("UP", LCARSColor.periwinkle) { model.goUp() }
            }
            Text(model.displayPath)
                .font(LCARSFont.antonio(22, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 12)
            pill("REVEAL IN FINDER", LCARSColor.iceBlue) { model.revealCurrentDirectoryInFinder() }
            pill(model.isLoading ? "LOADING" : "REFRESH", model.isLoading ? LCARSColor.peach : LCARSColor.paleCanary) {
                if !model.isLoading { model.refresh() }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if model.entries.isEmpty, !model.isLoading, model.notice == nil {
            Text("NOTHING HERE")
                .font(LCARSFont.antonio(18, weight: 400))
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
        }

        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.entries) { entry in
                EntryRowView(entry: entry, onOpen: { model.open(entry) })
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(LCARSFont.antonio(12, weight: 700))
            .tracking(1.5)
            .foregroundStyle(LCARSColor.textOnBlack.opacity(0.7))
    }

    private func pill(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LCARSFont.antonio(16, weight: 700))
                .tracking(1)
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(LCARSColor.gloss(color)))
    }
}

private struct EntryRowView: View {
    let entry: FileBrowserEntry
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(LCARSColor.gloss(entry.isDirectory ? LCARSColor.periwinkle : LCARSColor.orange))
                .frame(width: 90, height: 36)
                .overlay {
                    Text(entry.isDirectory ? "DIR" : "FILE")
                        .font(LCARSFont.antonio(14, weight: 700))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                }

            Text(entry.name)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(LCARSColor.textOnBlack)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(FileBrowserFormat.size(entry))
                .font(LCARSFont.antonio(16, weight: 700))
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.8))
                .frame(width: 100, alignment: .trailing)

            Text(FileBrowserFormat.modified(entry.modifiedDate))
                .font(LCARSFont.antonio(14, weight: 700))
                .tracking(0.5)
                .foregroundStyle(LCARSColor.textOnBlack.opacity(0.6))
                .frame(width: 170, alignment: .trailing)

            Button(action: onOpen) {
                Text("OPEN")
                    .font(LCARSFont.antonio(15, weight: 700))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(LCARSColor.gloss(LCARSColor.iceBlue)))
            .frame(width: 90, alignment: .trailing)
        }
    }
}
