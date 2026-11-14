import SwiftUI

/// The Clips tab: pages and panels you've saved.
struct ClippingsView: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var open: Clip?

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 18, alignment: .top)]

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CLIPPINGS")
                            .font(Theme.display(50))
                            .foregroundColor(Theme.yellow)
                            .shadow(color: Theme.red, radius: 0, x: 3, y: 3)
                        if !store.clips.isEmpty {
                            Text(store.clips.count == 1 ? "1 CLIPPING" : "\(store.clips.count) CLIPPINGS")
                                .font(Theme.caption(11))
                                .italic()
                                .kerning(0.5)
                                .monospacedDigit()
                                .foregroundColor(Theme.paper.opacity(0.7))
                        }
                    }

                    if store.clips.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(store.clips) { clip in
                                Button {
                                    open = clip
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ClipImage(id: clip.id)
                                            .inkPanel(stroke: Theme.paper, shadow: .black)
                                        Text(clip.bookTitle)
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(Theme.paper)
                                            .lineLimit(1)
                                        Text("PAGE \(clip.page + 1)")
                                            .font(Theme.caption(10))
                                            .kerning(0.4)
                                            .monospacedDigit()
                                            .foregroundColor(Theme.paper.opacity(0.6))
                                    }
                                }
                                .buttonStyle(PressDownStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.deleteClip(clip.id)
                                    } label: {
                                        Label("Delete clipping", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $open) { clip in
            ClipDetailView(clip: clip)
                .environmentObject(store)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("NOTHING CLIPPED YET!")
                .font(Theme.display(30))
                .foregroundColor(.black)
            Text("While reading, press and hold a page to clip it. In Panel view or Cinematic mode, that clips just the panel on screen.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color.black.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 46)
        .frame(maxWidth: 330)
        .background(SpeechBubble().fill(Theme.paper))
        .background(SpeechBubble().fill(Theme.yellow).offset(x: 6, y: 6))
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

/// A saved clipping at its own shape.
struct ClipImage: View {
    let id: UUID
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Theme.panel
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .task(id: id) {
            let path = Storage.clipImage(id).path
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
        }
    }
}

/// One clipping up close, with the way back to its page.
struct ClipDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let clip: Clip

    @State private var reading = false
    @State private var confirmingDelete = false

    private var bookExists: Bool { store.book(clip.bookID) != nil }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        CaptionBox(text: "Clipping", shadow: Theme.cyan)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            RoundIcon(systemName: "xmark")
                        }
                        .buttonStyle(PressDownStyle())
                        .accessibilityLabel("Close")
                    }

                    ClipImage(id: clip.id)
                        .inkPanel(corner: 2, line: 3, offset: 6, stroke: Theme.paper, shadow: Theme.red)
                        .padding(.trailing, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(clip.bookTitle)
                            .font(Theme.display(24))
                            .foregroundColor(Theme.paper)
                        Text("PAGE \(clip.page + 1)  •  CLIPPED \(clip.createdAt.formatted(date: .abbreviated, time: .omitted).uppercased())")
                            .font(Theme.caption(11))
                            .italic()
                            .kerning(0.5)
                            .monospacedDigit()
                            .foregroundColor(Theme.paper.opacity(0.7))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        if bookExists {
                            Button("GO TO PAGE") {
                                store.setPage(clip.page, for: clip.bookID)
                                reading = true
                            }
                            .buttonStyle(ComicButtonStyle(size: 20))
                        } else {
                            Text("The comic this came from is no longer in your box.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.paper.opacity(0.55))
                        }
                        HStack(spacing: 16) {
                            ShareLink(item: Storage.clipImage(clip.id)) {
                                Text("SHARE")
                            }
                            .buttonStyle(ComicButtonStyle(fill: Theme.paper, shadow: Theme.cyan, size: 18))

                            Button("DELETE") {
                                confirmingDelete = true
                            }
                            .buttonStyle(ComicButtonStyle(fill: Theme.red, shadow: .black, textColor: Theme.paper, size: 18))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $reading) {
            ReaderHost(bookID: clip.bookID)
                .environmentObject(store)
        }
        .confirmationDialog("Delete this clipping?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteClip(clip.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
