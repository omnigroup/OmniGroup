// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFFileWrapper.h> // For #define of OFFileWrapper, if needed

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniFoundation/OFObject.h>

@protocol OATextAttachmentCell;

@interface OATextAttachment : OFObject
{
@private
    OFFileWrapper *_fileWrapper;
    id <OATextAttachmentCell> _cell;
}

- initWithFileWrapper:(OFFileWrapper *)fileWrapper;

@property(nonatomic,retain) OFFileWrapper *fileWrapper;
@property(nonatomic,retain) id <OATextAttachmentCell> cell;

@end

#else

#import <AppKit/NSTextAttachment.h>
#define OATextAttachment NSTextAttachment

#endif
