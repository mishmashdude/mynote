import SwiftUI
import WidgetKit

@main
struct MynoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoteWidget()
        NoteLiveActivity()
        LiveToggleControl()
        KeepOnLockScreenControl()
    }
}
