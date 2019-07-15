// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSRegularExpression.h>
#import <OmniBase/macros.h>

@class OFRegularExpressionMatch;
@class OFStringScanner;

@interface NSRegularExpression (OFExtensions)

- (OFRegularExpressionMatch *)of_firstMatchInString:(NSString *)string;
- (OFRegularExpressionMatch *)of_firstMatchInString:(NSString *)string range:(NSRange)range;
- (BOOL)hasMatchInString:(NSString *)string;
- (NSTextCheckingResult *)exactMatchInString:(NSString *)string;

- (OFRegularExpressionMatch *)matchInScanner:(OFStringScanner *)stringScanner;
- (OFRegularExpressionMatch *)matchInScanner:(OFStringScanner *)stringScanner advanceScanner:(BOOL)advanceScanner;

@end

// NOTE: If NSRegularExpressionAnchorsMatchLines is not specified, ^ and $ do work, but only match the beginning and end of the string, not lines w/in the string. So /^a/ will match once vs "a\na" and twice if NSRegularExpressionAnchorsMatchLines is used.
#define OFCreateRegularExpressionWithOptions(name, pattern, _options) \
    static NSRegularExpression *name = nil; \
    do { \
        static dispatch_once_t onceToken; \
        dispatch_once(&onceToken, ^{ \
            OB_AUTORELEASING NSError *expressionError = nil; \
            name = [[NSRegularExpression alloc] initWithPattern:pattern options:_options error:&expressionError]; \
            if (!name) { \
                NSLog(@"Error creating regular expression '%@' from pattern: %@ --> %@", @#name, pattern, [expressionError toPropertyList]); \
            } \
        }); \
    } while(0)

#define OFCreateRegularExpression(name, pattern) OFCreateRegularExpressionWithOptions(name, pattern, NSRegularExpressionAnchorsMatchLines)
