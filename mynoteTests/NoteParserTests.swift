import SwiftUI
import Testing

struct NoteParserTests {
    @Test func parsesCheckboxesBulletsAndHeadings() {
        let lines = NoteParser.parse("# Today\n[ ] one\n- [x] two\n- three\nplain\n")
        #expect(lines[0].kind == .heading(1) && lines[0].content == "Today")
        #expect(lines[1].kind == .todo(checked: false) && lines[1].content == "one")
        #expect(lines[2].kind == .todo(checked: true) && lines[2].content == "two")
        #expect(lines[3].kind == .bullet && lines[3].content == "three")
        #expect(lines[4].kind == .text && lines[4].content == "plain")
        #expect(lines[5].kind == .blank)
    }

    @Test func acceptsLooseCheckboxSpellings() {
        #expect(NoteParser.parseLine("[] empty box", index: 0).kind == .todo(checked: false))
        #expect(NoteParser.parseLine("[X] caps", index: 0).kind == .todo(checked: true))
        #expect(NoteParser.parseLine("* [ ] star bullet", index: 0).kind == .todo(checked: false))
        #expect(NoteParser.parseLine("[link] not a box", index: 0).kind == .text)
        #expect(NoteParser.parseLine("-no space", index: 0).kind == .text)
        #expect(NoteParser.parseLine("#hashtag", index: 0).kind == .text)
    }

    @Test func togglesOnlyTheRequestedLine() {
        let text = "[ ] a\n- [ ] b\nplain"
        #expect(NoteParser.toggle(text, line: 1) == "[ ] a\n- [x] b\nplain")
        #expect(NoteParser.toggle(NoteParser.toggle(text, line: 0), line: 0) == text)
        #expect(NoteParser.toggle(text, line: 2) == text)
        #expect(NoteParser.toggle(text, line: 9) == text)
        #expect(NoteParser.toggle("[] a", line: 0) == "[x] a")
    }

    @Test func markersDoNotCountTowardTheLimit() {
        #expect(NoteParser.countedLength("[ ] milk") == 4)
        #expect(NoteParser.countedLength("- [x] milk\n- eggs") == 4 + 1 + 4)
        #expect(NoteParser.countedLength("") == 0)
    }

    @Test func continuationKeepsStyleButUnchecks() {
        let todo = NoteParser.parseLine("- [x] done", index: 0)
        #expect(NoteParser.continuationPrefix(for: todo) == "- [ ] ")
        let bullet = NoteParser.parseLine("* item", index: 0)
        #expect(NoteParser.continuationPrefix(for: bullet) == "* ")
        #expect(NoteParser.continuationPrefix(for: NoteParser.parseLine("plain", index: 0)) == nil)
    }

    @Test func tidyClearsEmptyFormattingPairs() {
        #expect(NoteParser.tidy("a\n****") == "a")
        #expect(NoteParser.tidy("****\nb") == "\nb")
        #expect(NoteParser.tidy("- [ ] ****\n- c") == "- [ ] \n- c")
        #expect(NoteParser.tidy("***") == "***")
    }

    @Test func keycapEmojiIsNotEmphasis() {
        #expect(InlineMarkdown.plain("*️⃣ one *️⃣") == "*️⃣ one *️⃣")
    }

    @Test func tidyRemovesTrailingEmptyItems() {
        #expect(NoteParser.tidy("[ ] a\n[ ] \n\n- ") == "[ ] a")
        #expect(NoteParser.tidy("a\n\nb") == "a\n\nb")
    }

    @Test func visibleLinesSkipEmptyItemsAndProgressIgnoresThem() {
        let text = "[x] a\n[ ] \n[ ] b\n\n"
        #expect(NoteParser.visibleLines(text).map(\.content) == ["a", "b"])
        let progress = NoteParser.progress(text)
        #expect(progress.done == 1 && progress.total == 2)
    }

    @Test func bulkEdits() {
        let text = "[x] a\n[ ] b\n- c\n[x] d"
        #expect(NoteParser.setAllTodos(text, checked: false) == "[ ] a\n[ ] b\n- c\n[ ] d")
        #expect(NoteParser.removeCheckedTodos(text) == "[ ] b\n- c")
    }

    @Test func fitHidesFinishedItemsFirst() {
        let lines = NoteParser.parse("[x] a\n[ ] b\n[x] c\n[ ] d\n[ ] e")
        let fitted = FittedNoteLines.fit(lines, into: 3)
        #expect(fitted.shown.map(\.content) == ["b", "d", "e"])
        #expect(fitted.summary == "2 done")
        let tight = FittedNoteLines.fit(lines, into: 2)
        #expect(tight.shown.map(\.content) == ["b", "d"])
        #expect(tight.summary == "+1 more · 2 done")
    }

    @Test func fitKeepsTheJustTickedItem() {
        let lines = NoteParser.parse("[x] a\n[ ] b\n[x] c\n[ ] d\n[ ] e")
        let fitted = FittedNoteLines.fit(lines, into: 4, keeping: 2)
        #expect(fitted.shown.map(\.content) == ["b", "c", "d", "e"])
        #expect(fitted.summary == "1 done")
    }

    @Test func shareTextIsReadable() {
        #expect(NoteParser.shareText("# Hi\n[x] a\n[ ] b\n- c") == "HI\n☑︎ a\n☐ b\n• c")
        #expect(NoteParser.shareText("1. **one**\n1. two\n  - deep") == "1. one\n2. two\n  • deep")
    }

    @Test func parsesTheWiderMarkdownSet() {
        let lines = NoteParser.parse("## Sub\n### Small\n#### Tiny\n1. one\n1) two\n> said\n---\n* * *\n  - nested\n    - deeper\n+ plus")
        #expect(lines[0].kind == .heading(2))
        #expect(lines[1].kind == .heading(3))
        #expect(lines[2].kind == .heading(3))
        #expect(lines[3].kind == .numbered(1) && lines[3].ordinal == 1)
        #expect(lines[4].kind == .numbered(1) && lines[4].ordinal == 2)
        #expect(lines[5].kind == .quote && lines[5].content == "said")
        #expect(lines[6].kind == .divider)
        #expect(lines[7].kind == .divider)
        #expect(lines[8].kind == .bullet && lines[8].indent == 1)
        #expect(lines[9].kind == .bullet && lines[9].indent == 2)
        #expect(lines[10].kind == .bullet)
    }

    @Test func numberingRestartsAfterOtherLines() {
        let lines = NoteParser.parse("3. a\n4. b\n\n5. c\ntext\n1. d\n  1. e\n2. f")
        #expect(lines.compactMap(\.ordinal) == [3, 4, 5, 1, 1, 2])
    }

    @Test func continuationNumbersAndQuotes() {
        #expect(NoteParser.continuationPrefix(for: NoteParser.parseLine("  4) four", index: 0)) == "  5) ")
        #expect(NoteParser.continuationPrefix(for: NoteParser.parseLine("> quote", index: 0)) == "> ")
    }

    @Test func inlineSymbolsDoNotCount() {
        #expect(NoteParser.countedLength("**milk**") == 4)
        #expect(NoteParser.countedLength("- [ ] ==eggs== and `jam`") == 12)
        #expect(NoteParser.countedLength("\\*not italic\\*") == 12)
    }

    @Test func liveActivityTextStaysSmall() {
        let url = "https://maps.example.com/" + String(repeating: "x", count: 1_500)
        let note = "- [ ] [menu](\(url))\n- [ ] [map](\(url))\n- [ ] [cafe](\(url))"
        let compact = NoteParser.compactForLiveActivity(note)
        #expect(compact == "- [ ] [menu](#)\n- [ ] [map](#)\n- [ ] [cafe](#)")
        #expect(NoteParser.shareText(compact) == NoteParser.shareText(note))
        let huge = String(repeating: "- [ ] item\n", count: 400)
        #expect(NoteParser.compactForLiveActivity(huge).utf8.count <= 3_000)
    }

    @Test func spokenTextHasNoSymbols() {
        #expect(NoteParser.spokenText("# Hi\n- [x] **a**\n- b\n---\n> c") == "Hi. a, done. b. c")
    }

    @Test func emptyItemsAndRepeatedBlankLinesAreHidden() {
        let visible = NoteParser.visibleLines("# \na\n\n\n\nb\n> \n- ")
        #expect(visible.map(\.plainContent) == ["a", "", "b"])
    }
}

struct InlineMarkdownTests {
    private func describe(_ s: String) -> String {
        InlineMarkdown.runs(s).map { run in
            var tags = ""
            if run.style.contains(.bold) { tags += "B" }
            if run.style.contains(.italic) { tags += "I" }
            if run.style.contains(.strike) { tags += "S" }
            if run.style.contains(.code) { tags += "C" }
            if run.style.contains(.highlight) { tags += "H" }
            if run.style.contains(.link) { tags += "L" }
            return tags.isEmpty ? run.text : "\(tags)(\(run.text))"
        }.joined()
    }

    @Test func readsEmphasisLikeCommonMark() {
        #expect(describe("**bold** and *it*") == "B(bold) and I(it)")
        #expect(describe("***a**b*") == "BI(a)I(b)")
        #expect(describe("**a*b***") == "B(a)BI(b)")
        #expect(describe("*a **b** c*") == "I(a )BI(b)I( c)")
        #expect(describe("snake_case_word") == "snake_case_word")
        #expect(describe("a ** b ** c") == "a ** b ** c")
        #expect(describe("**unclosed") == "**unclosed")
    }

    @Test func readsTheExtras() {
        #expect(describe("~~gone~~ ok") == "S(gone) ok")
        #expect(describe("==hi== there") == "H(hi) there")
        #expect(describe("a == b") == "a == b")
        #expect(describe("`co*de*` x") == "C(co*de*) x")
        #expect(describe("\\*not\\* it") == "*not* it")
        let link = InlineMarkdown.runs("[site](https://x.com) end")
        #expect(link.first?.style == .link && link.first?.url == "https://x.com" && link.first?.text == "site")
    }

    @Test func piecesCoverTheWholeLine() {
        let source = "a **b** [c](u) `d` \\*"
        let pieces = InlineMarkdown.pieces(source)
        #expect(pieces.map(\.text).joined() == source)
        #expect(pieces.filter(\.isSyntax).map(\.text) == ["**", "**", "[", "](u)", "`", "`", "\\"])
    }
}

struct RichTextCodecTests {
    /// Markdown → rich → Markdown.
    private func roundTrip(_ markdown: String) -> String {
        RichTextCodec.markdown(from: RichTextCodec.attributedString(from: markdown))
    }

    @Test func canonicalMarkdownSurvivesUnchanged() {
        let samples = [
            "# Title\n## Sub\n### Small",
            "- [ ] task\n- [x] done\n  - nested\n    - deeper",
            "1. one\n2. two\n  1. inner\n3. three",
            "> quote with **bold**\n---\nplain *italic* ~~strike~~ ==mark== `code`",
            "a [link](https://example.com) here",
            "***both*** and **bold *mixed* in**",
            "",
            "line\n\nafter blank",
        ]
        for sample in samples {
            #expect(roundTrip(sample) == sample, "\(sample)")
        }
    }

    @Test func otherSpellingsBecomeStandardOnes() {
        #expect(roundTrip("[ ] legacy\n[x] done\n* star\n+ plus\n__bold__ _it_") == "- [ ] legacy\n- [x] done\n- star\n- plus\n**bold** *it*")
        #expect(roundTrip("1. a\n1. b\n1. c") == "1. a\n2. b\n3. c")
        #expect(roundTrip("5) five") == "5. five")
    }

    @Test func plainTextThatLooksLikeMarkdownStaysPlain() {
        let tricky = ["\\- not a bullet", "\\# not a heading", "2026\\. a year", "5 \\* 3", "\\[x\\] not a box", "\\> not a quote", "\\---"]
        for sample in tricky {
            let rich = RichTextCodec.attributedString(from: sample)
            let again = RichTextCodec.markdown(from: rich)
            #expect(NoteParser.parse(again).map(\.kind) == NoteParser.parse(sample).map(\.kind), "\(sample) -> \(again)")
            #expect(NoteParser.shareText(again) == NoteParser.shareText(sample), "\(sample) -> \(again)")
        }
    }

    @Test func overlappingStylesAreSavedFaithfully() {
        // Bold "ab", italic "bc": the styles overlap, which needs careful Markdown.
        let text = NSMutableAttributedString(string: "abc")
        text.addAttribute(.noteInline, value: InlineStyle.bold.rawValue, range: NSRange(location: 0, length: 1))
        text.addAttribute(.noteInline, value: InlineStyle([.bold, .italic]).rawValue, range: NSRange(location: 1, length: 1))
        text.addAttribute(.noteInline, value: InlineStyle.italic.rawValue, range: NSRange(location: 2, length: 1))
        let markdown = RichTextCodec.markdown(from: text)
        let runs = InlineMarkdown.runs(markdown)
        #expect(runs.map(\.text) == ["a", "b", "c"], "\(markdown)")
        #expect(runs.map(\.style) == [.bold, [.bold, .italic], .italic], "\(markdown)")
    }

    @Test func stylesStepOffSpacesAtTheEdges() {
        let text = NSMutableAttributedString(string: "say hi there")
        text.addAttribute(.noteInline, value: InlineStyle.bold.rawValue, range: NSRange(location: 3, length: 4))
        #expect(RichTextCodec.markdown(from: text) == "say **hi** there")
    }

    /// Builds rich text by hand: one paragraph, optionally behind a marker.
    private func rich(_ words: String, block: RichBlock? = nil, styles: [(InlineStyle, NSRange)] = [],
                      link: (String, NSRange)? = nil) -> NSMutableAttributedString {
        let text = NSMutableAttributedString()
        if let block { text.append(NSAttributedString(attachment: MarkerAttachment(block: block))) }
        let offset = text.length
        text.append(NSAttributedString(string: words))
        for (style, range) in styles {
            text.addAttribute(.noteInline, value: style.rawValue, range: NSRange(location: offset + range.location, length: range.length))
        }
        if let link {
            text.addAttribute(.noteLink, value: link.0, range: NSRange(location: offset + link.1.location, length: link.1.length))
        }
        return text
    }

    @Test func leadingSpacesSurviveAndNeverMakeAList() {
        for words in ["  - milk", "  # big", "\t> x", " ---"] {
            let markdown = RichTextCodec.markdown(from: rich(words))
            let line = NoteParser.parseLine(markdown, index: 0)
            #expect(line.kind == .text, "\(words) -> \(markdown)")
            #expect(line.plainContent.replacingOccurrences(of: "\u{00A0}", with: " ")
                    == words.replacingOccurrences(of: "\t", with: "  "), "\(words) -> \(markdown)")
        }
    }

    @Test func listWordsThatLookLikeADividerStayWords() {
        let markdown = RichTextCodec.markdown(from: rich("--", block: RichBlock(kind: .bullet)))
        let line = NoteParser.parseLine(markdown, index: 0)
        #expect(line.kind == .bullet && line.plainContent == "--", "\(markdown)")
    }

    @Test func linksWithBracketsInTheAddressKeepTheirLink() {
        let url = "https://en.wikipedia.org/wiki/Swift_(language)"
        var lossy = false
        let markdown = RichTextCodec.markdown(from: rich("Swift and bold", styles: [(.bold, NSRange(location: 10, length: 4))],
                                                         link: (url, NSRange(location: 0, length: 5))), lossy: &lossy)
        #expect(!lossy, "\(markdown)")
        let runs = InlineMarkdown.runs(markdown)
        #expect(runs.first?.style == .link && runs.first?.url?.hasPrefix("https://en.wikipedia.org/wiki/Swift_") == true)
        #expect(runs.last?.style == .bold && runs.last?.text == "bold")
    }

    @Test func unwritableStylesAreDroppedOneRunAtATime() {
        // Bold that ends on punctuation right before a letter can't be written in Markdown;
        // only that run should lose its style, not the italic elsewhere on the line.
        var lossy = false
        let text = rich("Hi! x and more", styles: [(.bold, NSRange(location: 0, length: 3)), (.italic, NSRange(location: 10, length: 4))])
        text.replaceCharacters(in: NSRange(location: 3, length: 1), with: "")   // "Hi!x and more"
        let markdown = RichTextCodec.markdown(from: text, lossy: &lossy)
        let runs = InlineMarkdown.runs(markdown)
        #expect(runs.map(\.text).joined() == "Hi!x and more", "\(markdown)")
        #expect(runs.contains { $0.style == .italic && $0.text == "more" }, "\(markdown)")
    }

    @Test func aLinkCalledXIsNotATickedBox() {
        #expect(NoteParser.parseLine("[x](https://x.com) news", index: 0).kind == .text)
        let markdown = RichTextCodec.markdown(from: rich("x", link: ("https://x.com", NSRange(location: 0, length: 1))))
        #expect(NoteParser.parseLine(markdown, index: 0).kind == .text, "\(markdown)")
    }

    @Test func visibleCountMatchesTheMarkdownCount() {
        let samples = ["- [ ] **milk**\n- eggs", "# Head\n> quote\n---\n1. one", "plain"]
        for sample in samples {
            let rich = RichTextCodec.attributedString(from: sample)
            #expect(RichTextCodec.visibleCount(rich.string) == NoteParser.countedLength(sample), "\(sample)")
        }
    }
}

struct ThemeTests {
    @Test func catalogIDsAreUniqueAndResolvable() {
        let ids = ThemeCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ThemeCatalog.theme("dracula").name == "Dracula")
        #expect(ThemeCatalog.theme("nope").id == ThemeCatalog.defaultLightID)
    }

    @Test func darknessMatchesBackground() {
        #expect(ThemeCatalog.theme("serika-dark").isDark)
        #expect(!ThemeCatalog.theme("serika").isDark)
        #expect(!ThemeCatalog.theme(ThemeCatalog.defaultLightID).isDark)
    }

    @Test func themeChoiceFollowsSystemWhenMatching() {
        let choice = ThemeChoice(matchSystem: true, themeID: "nord", lightThemeID: "paper", darkThemeID: "dracula")
        #expect(choice.theme(for: .light).id == "paper")
        #expect(choice.theme(for: .dark).id == "dracula")
        #expect(choice.forcedScheme == nil)
        let fixed = ThemeChoice(matchSystem: false, themeID: "nord", lightThemeID: "paper", darkThemeID: "dracula")
        #expect(fixed.theme(for: .light).id == "nord")
        #expect(fixed.forcedScheme == .dark)
    }
}

struct ThemeAccessTests {
    private let picks = ThemeChoice(matchSystem: false, themeID: "dracula", lightThemeID: "paper", darkThemeID: "nord")

    @Test func lockedPicksShowDefaultsWithoutLosingThem() {
        let free = ThemeAccess(isSupporter: false, kept: [], rulesApply: true)
        let shown = picks.allowed(by: free)
        #expect(shown.themeID == ThemeCatalog.defaultDarkID)      // Dracula is dark
        #expect(shown.lightThemeID == ThemeCatalog.defaultLightID)
        #expect(shown.darkThemeID == ThemeCatalog.defaultDarkID)
        #expect(picks.themeID == "dracula")                        // the pick itself is untouched
    }

    @Test func supportersAndKeptThemesShowAsPicked() {
        #expect(picks.allowed(by: ThemeAccess(isSupporter: true, kept: [], rulesApply: true)) == picks)
        let kept = picks.allowed(by: ThemeAccess(isSupporter: false, kept: ["dracula"], rulesApply: true))
        #expect(kept.themeID == "dracula" && kept.lightThemeID == ThemeCatalog.defaultLightID)
    }

    @Test func nothingIsLockedBeforeTheUpdateFirstRuns() {
        #expect(picks.allowed(by: ThemeAccess(isSupporter: false, kept: [], rulesApply: false)) == picks)
    }

    @Test func onlyTheDefaultsAreFree() {
        let free = ThemeAccess(isSupporter: false, kept: [], rulesApply: true)
        #expect(ThemeCatalog.all.filter { free.allows($0.id) }.map(\.id).sorted() == [ThemeCatalog.defaultDarkID, ThemeCatalog.defaultLightID])
    }

    @Test func aLockedPurpleThemeResolvesToTheMatchingDefault() {
        let access = ThemeAccess(isSupporter: false, kept: [], rulesApply: true)
        #expect(access.resolved("lil-dragon") == ThemeCatalog.defaultLightID)
        #expect(access.resolved("dracula") == ThemeCatalog.defaultDarkID)
        #expect(access.resolved(ThemeCatalog.defaultLightID) == ThemeCatalog.defaultLightID)
        let kept = ThemeAccess(isSupporter: false, kept: ["lil-dragon"], rulesApply: true)
        #expect(kept.resolved("lil-dragon") == "lil-dragon")
        let choice = ThemeChoice(matchSystem: true, themeID: "lil-dragon", lightThemeID: "lil-dragon", darkThemeID: "dracula")
        let shown = choice.allowed(by: access)
        #expect(shown.lightThemeID == ThemeCatalog.defaultLightID)
        #expect(shown.darkThemeID == ThemeCatalog.defaultDarkID)
        #expect(choice.lightThemeID == "lil-dragon")
    }
}

struct LiveActivityAppearanceTests {
    @Test func appearanceIgnoresTheNoteText() {
        let purple = NoteActivityAttributes.ContentState(
            text: "one", lightThemeID: "lil-dragon", darkThemeID: "dracula",
            font: .system, textSize: .regular, style: .theme, relaying: true)
        let edited = NoteActivityAttributes.ContentState(
            text: "two", lightThemeID: "lil-dragon", darkThemeID: "dracula",
            font: .system, textSize: .regular, style: .theme, relaying: false, justTicked: 1)
        let reset = NoteActivityAttributes.ContentState(
            text: "one", lightThemeID: ThemeCatalog.defaultLightID, darkThemeID: ThemeCatalog.defaultDarkID,
            font: .system, textSize: .regular, style: .theme, relaying: true)
        #expect(purple.hasSameAppearance(as: edited))
        #expect(!purple.hasSameAppearance(as: reset))
    }
}

struct ContrastTests {
    @Test func wcagContrastMatchesKnownValues() {
        #expect(abs(Theme.contrast(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(Theme.contrast(0xFFFFFF, 0xFFFFFF) - 1) < 0.01)
    }

    @Test func everyThemeIsReadable() {
        for t in ThemeCatalog.all {
            let text = min(Theme.contrast(t.text, t.card), Theme.contrast(t.text, t.bg))
            #expect(text >= 4.5, "\(t.name) text contrast \(text)")
            #expect(Theme.contrast(t.main, t.card) >= 2.5, "\(t.name) accent contrast")
            #expect(Theme.contrast(t.editorCaret, t.card) >= 3 || t.editorCaret == t.text, "\(t.name) caret")
        }
    }

    @Test func darkThemesHaveLightText() {
        for t in ThemeCatalog.all where t.isDark {
            #expect(t.hasLightText, "\(t.name)")
        }
    }
}
