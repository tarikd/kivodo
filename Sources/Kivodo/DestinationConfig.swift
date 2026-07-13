import Foundation
import KivodoCore

/// The two panel destinations, persisted by Settings and read by
/// PanelController on every panel show.
enum DestinationConfig {
    static let keys = (id1: "destinationList1ID", title1: "destinationList1Title",
                       id2: "destinationList2ID", title2: "destinationList2Title")

    /// Both lists when configured and different; empty otherwise.
    static func load(from defaults: UserDefaults = .standard) -> [ReminderList] {
        guard
            let id1 = defaults.string(forKey: keys.id1), !id1.isEmpty,
            let id2 = defaults.string(forKey: keys.id2), !id2.isEmpty,
            id1 != id2
        else { return [] }
        let title1 = defaults.string(forKey: keys.title1) ?? "List 1"
        let title2 = defaults.string(forKey: keys.title2) ?? "List 2"
        return [ReminderList(id: id1, title: title1), ReminderList(id: id2, title: title2)]
    }
}
