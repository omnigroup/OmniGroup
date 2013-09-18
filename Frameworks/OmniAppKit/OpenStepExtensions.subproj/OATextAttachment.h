// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// 14207119: TextKit: NSTextAttachment.h is not usable as a standalone import
@class NSData;
#import <UIKit/NSAttributedString.h>

#import <UIKit/NSTextAttachment.h>

// TextKit's NSTextAttachment only supports flat-files (14181271: TextKit: NSTextAttachment needs file wrapper support).
// It also removes the notion of a cell which we might want to keep for now at least.
@class NSFileWrapper;
@protocol OATextAttachmentCell;

@interface OATextAttachment : NSTextAttachment

- initWithFileWrapper:(NSFileWrapper *)fileWrapper;

@property(nonatomic,retain) NSFileWrapper *fileWrapper;
@property(nonatomic,retain) id <OATextAttachmentCell> attachmentCell;

@end

#else

#import <AppKit/NSTextAttachment.h>
#define OATextAttachment NSTextAttachment

#endif
