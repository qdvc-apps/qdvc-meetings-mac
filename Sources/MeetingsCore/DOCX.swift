import Foundation

/// Writes a meeting's notes as a Word document: a handful of OOXML parts in
/// a ZIP. It uses the built-in Title, Heading 1, List Bullet and Hyperlink
/// styles, so the document picks up the reader's theme when restyled.
public enum DocxExport {
    public static func document(_ m: Meeting, formatter: MeetingFormatter = MeetingFormatter(),
                                created: Date = Date()) -> Data {
        let c = ExportContent(m, formatter: formatter)
        var body = Body()

        body.paragraph(style: "Title", runs: [.text(c.title)])
        body.paragraph(runs: [.text(c.when)])
        if !c.location.isEmpty {
            if let url = c.locationURL {
                // The URL stays visible, so it survives printing.
                if let service = m.locationKind.serviceName {
                    body.paragraph(runs: [.bold("Location: "), .text("\(service) ("), .link(url, url), .text(")")])
                } else {
                    body.paragraph(runs: [.bold("Location: "), .link(url, url)])
                }
            } else {
                body.paragraph(runs: [.bold("Location: "), .text(c.location)])
            }
        }
        if !c.people.isEmpty {
            body.paragraph(runs: [.bold("People: "), .text(c.people.joined(separator: ", "))])
        }
        if !c.details.isEmpty {
            body.paragraph(runs: [.text(c.details)], spaceBefore: true)
        }

        body.paragraph(style: "Heading1", runs: [.text("Notes")])
        if c.items.isEmpty {
            body.paragraph(runs: [.italic("No notes.")])
        } else {
            for item in c.items {
                let label = NotesExport.label(item, plain: false)
                var runs: [Run] = []
                if !label.isEmpty { runs.append(.bold(label)) }
                runs.append(.text(item.text))
                body.paragraph(style: "ListBullet", runs: runs)
            }
        }
        let actions = c.actionItems
        if !actions.isEmpty {
            body.paragraph(style: "Heading1", runs: [.text("Action items")])
            for item in actions {
                body.paragraph(style: "ListBullet", runs: [.bold(NotesExport.owner(item) + ": "), .text(item.text)])
            }
        }

        var zip = ZipWriter(date: created)
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", packageRels)
        zip.add("docProps/core.xml", coreProperties(title: c.title, created: created))
        zip.add("word/document.xml", body.documentXML())
        zip.add("word/_rels/document.xml.rels", body.relsXML())
        zip.add("word/styles.xml", styles)
        zip.add("word/numbering.xml", numbering)
        return zip.finish()
    }

    // MARK: Body

    enum Run {
        case text(String)
        case bold(String)
        case italic(String)
        case link(String, String)
    }

    struct Body {
        var paragraphs: [String] = []
        var links: [String] = []

        mutating func paragraph(style: String? = nil, runs: [Run], spaceBefore: Bool = false) {
            var ppr = ""
            if let style { ppr += "<w:pStyle w:val=\"\(style)\"/>" }
            if spaceBefore { ppr += "<w:spacing w:before=\"160\"/>" }
            var xml = "<w:p>"
            if !ppr.isEmpty { xml += "<w:pPr>\(ppr)</w:pPr>" }
            for run in runs {
                switch run {
                case .text(let s): xml += runXML(s, props: "")
                case .bold(let s): xml += runXML(s, props: "<w:b/>")
                case .italic(let s): xml += runXML(s, props: "<w:i/>")
                case .link(let s, let url):
                    links.append(url)
                    xml += "<w:hyperlink r:id=\"rIdLink\(links.count)\" w:history=\"1\">"
                    xml += runXML(s, props: "<w:rStyle w:val=\"Hyperlink\"/>")
                    xml += "</w:hyperlink>"
                }
            }
            xml += "</w:p>"
            paragraphs.append(xml)
        }

        /// A run, with line breaks for newlines.
        func runXML(_ s: String, props: String) -> String {
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            var xml = "<w:r>"
            if !props.isEmpty { xml += "<w:rPr>\(props)</w:rPr>" }
            for (i, line) in lines.enumerated() {
                if i > 0 { xml += "<w:br/>" }
                xml += "<w:t xml:space=\"preserve\">\(DocxExport.escape(String(line)))</w:t>"
            }
            return xml + "</w:r>"
        }

        func documentXML() -> String {
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <w:body>\(paragraphs.joined())\
            <w:sectPr><w:pgSz w:w="11906" w:h="16838"/>\
            <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>\
            </w:sectPr></w:body></w:document>
            """
        }

        func relsXML() -> String {
            var rels = """
            <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
            <Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
            """
            for (i, url) in links.enumerated() {
                rels += "<Relationship Id=\"rIdLink\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(DocxExport.escape(url))\" TargetMode=\"External\"/>"
            }
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
            """
        }
    }

    /// XML-escapes text and drops characters XML 1.0 cannot hold.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                let v = scalar.value
                let allowed = v == 0x9 || v == 0xA || v == 0xD || (0x20...0xD7FF).contains(v)
                    || (0xE000...0xFFFD).contains(v) || (0x10000...0x10FFFF).contains(v)
                if allowed { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }

    // MARK: Fixed parts

    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
    </Types>
    """

    static let packageRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    </Relationships>
    """

    static func coreProperties(title: String, created: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let stamp = f.string(from: created)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(escape(title))</dc:title><dc:creator>QDVC Meetings</dc:creator>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:created>\
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:modified>\
        </cp:coreProperties>
        """
    }

    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:docDefaults><w:rPrDefault><w:rPr>\
    <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>\
    <w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-GB"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>\
    </w:docDefaults>\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
    <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>\
    <w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="120"/><w:contextualSpacing/></w:pPr>\
    <w:rPr><w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:kern w:val="28"/>\
    <w:sz w:val="52"/><w:szCs w:val="52"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>\
    <w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/>\
    <w:spacing w:before="280" w:after="80"/><w:outlineLvl w:val="0"/></w:pPr>\
    <w:rPr><w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:color w:val="2F5496"/>\
    <w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/>\
    <w:qFormat/><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr><w:spacing w:after="60"/></w:pPr></w:style>\
    <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont">\
    <w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/></w:style>\
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/>\
    <w:basedOn w:val="DefaultParagraphFont"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>\
    </w:styles>
    """

    static let numbering = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/>\
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="\u{2022}"/>\
    <w:lvlJc w:val="left"/><w:pPr><w:ind w:left="360" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>\
    <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>\
    </w:numbering>
    """
}
