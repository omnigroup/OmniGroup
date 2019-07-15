// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#import <OmniAppKit/OmniAppKit.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/rcsid.h>
#import <XCTest/XCTest.h>

// NSTextStorage does NOT reset the length of its editedRange in processEditing. Only the location gets reset to NSNotFound.
#define OAAssertNoPendingTextStorageEdits(ts) do { \
    XCTAssertEqual([ts editedMask], 0UL); \
    XCTAssertEqual([ts changeInLength], 0L); \
    NSRange editedRange = [ts editedRange]; \
    XCTAssertEqual(editedRange.location, (NSUInteger)NSNotFound); \
} while(0)
