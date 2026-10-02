import SwiftUI
import Testing

struct NoteParserTests {
    @Test func parsesCheckboxesBulletsAndHeadings() {
        let lines = NoteParser.parse("# Today\n[ ] one\n- [x] two\n- three\nplain\n")
        #expect(lines[0].kind == .heading && lines[0].content == "Today")
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

    @Test func shareTextIsReadable() {
        #expect(NoteParser.shareText("# Hi\n[x] a\n[ ] b\n- c") == "HI\n☑︎ a\n☐ b\n• c")
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
