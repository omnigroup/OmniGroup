// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/NSLayoutManager.h>
#else
#import <AppKit/NSLayoutManager.h>
#endif

@class NSTextAttachment;

@interface NSLayoutManager (OAExtensions)

- (NSTextContainer *)textContainerForCharacterIndex:(NSUInteger)characterIndex;

- (CGRect)attachmentFrameAtGlyphIndex:(NSUInteger)glyphIndex; // in the text view's coordinate system
- (CGRect)attachmentFrameAtCharacterIndex:(NSUInteger)charIndex; // in the text view's coordinate system
- (CGRect)attachmentRectForAttachmentAtCharacterIndex:(NSUInteger)characterIndex inFrame:(CGRect)layoutFrame; // in the same coordinate system as layoutFrame, assuming no scaling

- (NSTextAttachment *)attachmentAtPoint:(CGPoint)point inTextContainer:(NSTextContainer *)container;

- (CGFloat)totalHeightUsed;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (CGFloat)heightForAttributes:(NSDictionary *)attributes;
#endif

- (CGFloat)widthOfLongestLine;

@end

