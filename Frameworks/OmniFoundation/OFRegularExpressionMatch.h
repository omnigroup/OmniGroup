// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSTextCheckingResult;
@class OFStringScanner;

@interface OFRegularExpressionMatch : NSObject

- initWithTextCheckingResult:(NSTextCheckingResult *)textCheckingResult string:(NSString *)string;
- initWithTextCheckingResult:(NSTextCheckingResult *)textCheckingResult stringScanner:(OFStringScanner *)stringScanner;

@property(nonatomic,readonly) NSTextCheckingResult *textCheckingResult;
@property(nonatomic,readonly) NSRange matchRange; // Range of the full match
@property(nonatomic,readonly) NSString *matchString;

- (NSString *)captureGroupAtIndex:(NSUInteger)captureGroupIndex; // Zero is the first capture (not the full match).
- (NSRange)rangeOfCaptureGroupAtIndex:(NSUInteger)captureGroupIndex;

// Returns nil if there is another match in the string, or stringScanner. If the receiver is initialized with a string scanner, this will advance the scan location on success.
- (OFRegularExpressionMatch *)nextMatch;

@end
