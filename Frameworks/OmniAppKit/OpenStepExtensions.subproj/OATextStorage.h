// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#if OMNI_BUILDING_FOR_IOS
    #import <UIKit/NSTextStorage.h>
#elif OMNI_BUILDING_FOR_MAC
    #import <AppKit/NSTextStorage.h>
#endif

@class NSUndoManager;

#if OMNI_BUILDING_FOR_IOS || OMNI_BUILDING_FOR_MAC
    // Map to the built-in names
    #define OATextStorage NSTextStorage
    #define OATextStorageDelegate NSTextStorageDelegate
    #define OAAttachmentCharacter NSAttachmentCharacter
    #define OAAttachmentAttributeName NSAttachmentAttributeName
    #define OATextStorageWillProcessEditingNotification NSTextStorageWillProcessEditingNotification
    #define OATextStorageDidProcessEditingNotification NSTextStorageDidProcessEditingNotification
    #define OATextStorageEditActions NSTextStorageEditActions 
    #define OATextStorageEditedAttributes NSTextStorageEditedAttributes
    #define OATextStorageEditedCharacters NSTextStorageEditedCharacters
#else

#import <Foundation/NSAttributedString.h>

#define OATextStorage OATextStorage_

@class OATextStorage_;

// Define our own version of text storage.

@class NSNotification, NSUndoManager;

extern NSString * const OAAttachmentAttributeName;

enum {
    OAAttachmentCharacter = 0xfffc // The magical Unicode character for attachments in both Cocoa (NSAttachmentCharacter) and CoreText ('run delegate' there).
};

typedef NS_OPTIONS(NSUInteger, OATextStorageEditActions) {
    OATextStorageEditedAttributes = (1 << 0),
    OATextStorageEditedCharacters = (1 << 1)
};

extern NSString * const OATextStorageWillProcessEditingNotification;
extern NSString * const OATextStorageDidProcessEditingNotification;

@protocol OATextStorageDelegate <NSObject>
@optional

/* These methods are sent during processEditing:. Although these methods can change the contents of the text storage, it's best if only the delegate did this.
 */
- (void)textStorage:(OATextStorage *)textStorage willProcessEditing:(OATextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta;
- (void)textStorage:(OATextStorage *)textStorage didProcessEditing:(OATextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta;

@end

// Methods normally on NSAttributedString via AppKit or OmniAppKit when on the Mac
@interface NSAttributedString (OAAppKitEmulation)
- (BOOL)containsAttachments;
- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;
@end

#endif

// Make sure we can always say "OATextStorage_" as a real class name (for testing).
@interface OATextStorage_ : NSMutableAttributedString
{
@private
    id <OATextStorageDelegate> _nonretained_delegate;
    NSUInteger _editingCount;
    OATextStorageEditActions _editedMask;
    NSInteger _changeInLength;
    NSRange _editedRange;
}

- (NSUndoManager *)undoManager;
- (void)edited:(OATextStorageEditActions)editedMask range:(NSRange)range changeInLength:(NSInteger)delta;
- (void)fixFontAttributeInRange:(NSRange)aRange;
- (void)processEditing;
- (OATextStorageEditActions)editedMask;
- (NSRange)editedRange;
- (NSInteger)changeInLength;

- (void)setDelegate:(id <OATextStorageDelegate>)delegate;
- (id <OATextStorageDelegate>)delegate;
@end

