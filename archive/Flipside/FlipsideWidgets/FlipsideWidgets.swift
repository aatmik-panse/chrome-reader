import WidgetKit
import SwiftUI

@main
struct FlipsideWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingWidget()
        LockScreenWidget()
    }
}
