import SwiftUI

/// Aba "Textos": anotações à esquerda e histórico de textos copiados à direita.
struct TextsView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: NotchModel
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("Buscar nas anotações e nos textos copiados", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12)).focused($searching)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).frame(height: 22)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 14) {
                if prefs.bool(.modNotes) {
                    NotesPanel(query: query).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if prefs.bool(.modNotes), prefs.bool(.modClipboard) {
                    Divider().opacity(0.4)
                }
                if prefs.bool(.modClipboard) {
                    CopiedPanel(query: query).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: searching) { _, focused in if focused { model.keepOpen = true } }
    }
}

/// Busca sem diferenciar maiúsculas nem acentos.
private func matches(_ text: String, _ query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty || text.localizedStandardContains(trimmed)
}

private struct PanelHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 18)
    }
}

// MARK: - Anotações

private struct NotesPanel: View {
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var model: NotchModel
    let query: String
    @State private var editing: UUID?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let id = editing {
                PanelHeader(title: "Anotação") {
                    iconButton("trash", help: "Apagar anotação") {
                        notes.delete(id)
                        editing = nil
                    }
                    iconButton("checkmark", help: "Concluir") { close(id) }
                }
                TextEditor(text: $draft)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: draft) { _, text in notes.update(id, text: text) }
            } else {
                PanelHeader(title: "Anotações") {
                    iconButton("plus", help: "Nova anotação") { open(notes.add()) }
                }
                let visible = notes.notes.filter { matches($0.text, query) }
                if notes.notes.isEmpty {
                    emptyState
                } else if visible.isEmpty {
                    noResults
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(visible) { note in
                                NoteRow(note: note) { open(note.id) }
                            }
                        }
                    }
                }
            }
        }
        // Enquanto estiver digitando, o notch não fecha ao tirar o mouse.
        .onChange(of: focused) { _, isFocused in model.keepOpen = isFocused }
        .onDisappear {
            model.keepOpen = false
            if let id = editing { notes.discardIfEmpty(id) }
        }
    }

    private var noResults: some View {
        Text("Nenhuma anotação com esse texto").font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nenhuma anotação").font(.system(size: 12, weight: .medium))
            Button("Criar anotação") { open(notes.add()) }.font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ id: UUID) {
        draft = notes.text(of: id)
        editing = id
        focused = true
    }

    private func close(_ id: UUID) {
        notes.discardIfEmpty(id)
        focused = false
        editing = nil
    }

    private func iconButton(_ icon: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 18)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct NoteRow: View {
    let note: Note
    let open: () -> Void
    @EnvironmentObject var notes: NotesStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(note.title).font(.system(size: 12)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(note.updated, format: .dateTime.day().month(.abbreviated))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Button { notes.delete(note.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).opacity(hovering ? 1 : 0)
                .help("Apagar")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.white.opacity(hovering ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .help("Clique para abrir")
    }
}

// MARK: - Textos copiados

private struct CopiedPanel: View {
    @EnvironmentObject var clipboard: ClipboardManager
    let query: String

    var body: some View {
        let visible = clipboard.items.filter { matches($0.text, query) }
        VStack(spacing: 4) {
            PanelHeader(title: "Textos copiados") {
                if !clipboard.items.isEmpty {
                    Button("Limpar", action: clipboard.clear)
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if clipboard.items.isEmpty {
                Text("Os textos que você copiar aparecem aqui.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text("Nenhum texto copiado com esse trecho").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visible) { CopiedRow(item: $0) }
                    }
                }
            }
        }
    }
}

private struct CopiedRow: View {
    let item: ClipItem
    @EnvironmentObject var clipboard: ClipboardManager
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var prefs: Prefs
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(copied ? L("Copiado") : item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12, weight: copied ? .semibold : .regular)).lineLimit(1)
                .foregroundStyle(copied ? Color.green : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                if prefs.bool(.modNotes) {
                    Button { notes.add(item.text) } label: { Image(systemName: "note.text.badge.plus").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Salvar como anotação")
                }
                Button { clipboard.remove(item) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remover do histórico")
            } else {
                Text(item.date, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.white.opacity(hovering ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            clipboard.copy(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
        }
        .help("Clique para copiar de novo")
    }
}
