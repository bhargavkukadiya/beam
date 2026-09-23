import AppKit

@MainActor
enum FeedbackService {
    static func confirmAction() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
