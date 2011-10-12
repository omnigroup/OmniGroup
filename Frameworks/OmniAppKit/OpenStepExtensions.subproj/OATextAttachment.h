// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniFoundation/OFObject.h>

@class NSFileWrapper;
@protocol OATextAttachmentCell;

@interface OATextAttachment : OFObject
{
@private
    NSFileWrapper *_fileWrapper;
    id <OATextAttachmentCell> _cell;
}

- initWithFileWrapper:(NSFileWrapper *)fileWrapper;

@property(nonatomic,retain) NSFileWrapper *fileWrapper;
@property(nonatomic,retain) id <OATextAttachmentCell> attachmentCell;

@end

#else

#import <AppKit/NSTextAttachment.h>
#define OATextAttachment NSTextAttachment

#endif
