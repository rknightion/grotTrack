import SwiftUI
import SwiftData

@Observable
@MainActor
final class CustomerViewModel {
    func addCustomer(name: String, keywords: [String], color: String, context: ModelContext) {
        let customer = Customer(name: name, keywords: keywords, color: color)
        context.insert(customer)
    }

    func updateCustomer(_ customer: Customer, name: String, keywords: [String], color: String) {
        customer.name = name
        customer.keywords = keywords
        customer.color = color
    }

    func deleteCustomer(_ customer: Customer, context: ModelContext) {
        context.delete(customer)
    }

    func matchCustomer(forActivity activity: ActivityEvent, customers: [Customer]) -> Customer? {
        let searchTexts = [
            activity.windowTitle.lowercased(),
            (activity.browserTabTitle ?? "").lowercased(),
            activity.appName.lowercased()
        ]

        for customer in customers where customer.isActive {
            for keyword in customer.keywords {
                let lowerKeyword = keyword.lowercased()
                if lowerKeyword.isEmpty { continue }
                for text in searchTexts where text.contains(lowerKeyword) {
                    return customer
                }
            }
        }
        return nil
    }

    func importCustomersFromSeeding(names: [String], context: ModelContext) {
        let defaultColors = ["blue", "green", "purple", "orange", "teal",
                             "pink", "indigo", "mint", "brown", "cyan"]
        for (index, name) in names.enumerated() {
            let color = defaultColors[index % defaultColors.count]
            let customer = Customer(name: name, keywords: [name.lowercased()], color: color)
            context.insert(customer)
        }
    }
}
