import AppKit
import UniformTypeIdentifiers

extension Store {
    static var archiveType: UTType {
        UTType(filenameExtension: "mynotes") ?? .json
    }

    // MARK: - Область экспорта

    func currentScope() -> ExportScope {
        if let id = activeTab { return .note(id) }
        if let id = selectedProject { return .project(id) }
        return .all
    }

    func scopeTitle(_ scope: ExportScope) -> String {
        switch scope {
        case .all: return "Все заметки"
        case .project(let id): return projectName(id)
        case .note(let id): return title(for: id)
        }
    }

    // MARK: - Сборка и запись архива

    func buildArchive(_ scope: ExportScope) -> Archive {
        var projectIDs: Set<UUID> = []
        var noteIDs: Set<UUID> = []
        var rootProject: UUID?
        var flattenNotes = false

        switch scope {
        case .all:
            projectIDs = Set(projects.map(\.id))
            noteIDs = Set(notes.map(\.id))
        case .project(let id):
            rootProject = id
            projectIDs = descendants(of: id).union([id])
            noteIDs = Set(notes.filter { n in n.projectID.map(projectIDs.contains) ?? false }.map(\.id))
        case .note(let id):
            noteIDs = [id]
            flattenNotes = true
        }

        let archivedProjects = projects.filter { projectIDs.contains($0.id) }.map { p in
            ArchivedProject(
                id: p.id.uuidString,
                parentID: p.id == rootProject ? nil : p.parentID?.uuidString,
                name: p.name,
                sort: p.sort
            )
        }
        let archivedNotes = notes.filter { noteIDs.contains($0.id) }.map { n in
            ArchivedNote(
                id: n.id.uuidString,
                projectID: flattenNotes ? nil : n.projectID?.uuidString,
                title: n.title,
                created: n.created,
                updated: n.updated,
                body: body(for: n.id)
            )
        }
        return Archive(projects: archivedProjects, notes: archivedNotes)
    }

    func writeArchive(_ scope: ExportScope, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(buildArchive(scope)).write(to: url, options: .atomic)
    }

    private func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(60)).isEmpty ? "Заметки" : String(cleaned.prefix(60))
    }

    // MARK: - Экспорт в файл

    func exportWithPanel(_ scope: ExportScope) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Store.archiveType]
        panel.nameFieldStringValue = "MyNotes — \(safeFileName(scopeTitle(scope))).mynotes"
        panel.message = "Файл можно открыть в другой копии MyNotes — заметки будут импортированы."
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeArchive(scope, to: url)
        } catch {
            Dialogs.info(title: "Не удалось экспортировать", message: error.localizedDescription)
        }
    }

    // MARK: - AirDrop

    func shareViaAirDrop(_ scope: ExportScope) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MyNotes-share", isDirectory: true)
        let url = dir.appendingPathComponent("MyNotes — \(safeFileName(scopeTitle(scope))).mynotes")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try writeArchive(scope, to: url)
        } catch {
            Dialogs.info(title: "Не удалось подготовить файл", message: error.localizedDescription)
            return
        }
        let items: [Any] = [url]
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) {
            service.perform(withItems: items)
        } else if let view = NSApp.keyWindow?.contentView ?? NSApp.windows.first?.contentView {
            let picker = NSSharingServicePicker(items: items)
            sharingPicker = picker
            let anchor = NSRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
            picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        }
    }

    // MARK: - Импорт .mynotes

    func importArchiveWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Store.archiveType]
        panel.allowsMultipleSelection = true
        panel.message = "Выберите файлы .mynotes, экспортированные из MyNotes"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { importArchive(from: $0) }
    }

    func importArchive(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let archive = try decoder.decode(Archive.self, from: data)
            guard archive.format == "MyNotes" else { throw DBError(message: "Это не файл MyNotes.") }

            var addedProjects = 0, addedNotes = 0, updatedNotes = 0, skippedNotes = 0
            try db.transaction {
                try db.script("PRAGMA defer_foreign_keys = ON;")
                var knownProjects = Set(projects.map { $0.id.uuidString })

                for p in archive.projects where !knownProjects.contains(p.id) {
                    try db.execute(
                        "INSERT INTO projects (id, parent_id, name, sort, created) VALUES (?, ?, ?, ?, ?)",
                        [.text(p.id), p.parentID.map { DBValue.text($0) } ?? .null, .text(p.name),
                         .int(Int64(p.sort)), .real(Date().timeIntervalSince1970)]
                    )
                    knownProjects.insert(p.id)
                    addedProjects += 1
                }
                let allProjects = knownProjects.union(archive.projects.map(\.id))

                for n in archive.notes {
                    let existing = try db.rows("SELECT updated FROM notes WHERE id = ?", [.text(n.id)]) { (r: Row) -> Double in r.real(0) }
                    let projectID = n.projectID.flatMap { allProjects.contains($0) ? $0 : nil }
                    let plain = n.body.flatMap(BodyCodec.decode)?.string.replacingOccurrences(of: "\u{FFFC}", with: " ") ?? ""
                    let blob = n.body.map { DBValue.blob($0) } ?? .null
                    let projectValue = projectID.map { DBValue.text($0) } ?? .null

                    if let current = existing.first {
                        if n.updated.timeIntervalSince1970 > current + 0.5 {
                            try db.execute(
                                "UPDATE notes SET project_id = ?, title = ?, body = ?, plain = ?, updated = ? WHERE id = ?",
                                [projectValue, .text(n.title), blob, .text(plain), .real(n.updated.timeIntervalSince1970), .text(n.id)]
                            )
                            updatedNotes += 1
                        } else {
                            skippedNotes += 1
                        }
                    } else {
                        try db.execute(
                            "INSERT INTO notes (id, project_id, title, body, plain, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?)",
                            [.text(n.id), projectValue, .text(n.title), blob, .text(plain),
                             .real(n.created.timeIntervalSince1970), .real(n.updated.timeIntervalSince1970)]
                        )
                        addedNotes += 1
                    }
                }
            }
            reload()
            NSApp.activate(ignoringOtherApps: true)
            Dialogs.info(
                title: "Импорт завершён",
                message: "Файл: \(url.lastPathComponent)\nДобавлено заметок: \(addedNotes)\nОбновлено: \(updatedNotes)\nПропущено (уже есть и не новее): \(skippedNotes)\nНовых проектов: \(addedProjects)"
            )
        } catch {
            Dialogs.info(title: "Не удалось импортировать «\(url.lastPathComponent)»", message: error.localizedDescription)
        }
    }

    // MARK: - Импорт из OneNote (через экспортированные файлы)

    private struct ImportReport {
        var notes = 0
        var projects = 0
        var skipped: [String] = []
        var failed: [String] = []
    }

    func importOneNoteWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Выберите файлы или папки, экспортированные из OneNote (.docx, .html, .rtf, .odt, .txt). Папки станут вложенными проектами."
        panel.prompt = "Импортировать"
        guard panel.runModal() == .OK else { return }
        importOneNote(urls: panel.urls)
    }

    func importOneNote(urls: [URL]) {
        var report = ImportReport()
        var rootID: UUID?
        attempt {
            try db.transaction {
                if let existing = projects.first(where: { $0.parentID == nil && $0.name == "OneNote" }) {
                    rootID = existing.id
                } else {
                    rootID = try insertProject(name: "OneNote", parent: nil)
                }
                for url in urls {
                    try importItem(url, into: rootID, report: &report)
                }
            }
        }
        reload()
        if let rootID { expanded.insert(rootID) }

        var text = "Импортировано заметок: \(report.notes)\nСоздано проектов: \(report.projects)"
        if !report.failed.isEmpty {
            text += "\n\nНе удалось прочитать: " + report.failed.prefix(8).joined(separator: ", ")
        }
        if !report.skipped.isEmpty {
            text += "\n\nПропущены неподдерживаемые форматы: " + report.skipped.prefix(8).joined(separator: ", ")
            text += "\nВ OneNote выберите «Файл → Экспорт» и сохраните страницы или разделы как Word (.docx)."
        }
        Dialogs.info(title: "Импорт из OneNote", message: text)
    }

    private func importItem(_ url: URL, into parent: UUID?, report: inout ImportReport) throws {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let ext = url.pathExtension.lowercased()

        if isDirectory.boolValue && ext != "rtfd" {
            let projectID = try insertProject(name: url.lastPathComponent, parent: parent)
            report.projects += 1
            let items = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let sorted = items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for item in sorted {
                try importItem(item, into: projectID, report: &report)
            }
            return
        }

        guard Store.supportedImportExtensions.contains(ext) else {
            report.skipped.append(url.lastPathComponent)
            return
        }
        guard let attributed = loadAttributed(url) else {
            report.failed.append(url.lastPathComponent)
            return
        }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        TextTools.normalizeColors(mutable)
        let plain = mutable.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
        var title = TextTools.title(from: plain)
        if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        try insertNote(
            project: parent, title: title, plain: plain,
            body: BodyCodec.encode(mutable), created: created, updated: Date()
        )
        report.notes += 1
    }

    static let supportedImportExtensions: Set<String> = [
        "docx", "doc", "odt", "rtf", "rtfd", "html", "htm", "webarchive", "txt", "md", "markdown"
    ]

    private func loadAttributed(_ url: URL) -> NSAttributedString? {
        let ext = url.pathExtension.lowercased()
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]

        switch ext {
        case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        case "webarchive": options[.documentType] = NSAttributedString.DocumentType.webArchive
        case "html", "htm":
            options[.documentType] = NSAttributedString.DocumentType.html
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        default:
            var encoding = String.Encoding.utf8
            guard let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, usedEncoding: &encoding)) else { return nil }
            return NSAttributedString(string: text, attributes: [.font: TextTools.defaultFont])
        }
        return try? NSAttributedString(url: url, options: options, documentAttributes: nil)
    }
}
