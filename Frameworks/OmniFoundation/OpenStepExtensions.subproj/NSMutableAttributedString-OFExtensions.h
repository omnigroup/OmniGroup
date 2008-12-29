// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSMutableAttributedString-OFExtensions.h 66043 2005-07-25 21:17:05Z kc $

#import <Foundation/NSAttributedString.h>

typedef NSAttributedString *(*OFMutableAttributedStringMutator)(NSMutableAttributedString *source, NSDictionary *attributes, NSRange matchRange, NSRange effectiveAttributeRange, BOOL *isEditing, void *context);

@interface NSMutableAttributedString (OFExtensions)
- (void)appendString:(NSString *)string attributes:(NSDictionary *)attributes;
- (void)appendString:(NSString *)string;

- (BOOL)mutateRanges:(OFMutableAttributedStringMutator)mutator inRange:(NSRange)sourceRange matchingString:(NSString *)matchString context:(void *)context;
- (BOOL)mutateRanges:(OFMutableAttributedStringMutator)mutator matchingString:(NSString *)matchString context:(void *)context;
@end
