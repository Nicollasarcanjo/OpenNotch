import Foundation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var updated = Date()

    /// Primeira linha não vazia, usada como título na lista.
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map { $0.trimmingCharacters(in: .whitespaces) } ?? L("Anotação vazia")
    }
}

/// Anotações do usuário, salvas em Application Support/OpenNotch/notes.json.
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    private let file: URL
    private var pending: DispatchWorkItem?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("notes.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        } else {
            // Versões antigas tinham um bloco de notas único em notes.txt.
            let legacy = dir.appendingPathComponent("notes.txt")
            if let text = try? String(contentsOf: legacy, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes = [Note(text: text)]
                scheduleSave()
            }
        }
    }

    @discardableResult
    func add(_ text: String = "") -> UUID {
        let note = Note(text: text)
        notes.insert(note, at: 0)
        scheduleSave()
        return note.id
    }

    func text(of id: UUID) -> String {
        notes.first { $0.id == id }?.text ?? ""
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updated = Date()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Anotações criadas e deixadas em branco não ficam na lista.
    func discardIfEmpty(_ id: UUID) {
        if text(of: id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { delete(id) }
    }

    private func scheduleSave() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let data = try? JSONEncoder().encode(self.notes) else { return }
            try? data.write(to: self.file, options: .atomic)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
}
