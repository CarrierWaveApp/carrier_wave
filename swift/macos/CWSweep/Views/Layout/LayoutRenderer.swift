import SwiftUI

// MARK: - LayoutRenderer

/// Recursively renders a LayoutNode tree into nested HSplitView/VSplitView.
/// Returns AnyView to break infinite type recursion in the SIL generator —
/// without this, `computeLoweredRValueType` loops on the recursive view tree.
struct LayoutRenderer: View {
    // MARK: Internal

    let node: LayoutNode
    let context: PanelContext

    var body: some View {
        content
    }

    // MARK: Private

    private var content: AnyView {
        switch node {
        case let .split(splitNode):
            AnyView(SplitRenderer(splitNode: splitNode, context: context))
        case let .panel(panelId):
            AnyView(
                PanelRegistry.view(for: panelId, context: context)
                    .vimPaneFocus(panelId)
            )
        }
    }
}

// MARK: - SplitRenderer

/// Renders a SplitNode as an HSplitView or VSplitView with two children.
private struct SplitRenderer: View {
    // MARK: Internal

    let splitNode: SplitNode
    let context: PanelContext

    var body: some View {
        if let fixed = splitNode.firstFixedSize {
            fixedSplitBody(fixed: fixed)
        } else {
            resizableSplitBody
        }
    }

    // MARK: Private

    private var resizableSplitBody: some View {
        GeometryReader { geo in
            switch splitNode.direction {
            case .horizontal:
                HSplitView {
                    LayoutRenderer(node: splitNode.first, context: context)
                        .frame(
                            minWidth: 140,
                            idealWidth: max(140, geo.size.width * splitNode.ratio)
                        )
                    LayoutRenderer(node: splitNode.second, context: context)
                        .frame(minWidth: 140)
                }
            case .vertical:
                VSplitView {
                    LayoutRenderer(node: splitNode.first, context: context)
                        .frame(
                            minHeight: 120,
                            idealHeight: max(120, geo.size.height * splitNode.ratio)
                        )
                    LayoutRenderer(node: splitNode.second, context: context)
                        .frame(minHeight: 120)
                }
            }
        }
    }

    @ViewBuilder
    private func fixedSplitBody(fixed: CGFloat) -> some View {
        switch splitNode.direction {
        case .horizontal:
            HStack(spacing: 0) {
                LayoutRenderer(node: splitNode.first, context: context)
                    .frame(width: fixed)
                Divider()
                LayoutRenderer(node: splitNode.second, context: context)
                    .frame(maxWidth: .infinity)
            }
        case .vertical:
            VStack(spacing: 0) {
                LayoutRenderer(node: splitNode.first, context: context)
                    .frame(height: fixed)
                Divider()
                LayoutRenderer(node: splitNode.second, context: context)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}
