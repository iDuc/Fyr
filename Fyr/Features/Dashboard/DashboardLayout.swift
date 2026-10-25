import SwiftUI

/// Places the fire (hero) and the controls for the screen the app gets.
///
/// - Phone, and the closed iPhone Duo (outer display): one column.
/// - Open iPhone Duo, flat: two panes split exactly at the fold, using the
///   `.division` reserved region (the fold), so nothing sits on the hinge.
/// - Partly folded iPhone Duo (tabletop/book): an `ArrangementView` keeps both
///   halves clear of the fold; the fire gets the half that faces you.
/// - iPad or another wide window: two panes side by side.
///
/// Decided by the space the view gets and the reserved regions, never by the
/// device model. With accessibility text sizes the two panes need more room.
struct DashboardLayout<Hero: View, Controls: View>: View {
    @ViewBuilder var hero: (_ isWide: Bool) -> Hero
    @ViewBuilder var controls: Controls

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Each pane needs at least this much width (or height, for a top/bottom split).
    static var minimumPaneLength: CGFloat { 300 }
    /// Without a fold, two side-by-side panes need this much width.
    static var minimumWideWidth: CGFloat { 700 }

    var body: some View {
        GeometryReader { proxy in
            switch Arrangement(proxy: proxy, sizeClass: sizeClass, typeSize: typeSize) {
            case .folded:
                foldedPanes
            case .splitAtFold(let division):
                splitPanes(at: division, size: proxy.size)
            case .sideBySide:
                HStack(spacing: 0) {
                    heroPane(isWide: true)
                    controlsPane
                }
            case .singleColumn:
                singleColumn
            }
        }
    }

    // MARK: - Arrangements

    enum Arrangement: Equatable {
        case singleColumn
        case sideBySide
        /// Flat open Duo: split at the division (fold) rectangle.
        case splitAtFold(CGRect)
        /// Partly folded Duo.
        case folded

        init(proxy: GeometryProxy, sizeClass: UserInterfaceSizeClass?, typeSize: DynamicTypeSize) {
            let size = proxy.size
            let division = proxy.reservedRegions(kind: .division, options: .includeInactive).first
            if let division, division.isActive {
                self = .folded
                return
            }
            let roomy = !typeSize.isAccessibilitySize
            if let division, roomy, Self.fits(division.frame, in: size) {
                self = .splitAtFold(division.frame)
                return
            }
            if roomy, sizeClass == .regular, size.width >= DashboardLayout.minimumWideWidth {
                self = .sideBySide
                return
            }
            self = .singleColumn
        }

        /// Whether both sides of the fold are large enough for a pane.
        static func fits(_ fold: CGRect, in size: CGSize) -> Bool {
            let minimum = DashboardLayout.minimumPaneLength
            if fold.height >= fold.width {
                return fold.minX >= minimum && size.width - fold.maxX >= minimum
            }
            return fold.minY >= minimum && size.height - fold.maxY >= minimum
        }
    }

    // MARK: - Panes

    private var singleColumn: some View {
        ScrollView {
            VStack(spacing: FyrDesign.Spacing.lg) {
                hero(false)
                controls
            }
            .padding(.horizontal, FyrDesign.Spacing.md)
            .padding(.bottom, FyrDesign.Spacing.xl)
            .frame(maxWidth: FyrDesign.Size.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func heroPane(isWide: Bool) -> some View {
        ScrollView {
            hero(isWide)
                .padding(FyrDesign.Spacing.lg)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("dashboard.heroPane")
    }

    private var controlsPane: some View {
        ScrollView {
            VStack(spacing: FyrDesign.Spacing.md) {
                controls
            }
            .padding(FyrDesign.Spacing.lg)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("dashboard.controlsPane")
    }

    private func splitPanes(at fold: CGRect, size: CGSize) -> some View {
        Group {
            if fold.height >= fold.width {
                // Book: fold runs top to bottom.
                HStack(spacing: 0) {
                    heroPane(isWide: true).frame(width: fold.minX)
                    Color.clear.frame(width: fold.width)
                    controlsPane.frame(width: max(0, size.width - fold.maxX))
                }
            } else {
                // Laptop: fold runs left to right; the fire on top.
                VStack(spacing: 0) {
                    heroPane(isWide: true).frame(height: fold.minY)
                    Color.clear.frame(height: fold.height)
                    controlsPane.frame(height: max(0, size.height - fold.maxY))
                }
            }
        }
    }

    private var foldedPanes: some View {
        ArrangementView {
            heroPane(isWide: true)
        } secondary: {
            controlsPane
        }
        .arrangementViewStyle(.split)
    }
}
