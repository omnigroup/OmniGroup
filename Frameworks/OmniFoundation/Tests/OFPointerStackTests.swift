// Copyright 2019-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import XCTest

// The @testable imports only work in debug builds
#if DEBUG

@testable import OmniFoundation

class OFPointerStackCase : XCTestCase {
    var stack: OFPointerStack<NSObject>!
    var mockData: [NSObject]!
    
    var one: NSObject? = NSObject()
    var two: NSObject? = NSObject()
    var three: NSObject? = NSObject()
    var four: NSObject? = NSObject()
    var five: NSObject? = NSObject()
    
    // Stack should read ["1", "2", "3", "4", "5"] after setup
    override func setUp() {
        autoreleasepool {
            one = NSObject()
            two = NSObject()
            three = NSObject()
            four = NSObject()
            five = NSObject()
            
            mockData = [one!, two!, three!, four!, five!]
            stack = OFPointerStack()
        }
        
        stack.push(five!)
        stack.push(four!)
        stack.push(three!)
        stack.push(two!)
        stack.push(one!)
    }
    
    func testUniquing() {
        stack.push(five!, uniquing: true)
        XCTAssert(stack.peek(afterCompacting: false) == five && stack.count == 5)
    }
    
    func testCompactionConditions() {
        stack.addAdditionalCompactionCondition {[weak self] (object) -> Bool in
            return object == self?.four || object == self?.five
        }
        
        XCTAssert(stack.count == 2 && stack.allObjects[0] == four && stack.allObjects[1] == five)
    }
    
    func testPop() {
        XCTAssert(stack.pop(afterCompacting: true)! == one)
        XCTAssert(stack.pop(afterCompacting: true)! == two)
        XCTAssert(stack.pop(afterCompacting: true)! == three)
        XCTAssert(stack.pop(afterCompacting: true)! == four)
        XCTAssert(stack.pop(afterCompacting: true)! == five)
    }
    
    func testFiltration() {
        XCTAssert(stack.firstElementSatisfyingCondition({ $0 == self.two })! == two)
        let twoAndThree = stack.allElementsSatisfyingCondition({ $0 == self.two || $0 == self.three })
        XCTAssert(twoAndThree[0] == two && twoAndThree[1] == three)
    }
    
    func testRemove() {
        stack.remove(three!)
        XCTAssert(!stack.contains(three!))
    }
    
    func testWeakHolding() {
        // This test needs careful memory management, so it does not use the pre-set data from setup(). The objects allocated in setup() are persisted too long in an autoreleasepool. We define our own here, and everything works ok.
        autoreleasepool {
            var one: NSObject? = NSObject()
            var two: NSObject? = NSObject()
            var three: NSObject? = NSObject()
            var four: NSObject? = NSObject()
            var five: NSObject? = NSObject()
            
            stack = OFPointerStack()
            
            stack.push(five!)
            stack.push(four!)
            stack.push(three!)
            stack.push(two!)
            stack.push(one!)
            
            one = nil
            two = nil
            three = nil
            four = nil
            five = nil
        }
        
        // Objects are deallocated at the autoreleasepool above, and so the stack should be empty
        XCTAssert(stack.count == 0)
    }
}

#endif

