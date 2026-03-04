import CarrierWaveData
import SwiftUI

// MARK: - TabConfigurationView

struct TabConfigurationView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                ForEach(tabBarTabs, id: \.self) { tab in
                    tabRow(tab, inTabBar: true)
                }
                .onMove(perform: moveTabBarTab)
            } header: {
                Text(isIPad ? "Sidebar" : "Tab Bar")
            } footer: {
                if isIPad {
                    Text("Drag to reorder. Tap to hide.")
                } else if tabBarTabs.count >= maxVisibleTabs {
                    Text(
                        "Maximum \(maxVisibleTabs) tabs. "
                            + "Drag to reorder."
                    )
                } else {
                    Text("Drag to reorder. Tap to move to More.")
                }
            }

            Section {
                if moreTabs.isEmpty {
                    Text("No hidden tabs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(moreTabs, id: \.self) { tab in
                        tabRow(tab, inTabBar: false)
                    }
                    .onMove(perform: moveMoreTab)
                }
            } header: {
                Text("Hidden")
            } footer: {
                if isIPad {
                    Text("Hidden tabs won't appear in the sidebar.")
                } else {
                    Text(
                        "These tabs are accessible from the More tab."
                    )
                }
            }

            Section {
                Button("Reset to Defaults") {
                    TabConfiguration.reset()
                    refreshTabs()
                    notifyChange()
                }
            }
        }
        .navigationTitle(isIPad ? "Sidebar" : "Tab Bar")
        .environment(\.editMode, .constant(.active))
        .onAppear {
            refreshTabs()
        }
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var tabBarTabs: [AppTab] = []
    @State private var moreTabs: [AppTab] = []

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    /// Maximum tabs visible in tab bar (excluding More).
    /// iPad has no limit since the sidebar can hold all tabs.
    private var maxVisibleTabs: Int {
        isIPad ? AppTab.configurableTabs.count : 4
    }

    private func tabRow(
        _ tab: AppTab, inTabBar: Bool
    ) -> some View {
        let canMoveToTabBar =
            !inTabBar && tabBarTabs.count < maxVisibleTabs

        return Button {
            toggleTab(tab, inTabBar: inTabBar)
        } label: {
            HStack {
                Image(systemName: tab.icon)
                    .foregroundStyle(
                        inTabBar || canMoveToTabBar
                            ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .foregroundStyle(
                            inTabBar || canMoveToTabBar
                                ? .primary : .secondary
                        )
                    Text(tab.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if inTabBar {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if canMoveToTabBar {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inTabBar && !canMoveToTabBar)
    }

    private func refreshTabs() {
        let order = TabConfiguration.tabOrder()
        let hidden = TabConfiguration.hiddenTabs()

        tabBarTabs = order.filter {
            $0 != .more && !hidden.contains($0)
        }
        moreTabs = order.filter {
            $0 != .more && hidden.contains($0)
        }
    }

    private func toggleTab(_ tab: AppTab, inTabBar: Bool) {
        var hidden = TabConfiguration.hiddenTabs()

        if inTabBar {
            hidden.insert(tab)
        } else {
            if tabBarTabs.count < maxVisibleTabs {
                hidden.remove(tab)
            }
        }

        TabConfiguration.saveHidden(hidden)
        refreshTabs()
        notifyChange()
    }

    private func moveTabBarTab(
        from source: IndexSet, to destination: Int
    ) {
        tabBarTabs.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    private func moveMoreTab(
        from source: IndexSet, to destination: Int
    ) {
        moreTabs.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    private func saveTabOrder() {
        let newOrder = tabBarTabs + moreTabs + [.more]
        TabConfiguration.saveOrder(newOrder)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(
            name: .tabConfigurationChanged, object: nil
        )
    }
}
