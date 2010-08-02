// Copyright 2003-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextStorage.h>
#import <OmniBase/OmniBase.h>

#import <Foundation/NSNotification.h>

RCS_ID("$Id$");

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

NSString * const OAAttachmentAttributeName = @"OAAttachmentAttributeName"; // Make this be the same as on the Mac?
NSString * const OATextStorageDidProcessEditingNotification = @"OATextStorageDidProcessEditingNotification";


@implementation NSAttributedString (OAAppKitEmulation)

- (BOOL)containsAttachments;
{
    NSUInteger position = 0, length = [self length];
    
    while (position < length) {
        NSRange effectiveRange;
        if ([self attribute:OAAttachmentAttributeName atIndex:position effectiveRange:&effectiveRange])
            return YES;
        position = NSMaxRange(effectiveRange);
    }
    
    return NO;
}

- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;
{
    return [self attribute:OAAttachmentAttributeName atIndex:characterIndex effectiveRange:NULL];
}

@end

#endif

// We always test our replacement. But, our replacement is really an abstract class, typically subclassed by OSStyledTextStorage.

@interface OAConcreteTextStorage : OATextStorage_
{
@private
    NSMutableAttributedString *_contents;
}
@end

@implementation OAConcreteTextStorage

- (id)initWithString:(NSString *)str attributes:(NSDictionary *)attrs;
{
    if (!(self = [super init]))
        return nil;
    
    _contents = [[NSMutableAttributedString alloc] initWithString:str attributes:attrs];
    
    // NSTextStorage starts out with having applied an edit. The only effect this ends up having is that editedRange is {NSNotFound, length} (since -processEditing will get called and it only resets editedRange.location.
    NSUInteger length = [_contents length];
    [self edited:OATextStorageEditedCharacters range:NSMakeRange(0, length) changeInLength:0];
    
    return self;
}

- (void)dealloc;
{
    [_contents release];
    [super dealloc];
}

- (NSUInteger)length;
{
    return [_contents length];
}

- (NSString *)string;
{
    return [_contents string];
}

- (NSDictionary *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range;
{
    return [_contents attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str;
{
    [_contents replaceCharactersInRange:range withString:str];
    [self edited:OATextStorageEditedCharacters range:range changeInLength:[str length] - range.length];
}

- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range;
{
    [_contents setAttributes:attrs range:range];
    [self edited:OATextStorageEditedAttributes range:range changeInLength:0];
}

@end

@implementation OATextStorage_

static Class OATextStorageClass = Nil;

+ (void)initialize;
{
    OBINITIALIZE;
    OATextStorageClass = [OATextStorage_ class];
}

+ (id)allocWithZone:(NSZone *)zone;
{
    if (self == OATextStorageClass)
        return [OAConcreteTextStorage allocWithZone:zone];
    return [super allocWithZone:zone];
}

// The other initializers are abstract, so the concrete classes must call this.
- init;
{
    if (!(self = [super init]))
        return nil;
    
    _editedRange = NSMakeRange(NSNotFound, 0);

    return self;
}

- (void)dealloc;
{
    if ([_nonretained_delegate respondsToSelector:@selector(textStorageDidProcessEditing:)])
        [[NSNotificationCenter defaultCenter] removeObserver:_nonretained_delegate name:OATextStorageDidProcessEditingNotification object:self];
    
    [super dealloc];
}

- (NSUndoManager *)undoManager;
{
    // TODO: -[NSTextStorage(OAExtensions) undoManager] should probably move to whatever we do here (rather than grunging over the layout managers.
    OBFinishPortingLater("Return an undo manager");
    return nil;
}

// NSTextStorage clears the edit state *after* -processEditing has returned (so subclass implementations and notification observers can still see it).
static void _processEditing(OATextStorage_ *self)
{
    [self processEditing];

    // NSTextStorage only resets the location, so we only do that too (see our test cases).
    self->_editedRange.location = NSNotFound;
    self->_editedMask = 0;
    self->_changeInLength = 0;
}

- (void)edited:(NSUInteger)editedMask range:(NSRange)range changeInLength:(NSInteger)delta;
{
    OBPRECONDITION(editedMask); // must have edited something
    OBPRECONDITION((editedMask & ~(OATextStorageEditedAttributes|OATextStorageEditedCharacters)) == 0); // only should get flags we know about
    OBPRECONDITION(range.location != NSNotFound); // must have edited something
    OBPRECONDITION((delta == 0) || (editedMask & OATextStorageEditedCharacters)); // can't change the length w/o changing characters (can change characters and not change length, though).
    OBPRECONDITION(delta > 0 || ((NSUInteger)-delta) <= range.length); // if deleting, we can't delete more than the original range.
    
    // Nothing actually happened.
    if (editedMask == OATextStorageEditedAttributes && range.length == 0)
        return;
    
    // NSTextStorage doesn't bail on this case. See -[OATextStorageMergedEditTests test3]
//    if (editedMask == OATextStorageEditedCharacters && range.length == 0 && delta == 0)
//        return;
    
    _editedMask |= editedMask;
    
    if (_editedRange.location == NSNotFound) {
        // First edit. The "range" argument is in our pre-edit state, so we need to adjust its length.
        OBASSERT(delta > 0 || _editedRange.length >= (NSUInteger)-delta);
        _editedRange = range;
        _editedRange.length += delta;
        _changeInLength = delta;
    } else {
        // Our _editedRange and the input are in the old space. Union them.
        
        NSUInteger unionStart = MIN(_editedRange.location, range.location);
        NSUInteger unionEnd = MAX(NSMaxRange(_editedRange), NSMaxRange(range));
        NSRange unionRange = NSMakeRange(unionStart, unionEnd - unionStart);
        
        // Then adjust the length based on the input delta.
        OBASSERT(delta >= 0 || (NSUInteger)-delta <= unionRange.length);
        unionRange.length += delta;
        
        _editedRange = unionRange;
        _changeInLength += delta;
    }
    
    // From NSTextStorage.h, if this is zero, we 
    if (_editingCount == 0)
        _processEditing(self);
}

- (void)fixFontAttributeInRange:(NSRange)aRange;
{
    OBFinishPortingLater("Fix up attributes");
}

- (void)processEditing;
{
    OBFinishPortingLater("Fix attributes or whatever else NSTextStorage does that we need.");
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OATextStorageDidProcessEditingNotification object:self];
}

- (NSUInteger)editedMask;
{
    return _editedMask;
}

- (NSRange)editedRange;
{
    return _editedRange;
}

- (NSInteger)changeInLength;
{
    return _changeInLength;
}

- (void)setDelegate:(id <OATextStorageDelegate>)delegate;
{
    if ([_nonretained_delegate respondsToSelector:@selector(textStorageDidProcessEditing:)])
        [[NSNotificationCenter defaultCenter] removeObserver:_nonretained_delegate name:OATextStorageDidProcessEditingNotification object:self];
    
    _nonretained_delegate = delegate;

    if ([_nonretained_delegate respondsToSelector:@selector(textStorageDidProcessEditing:)])
        [[NSNotificationCenter defaultCenter] addObserver:_nonretained_delegate selector:@selector(textStorageDidProcessEditing:) name:OATextStorageDidProcessEditingNotification object:self];
}

- (id <OATextStorageDelegate>)delegate;
{
    return _nonretained_delegate;
}

#pragma mark -
#pragma mark NSMutableAttributedString subclasses

- (void)beginEditing;
{
    [super beginEditing];
    _editingCount++;
}

- (void)endEditing;
{
    if (_editingCount == 0)
        [NSException raise:NSInternalInconsistencyException reason:@"Ended editing without a matching begin."];
    
    _editingCount--;
    if (_editingCount == 0)
        _processEditing(self);
}

#pragma mark -
#pragma mark Private

// OOTextStorage subclasses this to send out -fastDelegateTextStorageWillUndoOrRedo:. So, we either need to change that, or use the same undo pattern that the Cocoa text system does.
- (void)_undoRedoTextOperation:(id)arg;
{
    
}

@end
