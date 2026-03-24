import SwiftUI
import SwiftData

struct CustomerListView: View {
    let llmProvider: any LLMProvider

    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var viewModel = CustomerViewModel()
    @State private var showingAddCustomer = false
    @State private var selectedCustomer: Customer?
    @State private var showingSeeding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(customers) { customer in
                    CustomerRow(customer: customer)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCustomer = customer
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.deleteCustomer(customers[index], context: context)
                    }
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCustomer = true
                    } label: {
                        Label("Add Customer", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Import from PM Tool") {
                        showingSeeding = true
                    }
                }
            }
            .sheet(isPresented: $showingAddCustomer) {
                CustomerEditView(mode: .add) { name, keywords, color in
                    viewModel.addCustomer(name: name, keywords: keywords, color: color, context: context)
                }
            }
            .sheet(item: $selectedCustomer) { customer in
                CustomerEditView(mode: .edit(customer)) { name, keywords, color in
                    viewModel.updateCustomer(customer, name: name, keywords: keywords, color: color)
                }
            }
            .sheet(isPresented: $showingSeeding) {
                SeedingView(llmProvider: llmProvider)
            }
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView(
                        "No Customers",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add customers to start tracking time by project.")
                    )
                }
            }
        }
    }
}

private struct CustomerRow: View {
    @Bindable var customer: Customer

    var body: some View {
        HStack {
            Circle()
                .fill(customer.swiftUIColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading) {
                Text(customer.name)
                    .font(.body)
                Text("\(customer.keywords.count) keyword\(customer.keywords.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $customer.isActive)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
