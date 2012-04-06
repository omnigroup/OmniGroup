// Copyright 2006, 2008, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSLayoutManager.h>

@class NSTextAttachment;

@interface NSLayoutManager (OAExtensions)

- (NSTextContainer *)textContainerForCharacterIndex:(NSUInteger)characterIndex;

- (NSRect)attachmentFrameAtGlyphIndex:(NSUInteger)glyphIndex; // in the text view's coordinate system
- (NSRect)attachmentFrameAtCharacterIndex:(NSUInteger)charIndex; // in the text view's coordinate system
- (NSRect)attachmentRectForAttachmentAtCharacterIndex:(NSUInteger)characterIndex inFrame:(NSRect)layoutFrame; // in the same coordinate system as layoutFrame, assuming no scaling

- (NSTextAttachment *)attachmentAtPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;

- (CGFloat)totalHeightUsed;
- (CGFloat)widthOfLongestLine;

@end

