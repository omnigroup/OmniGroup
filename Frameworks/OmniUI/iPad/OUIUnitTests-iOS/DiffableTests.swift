// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import XCTest
@testable import OmniUI

private struct IDWithPayload: DifferenceComparable {
    let id: String
    let payload: Int
    
    init(_ id: String, _ payload: Int) {
        self.id = id
        self.payload = payload
    }
    
    var differenceIdentifier: String {
        return id
    }
    
    func diff(from preState: IDWithPayload) -> ElementDifference {
        guard id == preState.id else { return .incomparable }
        if payload == preState.payload {
            return .unchanged
        }
        return .needsUpdate
    }
}

private struct TestDiffable: Diffable {
    let values: [(IDWithPayload, [IDWithPayload])]
    
    var sections: [IDWithPayload] {
        return values.map { $0.0 }
    }
    
    func items(in section: Int) -> [IDWithPayload] {
        return values[section].1
    }
}

class DiffableTests: XCTestCase {
    
    // MARK: Section Tests
    
    func testUnchangedSections() {
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            (IDWithPayload("B", 0), []),
            ])
        let difference = after.difference(from: after)
        XCTAssert(difference.changeKind == .noChange)
    }
    
    func testSectionsUpdated() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            (IDWithPayload("B", 0), []),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 1), []),
            (IDWithPayload("B", 0), []),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.insertions.isEmpty)
        XCTAssert(difference.sectionChanges.deletions.isEmpty)
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        XCTAssert(difference.sectionChanges.updates.count == 1)
        if let first = difference.sectionChanges.updates.first {
            XCTAssert(first == (0, 0))
        }
    }
    
    func testSectionsMoved() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            (IDWithPayload("B", 0), []),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("B", 0), []),
            (IDWithPayload("A", 0), []),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.insertions.isEmpty)
        XCTAssert(difference.sectionChanges.deletions.isEmpty)
        XCTAssert(difference.sectionChanges.updates.isEmpty)
        
        XCTAssertEqual(difference.sectionChanges.moves.count, 1)
        for (actualPair, expectedPair) in zip(difference.sectionChanges.moves, [(1, 0)]) {
            XCTAssert(actualPair.0 == expectedPair.0)
            XCTAssert(actualPair.1 == expectedPair.1)
        }
    }

    func testSectionsMoved2() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            (IDWithPayload("B", 0), []),
            (IDWithPayload("C", 0), []),
            (IDWithPayload("D", 0), []),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("B", 0), []),
            (IDWithPayload("C", 0), []),
            (IDWithPayload("D", 0), []),
            (IDWithPayload("A", 0), []),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.insertions.isEmpty)
        XCTAssert(difference.sectionChanges.deletions.isEmpty)
        XCTAssert(difference.sectionChanges.updates.isEmpty)
        
        XCTAssertEqual(difference.sectionChanges.moves.count, 1)
        for (actualPair, expectedPair) in zip(difference.sectionChanges.moves, [(0, 3)]) {
            XCTAssert(actualPair.0 == expectedPair.0)
            XCTAssert(actualPair.1 == expectedPair.1)
        }
    }
    
    func testSectionsInserted() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("B", 0), []),
            (IDWithPayload("A", 0), []),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.deletions.isEmpty)
        XCTAssert(difference.sectionChanges.updates.isEmpty)
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        
        XCTAssert(difference.sectionChanges.insertions == [0])
    }
    
    func testSectionsInserted2() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("B", 0), []),
            (IDWithPayload("A", 0), []),
            (IDWithPayload("C", 0), []),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.deletions.isEmpty)
        XCTAssert(difference.sectionChanges.updates.isEmpty)
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        XCTAssert(difference.sectionChanges.insertions == [0,2])
    }
    
    func testSectionsDeleted() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            (IDWithPayload("B", 0), []),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), []),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.insertions.isEmpty)
        XCTAssert(difference.sectionChanges.updates.isEmpty)
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        
        XCTAssert(difference.sectionChanges.deletions == [1])
    }
    
    func testReplaceSection() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Y", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("B", 0), [
                IDWithPayload("Y", 0),
                IDWithPayload("X", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.itemChanges.isEmpty) // should ignore item changes inside changing sections
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.updates.isEmpty)
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        
        XCTAssert(difference.sectionChanges.deletions == [0])
        XCTAssert(difference.sectionChanges.insertions == [0])
    }
    
    // MARK: Multiple Selection Tests
    
    func testGroupToNewSection() {
        let before = TestDiffable(values: [
            (IDWithPayload("X", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("Y", 0), [
                IDWithPayload("C", 0),
                IDWithPayload("D", 0),
                IDWithPayload("E", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("Z", 0), [
                IDWithPayload("X", 1),
                IDWithPayload("A", 1),
                IDWithPayload("B", 1),
                IDWithPayload("C", 0),
                IDWithPayload("E", 0),
                ]),
            (IDWithPayload("Y", 1), [
                IDWithPayload("D", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(!difference.sectionChanges.isEmpty)
        if let sectionUpdate = difference.sectionChanges.updates.first {
            XCTAssert(sectionUpdate.0 == 1)
            XCTAssert(sectionUpdate.1 == 1)
        } else {
            XCTFail("missing section update")
        }
        
        XCTAssert(difference.sectionChanges.deletions == [0])
        XCTAssert(difference.sectionChanges.insertions == [0])
        
        XCTAssert(!difference.itemChanges.isEmpty)
        let expected: Set<IndexPath> = [IndexPath(row: 0, section: 1), IndexPath(row: 2, section: 1)]
        XCTAssertEqual(difference.itemChanges.deletions, expected)
    }
    
    func testGroupToNewAction() {
        let before = TestDiffable(values: [
            (IDWithPayload("X", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                IDWithPayload("C", 0),
                IDWithPayload("D", 0),
                IDWithPayload("E", 0),
                IDWithPayload("F", 0),
                ]),
            (IDWithPayload("Y", 0), [
                IDWithPayload("G", 0),
                IDWithPayload("H", 0),
                ]),
            (IDWithPayload("Z", 0), [
                IDWithPayload("I", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("X", 1), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                IDWithPayload("C", 0),
                IDWithPayload("D", 0),
                IDWithPayload("NEW", 0),
                IDWithPayload("E", 0),
                IDWithPayload("Y", 0),
                IDWithPayload("G", 0),
                IDWithPayload("H", 0),
                IDWithPayload("I", 0),
                IDWithPayload("F", 0),
                ]),
            (IDWithPayload("Z", 1), [
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(difference.sectionChanges.insertions.isEmpty)
        XCTAssertEqual(difference.sectionChanges.deletions, [1])
        XCTAssertEqual(difference.sectionChanges.updates.count, 2)
        XCTAssert(difference.sectionChanges.updates.contains(where: { pre, post in
            return pre == 0 && post == 0
        }))
        XCTAssert(difference.sectionChanges.updates.contains(where: { pre, post in
            return pre == 2 && post == 1
        }))

        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssertEqual(difference.itemChanges.insertions.count, 4)
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 4, section: 0)))
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 6, section: 0)))
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 7, section: 0)))
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 8, section: 0)))
        XCTAssertEqual(difference.itemChanges.moves.count, 2)
        XCTAssert(difference.itemChanges.moves.contains(where: { pre, post in
            return pre == IndexPath(row: 5, section: 0) && post == IndexPath(row: 10, section: 0)
        }))
        XCTAssert(difference.itemChanges.moves.contains(where: { pre, post in
            return pre == IndexPath(row: 0, section: 2) && post == IndexPath(row: 9, section: 0)
        }))
    }
    
    func testMultipleInserts() {
        let before = TestDiffable(values: [
            (IDWithPayload("W", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("Y", 1), [
                IDWithPayload("F", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("W", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("X", 0), [
                IDWithPayload("C", 0),
                IDWithPayload("D", 0),
                ]),
            (IDWithPayload("Y", 0), [
                IDWithPayload("E", 0),
                IDWithPayload("F", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssertEqual(difference.sectionChanges.insertions, [1])
        XCTAssertEqual(difference.sectionChanges.updates.count, 1)
        if let first = difference.sectionChanges.updates.first {
            XCTAssert(first == (1, 2))
        }
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        XCTAssert(difference.sectionChanges.deletions.isEmpty)
        
        XCTAssertEqual(difference.itemChanges.insertions, [IndexPath(row: 0, section: 2)])
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
    }
    
    func testMultipleDeletes() {
        let before = TestDiffable(values: [
            (IDWithPayload("W", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("X", 0), [
                IDWithPayload("C", 0),
                IDWithPayload("D", 0),
                ]),
            (IDWithPayload("Y", 0), [
                IDWithPayload("E", 0),
                IDWithPayload("F", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("W", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("Y", 1), [
                IDWithPayload("F", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.sectionChanges.insertions.isEmpty)
        XCTAssert(difference.sectionChanges.updates.count == 1)
        if let first = difference.sectionChanges.updates.first {
            XCTAssert(first == (2, 1))
        }
        XCTAssert(difference.sectionChanges.moves.isEmpty)
        XCTAssertEqual(difference.sectionChanges.deletions, [1])
        
        XCTAssert(difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        XCTAssertEqual(difference.itemChanges.deletions, [IndexPath(row: 0, section: 2)])
    }
    
    // MARK: Item Tests
    
    func testUnchangedItems() {
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("AA", 100),
                IDWithPayload("AB", 100),
                ]),
            ])
        let difference = after.difference(from: after)
        XCTAssert(difference.changeKind == .noChange)
    }
    
    func testUpdatedItems() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("AA", 100),
                IDWithPayload("AB", 100),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("AA", 101),
                IDWithPayload("AB", 100),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        XCTAssertEqual(difference.itemChanges.updates.count, 1)
        if let first = difference.itemChanges.updates.first {
            XCTAssert(first == (IndexPath(row: 0, section: 0), IndexPath(row: 0, section: 0)))
        } else {
            XCTFail("missing item update")
        }
    }

    func testInsertedItems() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("Y", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Z", 0),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("W", 0),
                IDWithPayload("Y", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        
        XCTAssert(!difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 1, section: 0)))
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 0, section: 1)))
    }
    
    func testInsertedItems2() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Q", 0),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("Y", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Z", 0),
                IDWithPayload("Q", 0),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("W", 0),
                IDWithPayload("Y", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        
        XCTAssert(!difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 1, section: 0)))
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 0, section: 1)))
    }
    
    func testInsertedItems3() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("W", 0),
                IDWithPayload("X", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("W", 0),
                IDWithPayload("Y", 0),
                IDWithPayload("Z", 0),
                IDWithPayload("X", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        
        XCTAssert(!difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 1, section: 0)))
        XCTAssert(difference.itemChanges.insertions.contains(IndexPath(row: 2, section: 0)))
    }
    
    func testItemDeletes() {
        let before = TestDiffable(values: [
            (IDWithPayload("W", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("X", 0), [
                IDWithPayload("C", 0),
                IDWithPayload("D", 0),
                ]),
            (IDWithPayload("Y", 0), [
                IDWithPayload("E", 0),
                IDWithPayload("F", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("W", 0), [
                IDWithPayload("A", 0),
                IDWithPayload("B", 0),
                ]),
            (IDWithPayload("X", 0), [
                ]),
            (IDWithPayload("Y", 0), [
                IDWithPayload("F", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.sectionChanges.isEmpty)
        
        XCTAssert(difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        XCTAssert(difference.itemChanges.moves.isEmpty)
        XCTAssertEqual(difference.itemChanges.deletions, [IndexPath(row: 0, section: 1), IndexPath(row: 1, section: 1), IndexPath(row: 0, section: 2)])
    }
    

    func testMovedItems() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 100),
                ]),
            (IDWithPayload("B", 0), [
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("X", 100),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        
        XCTAssert(difference.itemChanges.moves.count == 1)
        
    }

    func testMovedItems2() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Y", 0),
                IDWithPayload("Z", 0),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("Q", 0),
                IDWithPayload("R", 0),
                IDWithPayload("S", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Z", 0),
                IDWithPayload("S", 0),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("Y", 0),
                IDWithPayload("Q", 0),
                IDWithPayload("R", 0),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.insertions.isEmpty)
        XCTAssert(difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        
        XCTAssert(difference.itemChanges.moves.count == 2)
        XCTAssert(difference.itemChanges.moves.contains(where: { pre, post in
            return pre == IndexPath(row: 2, section: 1) && post == IndexPath(row: 2, section: 0)
        }))
        XCTAssert(difference.itemChanges.moves.contains(where: { pre, post in
            return pre == IndexPath(row: 1, section: 0) && post == IndexPath(row: 0, section: 1)
        }))
    }
    
    // MARK: Move Adjustment Tests
    
    func testSuppressSingleMoveSource() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Y", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("Y", 0),
                IDWithPayload("X", 0),
                ]),
            ])
        let difference = after.difference(from: before, suppressedMovePositions: (sources: [IndexPath(row: 0, section: 0)], destinations: []))
        
        XCTAssert(difference.itemChanges.moves.isEmpty)
        XCTAssertEqual([IndexPath(row: 1, section: 0)], difference.itemChanges.insertions)
        XCTAssertEqual([IndexPath(row: 0, section: 0)], difference.itemChanges.deletions)
    }
    
    func testSuppressSingleMoveDestination() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 0),
                IDWithPayload("Y", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("Y", 0),
                IDWithPayload("X", 0),
                ]),
            ])
        let difference = after.difference(from: before, suppressedMovePositions: (sources: [], destinations: [IndexPath(row: 1, section: 0)]))
        
        XCTAssert(difference.itemChanges.moves.isEmpty)
        XCTAssertEqual([IndexPath(row: 1, section: 0)], difference.itemChanges.insertions)
        XCTAssertEqual([IndexPath(row: 0, section: 0)], difference.itemChanges.deletions)
    }
    
    func testDeletingItemInMovingSection() {
        let before = TestDiffable(values: [
            (IDWithPayload("S1", 0), []),
            (IDWithPayload("S2", 0), [
                IDWithPayload("X", 0),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("S2", 0), []),
            (IDWithPayload("S1", 0), []),
            ])
        let difference = after.difference(from: before, suppressedMovePositions: (sources: [], destinations: [IndexPath(row: 0, section: 1)]))
        
        // [(Int, Int)] is not Equatable, so we have to break down the assertion here: there should be one section move; it should start at section index 1; and it should go to section index 0.
        XCTAssertEqual(1, difference.sectionChanges.moves.count)
        XCTAssertEqual(1, difference.sectionChanges.moves.first!.0)
        XCTAssertEqual(0, difference.sectionChanges.moves.first!.1)
        XCTAssertEqual([IndexPath(row: 0, section: 1)], difference.itemChanges.deletions)
    }

    // MARK: Regression Tests
    
    // bug:///145686 (iOS-OmniFocus Bug: If the Customize Editor button is the only "hidable" item, don't allow hiding it)
    func testCustomizeInspector() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 100),
                IDWithPayload("Y", 100),
                ]),
            ])
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 100),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("Y", 100),
                ]),
            ])
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
        XCTAssert(difference.itemChanges.insertions.isEmpty)
        XCTAssert(!difference.itemChanges.deletions.isEmpty)
        XCTAssert(difference.itemChanges.updates.isEmpty)
        
        XCTAssert(difference.itemChanges.deletions == [IndexPath(row: 1, section: 0)])
    }
    
    // <bug:///150991> (iOS-OmniFocus Crasher: Crash customizing inspector to leave no item hidden)
    func testRemoveLastInspectorRow() {
        let before = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 100),
                ]),
            (IDWithPayload("B", 0), [
                IDWithPayload("Y", 100),
                ]),
            (IDWithPayload("C", 0), [
                IDWithPayload("Z", 100),
                ]),
            ])
        
        let after = TestDiffable(values: [
            (IDWithPayload("A", 0), [
                IDWithPayload("X", 100),
                IDWithPayload("Z", 100),
                ]),
            ])
        
        let difference = after.difference(from: before)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
    }
    
    #if true
    func testBug154833() {
        let before: [(IDWithPayload, [IDWithPayload])] = [
            (IDWithPayload("gi6rw-1OBZ2", 0), [
                IDWithPayload("lOkgMGkmQon", 0),
                IDWithPayload("hQuZM7RSiKU", 0),
                IDWithPayload("clZGuofgS1E", 0),
                IDWithPayload("hEtgpoNP8mC", 0),
                IDWithPayload("dkE1k7wwkSJ", 0),
                ]),
            (IDWithPayload("jensHz38O4k", 0), [
                IDWithPayload("e541fR4fi-k", 0),
                ]),
            (IDWithPayload("kn_3Ie0UjA1", 0), [
                IDWithPayload("oWZS6Yb_fRQ", 0),
                IDWithPayload("kcbDGJySp6u", 0),
                IDWithPayload("id5o8Gi5_Rj", 0),
                IDWithPayload("o3CE0J9_h1R", 0),
                IDWithPayload("iIZS5WopEet", 0),
                IDWithPayload("kh2v0tBtUAX", 0),
                IDWithPayload("daWpe6pUOTs", 0),
                IDWithPayload("jGqiB2Spo3E", 0),
                IDWithPayload("khe3rx35NdP", 0),
                IDWithPayload("jKjz8KOMOpu", 0),
                IDWithPayload("nDS3M5UOXi6", 0),
                ]),
            (IDWithPayload("jxAC8dC4eoH", 0), [
                IDWithPayload("bkZ4ccQZODb", 0),
                ]),
            (IDWithPayload("jCMBlEA5IMD", 0), [
                IDWithPayload("fs5tM1PLwBz", 0),
                IDWithPayload("oWZ4TjP1eES", 0),
                IDWithPayload("nn9NBGQfB4p", 0),
                IDWithPayload("atI979GQbMr", 0),
                IDWithPayload("hzG1RmXeRI2", 0),
                IDWithPayload("hE1eE-bM1Tf", 0),
                IDWithPayload("f2EG0gFPIZr", 0),
                ]),
            (IDWithPayload("p_vBNxcuCjJ", 0), [
                IDWithPayload("eDgdL7VrXaC", 0),
                ]),
            (IDWithPayload("bJQeGjsSGmR", 0), [
                IDWithPayload("b_9Yar9X67J", 0),
                ]),
            (IDWithPayload("bLq5-2ZPLHc", 0), [
                IDWithPayload("pMY6Zx3waUO", 0),
                ]),
            (IDWithPayload("bAz8lEU9MgW", 0), [
                IDWithPayload("ojnSoz_JEe4", 0),
                IDWithPayload("bbofRd9Y5-n", 0),
                ]),
            (IDWithPayload("a7H-hl6wlrl", 0), [
                IDWithPayload("nqq86238dmn", 0),
                IDWithPayload("eL7qsxubKgh", 0),
                IDWithPayload("ilqEOH54FAS", 0),
                ]),
            (IDWithPayload("aY5pg_BPp_2", 0), [
                IDWithPayload("kLSivHijkmX", 0),
                ]),
            ]
        let after: [(IDWithPayload, [IDWithPayload])] = [
            (IDWithPayload("gi6rw-1OBZ2", 0), [
                IDWithPayload("hQuZM7RSiKU", 0),
                IDWithPayload("clZGuofgS1E", 0),
                IDWithPayload("hEtgpoNP8mC", 0),
                IDWithPayload("dkE1k7wwkSJ", 0),
                ]),
            (IDWithPayload("jCMBlEA5IMD", 0), [
                IDWithPayload("oWZ4TjP1eES", 0),
                IDWithPayload("atI979GQbMr", 0),
                IDWithPayload("f2EG0gFPIZr", 0),
                ]),
            (IDWithPayload("bJQeGjsSGmR", 0), [
                IDWithPayload("b_9Yar9X67J", 0),
                ]),
            (IDWithPayload("bLq5-2ZPLHc", 0), [
                IDWithPayload("pMY6Zx3waUO", 0),
                ]),
            ]
        
        let beforeDiff = TestDiffable(values: before)
        let afterDiff = TestDiffable(values: after)
        
        let difference = afterDiff.difference(from: beforeDiff)
        
        XCTAssert(difference.changeKind != .noChange)
        XCTAssert(!difference.sectionChanges.isEmpty)
        XCTAssert(!difference.itemChanges.isEmpty)
    }
    #endif
}
