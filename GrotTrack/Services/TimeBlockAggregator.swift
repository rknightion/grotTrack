import SwiftData
import Foundation

@MainActor
final class TimeBlockAggregator {

    /// Aggregate a set of ActivityEvents into a TimeBlock for the given hour.
    func aggregateHour(events: [ActivityEvent], hour: Date) -> TimeBlock {
        let block = TimeBlock(startTime: hour, endTime: hour.addingTimeInterval(3600))

        guard !events.isEmpty else { return block }

        // Group events by appName, sum durations
        var durationByApp: [String: TimeInterval] = [:]
        for event in events {
            durationByApp[event.appName, default: 0] += event.duration
        }

        // Find dominant app (most total duration)
        if let dominant = durationByApp.max(by: { $0.value < $1.value }) {
            block.dominantApp = dominant.key

            // Find the dominant window title within the dominant app
            let dominantEvents = events.filter { $0.appName == dominant.key }
            var durationByTitle: [String: TimeInterval] = [:]
            for event in dominantEvents {
                durationByTitle[event.windowTitle, default: 0] += event.duration
            }
            block.dominantTitle = durationByTitle.max(by: { $0.value < $1.value })?.key ?? ""
        }

        // Calculate average multitasking score from visible window counts
        let totalScore = events.reduce(0.0) { $0 + $1.multitaskingScore }
        block.multitaskingScore = totalScore / Double(events.count)

        // Attach all events to the block
        block.activities = events

        return block
    }

    /// Aggregate all events for a given hour from the database.
    func aggregateHour(for hour: Date, context: ModelContext) -> TimeBlock {
        let endOfHour = hour.addingTimeInterval(3600)

        let predicate = #Predicate<ActivityEvent> {
            $0.timestamp >= hour && $0.timestamp < endOfHour
        }
        let descriptor = FetchDescriptor<ActivityEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )

        let events = (try? context.fetch(descriptor)) ?? []
        let block = aggregateHour(events: events, hour: hour)

        // Auto-match customer by keywords
        let customerDescriptor = FetchDescriptor<Customer>(
            predicate: #Predicate<Customer> { $0.isActive == true },
            sortBy: [SortDescriptor(\Customer.name)]
        )
        let activeCustomers = (try? context.fetch(customerDescriptor)) ?? []

        if !activeCustomers.isEmpty, !events.isEmpty {
            let dominantActivity = events
                .filter { $0.appName == block.dominantApp }
                .max(by: { $0.duration < $1.duration })

            if let activity = dominantActivity {
                let customerVM = CustomerViewModel()
                if let matched = customerVM.matchCustomer(forActivity: activity, customers: activeCustomers) {
                    block.customer = matched
                }
            }
        }

        context.insert(block)
        try? context.save()

        return block
    }
}
