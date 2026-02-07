import SwiftUI
import WidgetKit

// MARK: - Widget Bundle

@main
struct CuraKnotWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextTaskComplication()
        LastHandoffComplication()
        EmergencyComplication()
    }
}
