import SwiftUI

/// Navigation sidebar organized by section
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(SidebarSection.allCases) { section in
                Section(section.displayName) {
                    ForEach(section.items) { item in
                        Label(item.displayName, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }
}
