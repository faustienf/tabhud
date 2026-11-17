import CoreGraphics
import Testing
@testable import CmdTabWheel

/// Slots around the wheel: SwiftUI coordinates (y down), slot 0 at 12 o'clock, then clockwise.
struct GeometryTests {
    @Test func slotZeroIsAtTwelveOClock() {
        #expect(WheelGeometry.index(at: -.pi / 2, count: 4) == 0)
    }

    @Test func slotsGoClockwise() {
        // With y pointing down, angle 0 is 3 o'clock and π/2 is 6 o'clock.
        #expect(WheelGeometry.index(at: 0, count: 4) == 1)
        #expect(WheelGeometry.index(at: .pi / 2, count: 4) == 2)
        #expect(WheelGeometry.index(at: .pi, count: 4) == 3)
    }

    @Test(arguments: 1...12)
    func everySlotsMiddlePointsBackAtIt(count: Int) {
        for index in 0..<count {
            #expect(WheelGeometry.index(at: WheelGeometry.angle(of: index, count: count), count: count) == index)
        }
    }

    @Test func aSlotReachesHalfwayToItsNeighbours() {
        let half = WheelGeometry.sectorAngle(count: 6) / 2
        let top = WheelGeometry.angle(of: 0, count: 6)
        #expect(WheelGeometry.index(at: top + half * 0.99, count: 6) == 0)
        #expect(WheelGeometry.index(at: top - half * 0.99, count: 6) == 0)
        #expect(WheelGeometry.index(at: top + half * 1.01, count: 6) == 1)
        #expect(WheelGeometry.index(at: top - half * 1.01, count: 6) == 5)
    }

    @Test func iconsShrinkWhenCrowdedButNeverGrowPastSixty() {
        let layout = WheelLayout.standard
        #expect(layout.iconSize(count: 0) == 0)
        #expect(layout.iconSize(count: 3) == 60)
        #expect(layout.iconSize(count: 30) < layout.iconSize(count: 10))
    }

    @Test(arguments: [3, 8, 13])
    func theCloseButtonSitsOnTheRailAndIsPartOfIt(count: Int) {
        let layout = WheelLayout.standard
        for index in 0..<count {
            let center = layout.closeButtonCenter(index: index, count: count)
            #expect(abs(hypot(center.x, center.y) - layout.actionRailRadius) < 0.001)
            #expect(layout.actionRailContains(center, index: index, count: count))
            // The opposite side of the wheel is not.
            #expect(!layout.actionRailContains(CGPoint(x: -center.x, y: -center.y), index: index, count: count))
        }
    }

    @Test(arguments: [3, 8, 13])
    func theStarSitsPastTheCloseButtonOnALongerRail(count: Int) {
        let layout = WheelLayout.standard
        for index in 0..<count {
            let close = layout.closeButtonCenter(index: index, count: count)
            let star = layout.railButtonCenter(slot: 1, index: index, count: count)
            #expect(abs(hypot(star.x, star.y) - layout.actionRailRadius) < 0.001)
            #expect(hypot(star.x - close.x, star.y - close.y) > WheelLayout.closeButtonSize)
            #expect(layout.actionRailContains(star, index: index, count: count, buttons: 2))
            // Away from the icon on the same side as the close button.
            let icon = WheelGeometry.angle(of: index, count: count)
            let sideOf = { (point: CGPoint) in sin(atan2(point.y, point.x) - icon) }
            #expect(abs(sideOf(star)) > abs(sideOf(close)))
            #expect(sideOf(star).sign == sideOf(close).sign)
        }
    }

    @Test(arguments: [1, 2, 3, 8, 13, 30], [0, 1, 2])
    func theWholeRailIsCenteredOnItsIcon(count: Int, buttons: Int) {
        let layout = WheelLayout.standard
        for index in 0..<count {
            let span = layout.actionRailSpan(index: index, count: count, buttons: buttons)
            #expect(abs(span.start + span.end) < 0.000_001)
            let selection = layout.railSelectionSpan(index: index, count: count, buttons: buttons)
            #expect(selection.start > span.start && selection.end < span.end)
            for slot in 0..<buttons {
                let center = layout.railButtonCenter(slot: slot, index: index, count: count, buttons: buttons)
                #expect(layout.actionRailContains(center, index: index, count: count, buttons: buttons))
                let angle = atan2(center.y, center.x) - WheelGeometry.angle(of: index, count: count)
                let offset = atan2(sin(angle), cos(angle))
                #expect(offset > span.start && offset < span.end)
            }
        }
    }
}
