import SwiftUI
import WidgetKit

@main
struct FyrWidgetBundle: WidgetBundle {
    var body: some Widget {
        FyrWidget()
        FireLiveActivityWidget()
        FireOffControl()
        WaveModeControl()
        LightFireControl()
    }
}
