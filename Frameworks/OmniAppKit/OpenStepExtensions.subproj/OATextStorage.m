// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextStorage.h>
#import <OmniBase/OmniBase.h>

#import <Foundation/NSNotification.h>

RCS_ID("$Id$");


#if 0 && defined(DEBUG)
    #define DEBUG_INSERT(format, ...) NSLog(@"INSERT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_INSERT(format, ...)
#endif

#if OMNI_BUILDING_FOR_SERVER

NSString * const OAAttachmentAttributeName = @"OAAttachmentAttributeName"; // Make this be the same as on the Mac?
NSString * const OATextStorageWillProcessEditingNotification = @"OATextStorageWillProcessEditingNotification";
NSString * const OATextStorageDidProcessEditingNotification = @"OATextStorageDidProcessEditingNotification";

#endif

// We always test our replacement. But, our replacement is really an abstract class, typically subclassed by OSStyledTextStorage.

@interface OAConcreteTextStorage : OATextStorage_
{
@private
    NSMutableAttributedString *_contents;
}

//- (id)initWithString:(NSString *)str attributes:(NSDictionary *)attrs NS_DESIGNATED_INITIALIZER;
- (id)initWithAttributedString:(NSAttributedString *)attrStr NS_DESIGNATED_INITIALIZER;

@end


@implementation OAConcreteTextStorage

// Various init methods to cover our superclass initializers

- init;
{
    return [self initWithString:@"" attributes:nil];
}

- (id)initWithString:(NSString *)str;
{
    return [self initWithString:str attributes:nil];
}

- (id)initWithString:(NSString *)str attributes:(NSDictionary *)attrs;
{
    if (!str)
        str = @"";
    
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:str attributes:attrs];
    self = [self initWithAttributedString:attributedString];
    return self;
}

- (id)initWithAttributedString:(NSAttributedString *)attrStr;
{
    if (!(self = [super init]))
        return nil;
    
    if (attrStr)
        _contents = [attrStr mutableCopy];
    else
        _contents = [[NSMutableAttributedString alloc] initWithString:@"" attributes:nil];
    
    // NSTextStorage starts out with having applied an edit. The only effect this ends up having is that editedRange is {NSNotFound, length} (since -processEditing will get called and it only resets editedRange.location.
    NSUInteger length = [_contents length];
    [self edited:OATextStorageEditedCharacters range:NSMakeRange(0, length) changeInLength:0];
    
    return self;
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
{
    BOOL _isProcessingEditing;
}

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

- (NSUndoManager *)undoManager;
{
    // TODO: -[NSTextStorage(OAExtensions) undoManager] should probably move to whatever we do here (rather than grunging over the layout managers.
    OBFinishPortingLater("<bug:///147889> (Frameworks-Mac Engineering: -[OATextStorage undoManager] - return an undoManager)");
    return nil;
}

// NSTextStorage clears the edit state *after* -processEditing has returned (so subclass implementations and notification observers can still see it).
static void _processEditing(OATextStorage_ *self)
{
    OBPRECONDITION(self->_isProcessingEditing == NO);

    // Avoid infinite recursion if the delegate or notification causes more edits.

    self->_isProcessingEditing = YES;

    [self processEditing];

    OBASSERT(self->_isProcessingEditing == YES);
    self->_isProcessingEditing = NO;

    // NSTextStorage only resets the location, so we only do that too (see our test cases).
    self->_editedRange.location = NSNotFound;
    self->_editedMask = 0;
    self->_changeInLength = 0;
}

- (void)edited:(OATextStorageEditActions)editedMask range:(NSRange)range changeInLength:(NSInteger)delta;
{
    DEBUG_INSERT(@"In %s. Edit location: %ld, length: %ld. Change in overall string length: %ld.", __func__, range.location, range.length, delta);
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
        OBASSERT(delta > 0 || range.length >= (NSUInteger)-delta);
        _editedRange = range;
        _editedRange.length += delta;
        _changeInLength = delta;
    } else {
        // Our _editedRange and the input are in the old space. Union them.
        DEBUG_INSERT(@"Old _editedRange length %ld and location %ld.", _editedRange.length, _editedRange.location);
        DEBUG_INSERT(@"New range length %ld and location %ld.", range.length, range.location);
        
        NSUInteger unionStart = MIN(_editedRange.location, range.location);
        NSUInteger unionEnd = MAX(NSMaxRange(_editedRange), NSMaxRange(range));
        NSRange unionRange = NSMakeRange(unionStart, unionEnd - unionStart);
        
        // Then adjust the length based on the input delta.
        OBASSERT(delta >= 0 || (NSUInteger)-delta <= unionRange.length);
        unionRange.length += delta;
        
        _editedRange = unionRange;
        DEBUG_INSERT(@"Unioned range length %ld and location %ld.", _editedRange.length, _editedRange.location);
        _changeInLength += delta;
        DEBUG_INSERT(@"Change in length for this edit: %ld, and total, %ld.", delta, _changeInLength);
    }
    
    // From NSTextStorage.h, if this is zero, we 
    if (_editingCount == 0 && !_isProcessingEditing)
        _processEditing(self);
}

- (void)fixFontAttributeInRange:(NSRange)aRange;
{
    // OBFinishPortingLater("<bug:///147890> (Frameworks-Mac Bug: Implement -[OATextStorage fixFontAttributeInRange:])");
}

- (void)processEditing;
{
    // NSTextStorage sends these notifications in this order, so we do too (see -testDelegateVsNotificationTiming)

    [[NSNotificationCenter defaultCenter] postNotificationName:OATextStorageWillProcessEditingNotification object:self];

    if ([_nonretained_delegate respondsToSelector:@selector(textStorage:willProcessEditing:range:changeInLength:)]) {
        [_nonretained_delegate textStorage:(id)self willProcessEditing:_editedMask range:_editedRange changeInLength:_changeInLength];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:OATextStorageDidProcessEditingNotification object:self];

    // TODO: Test whether this gets passed the same value as at the start, or the final value if there are extra edits during the previous phases.
    if ([_nonretained_delegate respondsToSelector:@selector(textStorage:didProcessEditing:range:changeInLength:)]) {
        [_nonretained_delegate textStorage:(id)self didProcessEditing:_editedMask range:_editedRange changeInLength:_changeInLength];
    }
}

- (OATextStorageEditActions)editedMask;
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
    _nonretained_delegate = delegate;
}

- (id <OATextStorageDelegate>)delegate;
{
    return _nonretained_delegate;
}

#pragma mark -
#pragma mark NSMutableAttributedString subclasses

// Inspecting in Hopper, NSMutableAttributedString's versions of these methods are no-ops, so we aren't calling super.
// Allow the counter to go up/down while we are sending -processEditing (so that we catch unbalanced operations during delegate/notifications).

- (void)beginEditing;
{
    _editingCount++;
}

- (void)endEditing;
{
    if (_editingCount == 0)
        [NSException raise:NSInternalInconsistencyException reason:@"Ended editing without a matching begin."];
    
    _editingCount--;
    if (_editingCount == 0 && !_isProcessingEditing) {
        _processEditing(self);
        OBASSERT(_editingCount == 0); // Any delegate/notification must have had balanced begin/end pairs too
    }
}

#pragma mark -
#pragma mark Private

// OOTextStorage subclasses this to send out -fastDelegateTextStorageWillUndoOrRedo:. So, we either need to change that, or use the same undo pattern that the Cocoa text system does.
- (void)_undoRedoTextOperation:(id)arg;
{
    
}

@end
