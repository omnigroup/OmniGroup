// Copyright 2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSLayoutManager-OAExtensions.h 98223 2008-03-04 21:07:09Z kc $

#import <AppKit/NSLayoutManager.h>

@class NSTextAttachment;

@interface NSLayoutManager (OAExtensions)

- (NSTextContainer *)textContainerForCharacterIndex:(unsigned int)characterIndex;

- (NSRect)attachmentFrameAtGlyphIndex:(unsigned int)glyphIndex;
- (NSRect)attachmentFrameAtCharacterIndex:(unsigned int)charIndex;
- (NSRect)attachmentRectForAttachmentAtCharacterIndex:(unsigned int)characterIndex inFrame:(NSRect)layoutFrame;

- (NSTextAttachment *)attachmentAtPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;

- (float)totalHeightUsed;
- (float)widthOfLongestLine;

@end

