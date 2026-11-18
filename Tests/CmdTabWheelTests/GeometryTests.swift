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

    @Test(arguments: [1, 2, 3, 8, 13, 30, 80])
    func keysSitOnTheGlassEdgeCenteredOnTheirSector(count: Int) {
        let layout = WheelLayout.standard
        for index in 0..<count {
            let axis = WheelGeometry.angle(of: index, count: count)
            let close = layout.closeButtonCenter(index: index, count: count)
            let star = layout.railButtonCenter(slot: 1, index: index, count: count)
            for key in [close, star] {
                #expect(abs(hypot(key.x, key.y) - layout.railRadius) < 0.001)
                #expect(hypot(key.x, key.y) + WheelLayout.railKeySize / 2 + 8 < layout.canvasSize / 2)
            }
            let middle = atan2((close.y + star.y) / 2, (close.x + star.x) / 2)
            #expect(abs(atan2(sin(middle - axis), cos(middle - axis))) < 0.000_1)
            #expect(hypot(star.x - close.x, star.y - close.y) > WheelLayout.railKeySize)
            // × comes first in reading order: left of ★, or above it where the rim runs up and down.
            #expect((star.x - close.x) + (star.y - close.y) > -0.001)
        }
    }

    /// Whatever icons carry (both corner marks, the widest row of window dots), at any angle,
    /// stays clear of the selected sector's keys: the biggest icons end before the lane,
    /// smaller ones come out toward the rim only as far as that holds.
    @Test(arguments: Array(1...80)) @MainActor
    func noMarkOrWindowDotsReachTheKeys(count: Int) {
        let layout = WheelLayout.standard
        let size = layout.iconSize(count: count), half = size / 2
        let radius = layout.iconRadius(iconSize: size)
        #expect(radius >= layout.bandRadius && radius + half < layout.railRadius)
        let mark = WheelLayout.markSize(iconSize: size)
        let overhang = WheelLayout.markOverhang(iconSize: size)
        let dots = (1...30).map { WindowPositionIndicator.width(count: $0, maxWidth: size) }.max()!
        // The marks' plates are rounded like this.
        let carried: [(rect: CGRect, corner: CGFloat)] = [
            (CGRect(x: half + overhang - mark, y: -half - overhang, width: mark, height: mark), mark * 0.26),
            (CGRect(x: -half - overhang, y: -half - overhang, width: mark, height: mark), mark * 0.26),
            (CGRect(x: -dots / 2, y: half + WheelLayout.windowDotsGap, width: dots, height: 3), 0),
        ]
        for selected in 0..<count {
            // Half the glyph and a point or two of glass; × is the smaller glyph.
            let keys: [(center: CGPoint, clearance: CGFloat)] = [
                (layout.closeButtonCenter(index: selected, count: count), 6.5),
                (layout.railButtonCenter(slot: 1, index: selected, count: count), 8),
            ]
            var closest = CGFloat.infinity
            for index in 0..<count {
                let angle = WheelGeometry.angle(of: index, count: count)
                let icon = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                let scale = index == selected ? WheelLayout.selectedIconScale : 1
                for (rect, corner) in carried {
                    let core = CGRect(x: icon.x + rect.minX * scale, y: icon.y + rect.minY * scale,
                                      width: rect.width * scale, height: rect.height * scale)
                        .insetBy(dx: corner * scale, dy: corner * scale)
                    for (key, clearance) in keys {
                        let dx = max(core.minX - key.x, 0, key.x - core.maxX)
                        let dy = max(core.minY - key.y, 0, key.y - core.maxY)
                        closest = min(closest, hypot(dx, dy) - corner * scale - clearance)
                    }
                }
            }
            #expect(closest >= 0)
        }
    }

    @Test(arguments: [1, 3, 8, 30, 80])
    func theWayFromTheIconToEitherKeyKeepsItsSector(count: Int) {
        let layout = WheelLayout.standard
        let size = layout.iconSize(count: count), radius = layout.iconRadius(iconSize: size)
        for index in 0..<count {
            let angle = WheelGeometry.angle(of: index, count: count)
            let icon = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            let keys = [layout.closeButtonCenter(index: index, count: count),
                        layout.railButtonCenter(slot: 1, index: index, count: count)]
            for key in keys {
                for step in 0...20 {
                    let t = Double(step) / 20
                    let point = CGPoint(x: icon.x + t * (key.x - icon.x), y: icon.y + t * (key.y - icon.y))
                    #expect(layout.actionRailContains(point, index: index, count: count, iconSize: size))
                }
            }
            #expect(!layout.actionRailContains(CGPoint(x: -keys[0].x, y: -keys[0].y), index: index, count: count,
                                                iconSize: size))
        }
    }
}
