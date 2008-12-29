// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OAPasteboardHelper.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>
#import <AppKit/NSPasteboard.h>

@interface OAPasteboardHelper : OFObject
{
    NSMutableDictionary *typeToOwner;
    unsigned int responsible;
    NSPasteboard *pasteboard;
}

+ (OAPasteboardHelper *) helperWithPasteboard:(NSPasteboard *)newPasteboard;
+ (OAPasteboardHelper *) helperWithPasteboardNamed:(NSString *)pasteboardName;
- initWithPasteboard:(NSPasteboard *)newPasteboard;
- initWithPasteboardNamed:(NSString *)pasteboardName;

- (NSPasteboard *) pasteboard;

- (void)declareTypes:(NSArray *)someTypes owner:(id)anOwner;
- (void)addTypes:(NSArray *)someTypes owner:(id)anOwner;

- (void)absolvePasteboardResponsibility;

@end
