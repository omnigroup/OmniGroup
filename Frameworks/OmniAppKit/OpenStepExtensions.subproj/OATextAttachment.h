// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

@class NSData, NSFileWrapper;

#if OMNI_BUILDING_FOR_IOS
// 14207119: TextKit: NSTextAttachment.h is not usable as a standalone import
#import <UIKit/NSAttributedString.h>
#import <UIKit/NSTextAttachment.h>
#endif

#if OMNI_BUILDING_FOR_IOS || OMNI_BUILDING_FOR_SERVER

#if OMNI_BUILDING_FOR_SERVER
#import <OmniFoundation/OFObject.h>
#define _OATextAttachmentSuperclass OFObject
#else
#define _OATextAttachmentSuperclass NSTextAttachment
#endif

// TextKit's NSTextAttachment only supports flat-files (14181271: TextKit: NSTextAttachment needs file wrapper support).

#if OMNI_BUILDING_FOR_IOS
// It also removes the notion of a cell which we might want to keep for now at least.
@protocol OATextAttachmentCell;
#endif

@interface OATextAttachment : _OATextAttachmentSuperclass

- initWithFileWrapper:(NSFileWrapper *)fileWrapper;

@property(nonatomic,retain) NSFileWrapper *fileWrapper;

#if OMNI_BUILDING_FOR_IOS
@property(nonatomic,retain) id <OATextAttachmentCell> attachmentCell;
#endif

@end
#endif

#if OMNI_BUILDING_FOR_MAC
#import <AppKit/NSTextAttachment.h>
#define OATextAttachment NSTextAttachment
#endif
