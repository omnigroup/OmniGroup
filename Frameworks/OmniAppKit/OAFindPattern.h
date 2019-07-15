// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSRange.h>

@class NSString;

@protocol OAFindPattern <NSObject>
- (BOOL)findInString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;
- (BOOL)findInRange:(NSRange)range ofString:(NSString *)aString foundRange:(NSRangePointer)rangePtr;

- (void)setReplacementString:(NSString *)aString;
- (NSString *)replacementStringForLastFind;

// Allow the caller to inspect the contents of the find pattern (very helpful when they cannot efficiently reduce their target content to a string)
- (NSString *)findPattern;
- (BOOL)isCaseSensitive;
- (BOOL)isBackwards;
- (BOOL)isRegularExpression;
@end

@interface OAFindPattern : NSObject <OAFindPattern>
{
@private
    NSString *pattern;
    unsigned int optionsMask;
    BOOL wholeWord;
    NSString *replacementString;
}

- (instancetype)initWithString:(NSString *)aString ignoreCase:(BOOL)ignoreCase wholeWord:(BOOL)isWholeWord backwards:(BOOL)backwards;

@end
