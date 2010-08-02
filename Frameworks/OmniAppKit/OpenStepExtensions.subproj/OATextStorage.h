// Copyright 2003-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>
#import <Foundation/NSAttributedString.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Define our extra ancillary symbols only on iOS.

@class NSNotification, NSUndoManager;

extern NSString * const OAAttachmentAttributeName;

enum {
    OAAttachmentCharacter = 0xfffc // There's a CoreText equivalent, actually
};

enum {
    OATextStorageEditedAttributes = 1,
    OATextStorageEditedCharacters = 2
};

extern NSString * const OATextStorageDidProcessEditingNotification;

@protocol OATextStorageDelegate <NSObject>
@optional

/* These methods are sent during processEditing:. The receiver can use the callback methods editedMask, editedRange, and changeInLength to see what has changed. Although these methods can change the contents of the text storage, it's best if only the delegate did this.
 */
- (void)textStorageWillProcessEditing:(NSNotification *)notification;	/* Delegate can change the characters or attributes */
- (void)textStorageDidProcessEditing:(NSNotification *)notification;	/* Delegate can change the attributes */

@end

// Methods normally on NSAttributedString via AppKit or OmniAppKit when on the Mac
@interface NSAttributedString (OAAppKitEmulation)
- (BOOL)containsAttachments;
- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;
@end

#define OATextStorage OATextStorage_

#else

// Map our symbols to the Mac version
#import <AppKit/NSTextStorage.h>
#define OATextStorage NSTextStorage
#define OATextStorageDelegate NSTextStorageDelegate
#define OATextStorageEditedAttributes NSTextStorageEditedAttributes
#define OATextStorageEditedCharacters NSTextStorageEditedCharacters 
#define OATextStorageDidProcessEditingNotification NSTextStorageDidProcessEditingNotification
#define OAAttachmentCharacter NSAttachmentCharacter
#define OAAttachmentAttributeName NSAttachmentAttributeName

#endif

// Make sure we can always say "OATextStorage_" as a real class name (for testing).
@interface OATextStorage_ : NSMutableAttributedString
{
@private
    id <OATextStorageDelegate> _nonretained_delegate;
    NSUInteger _editingCount;
    NSUInteger _editedMask;
    NSInteger _changeInLength;
    NSRange _editedRange;
}

- (NSUndoManager *)undoManager;
- (void)edited:(NSUInteger)editedMask range:(NSRange)range changeInLength:(NSInteger)delta;
- (void)fixFontAttributeInRange:(NSRange)aRange;
- (void)processEditing;
- (NSUInteger)editedMask;
- (NSRange)editedRange;
- (NSInteger)changeInLength;

- (void)setDelegate:(id <OATextStorageDelegate>)delegate;
- (id <OATextStorageDelegate>)delegate;
@end
