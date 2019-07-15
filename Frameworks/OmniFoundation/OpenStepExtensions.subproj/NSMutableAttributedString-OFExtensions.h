// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSAttributedString.h>

typedef NSAttributedString *(^OFMutableAttributedStringMutator)(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing);

@interface NSMutableAttributedString (OFExtensions)

- (void)appendString:(NSString *)string attributes:(NSDictionary *)attributes;
- (void)appendString:(NSString *)string;

- (BOOL)mutateRangesInRange:(NSRange)sourceRange matchingString:(NSString *)matchString with:(OFMutableAttributedStringMutator)mutator;
- (BOOL)mutateRangesMatchingString:(NSString *)matchString with:(OFMutableAttributedStringMutator)mutator;

- (BOOL)replaceString:(NSString *)searchString withString:(NSString *)replacementString inRange:(NSRange)searchRange;

@end
