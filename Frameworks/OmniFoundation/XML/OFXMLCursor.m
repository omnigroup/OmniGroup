// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLCursor.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

struct _OFXMLCursorState {
    // Not retained -- the document should be retaining it (and it is invalid to modify the document while we are alive).
    OFXMLElement *element;

    // Cached from the element
    NSArray      *children;
    NSUInteger    childCount;
    
    // The next child to return
    NSUInteger    childIndex;
};

// NSNotFound is equal to the maximum NSInteger value, which is smack in the middle of NSUInteger's range. We only need to compare against our own sentinel value, though, not Apple's, so use an NSUInteger-specific sentinel.
#define InvalidChildIndex (~(NSUInteger)0)

static inline void _OFXMLCursorStateInit(struct _OFXMLCursorState *state, OFXMLElement *element)
{
    state->element    = element;
    state->children   = [state->element children];
    state->childCount = [state->children count];
    state->childIndex = InvalidChildIndex;
}

@interface OFXMLCursor (Private)
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
- (id)_nextChild:(BOOL)peek;
@end

@implementation OFXMLCursor
/*.doc. OFXMLCursor provides a simple way to traverse the elements in an OFXMLDocument.  At any point of time, the cursor can be thought of sitting 'at' one of the elements in the document (with the starting location being the root element).  The cursor also maintains a notion of the current child and allows you to enumerate through the children.  If you find a child that you want to recurse into temporarily, you can call -openElement.  Once you are done with that element, you call -closeElement to return to the cursor to the parent element (also restoring the notion of the current child).
*/

// Init and dealloc

- initWithDocument:(OFXMLDocument *)document element:(OFXMLElement *)element;
{
    OBPRECONDITION(document);
    OBPRECONDITION(element);
    
    _document = [document retain];
    _startingElement = [element retain];
    
    _state = NSAllocateCollectable(sizeof(*_state), NSScannedOption);
    _stateCount = 1;
    _stateSize = 1;

    _OFXMLCursorStateInit(_state, element);

    OBINVARIANT([self _checkInvariants]);
    return self;
}

// Initializes the receiver so that -currentChild will return the root element of the document.
- initWithDocument:(OFXMLDocument *)document;
{
    return [self initWithDocument:document element:[document rootElement]];
}

- (void)dealloc;
{
    OBINVARIANT([self _checkInvariants]);
    [_startingElement release];
    [_document release];
    if (_state)
        free(_state);
    [super dealloc];
}

- (OFXMLDocument *)document;
{
    OBINVARIANT([self _checkInvariants]);
    return _document;
}

- (OFXMLElement *)currentElement;
/*.doc. Return the parent over which the receiver is currently enumerating. */
{
    OBINVARIANT([self _checkInvariants]);
    return _state[_stateCount-1].element;
}

- (id)currentChild;
/*.doc. Returns the current child element.  This is the same thing as the previous result of -nextElement (since the last call to -openElement), but it doesn't advance the enumeration.  If -nextElement hasn't been called since the last call to -openElement, or if there are no more children of the current parent, this returns nil. */
{
    OBINVARIANT([self _checkInvariants]);

    const struct _OFXMLCursorState *state = &_state[_stateCount-1];
    
    if (state->childIndex == InvalidChildIndex)
        return nil;

    if (state->childIndex >= state->childCount)
        return nil;

    return [state->children objectAtIndex:state->childIndex];
}

- (NSString *)currentPath;
{
    OBINVARIANT([self _checkInvariants]);

    /*
     Right now this is just used for error reporting in OmniOutliner.  Later we should do two things:

     - Report stuff more like /root/child/grandchild[4]/great-grandchild where the '[4]' would be based on there being multiple elements at that level.
       Should look at the XPath spec.

     - Have an -initWithDocument:path: method for starting in the middle of a document
     */

    NSMutableString *path = [NSMutableString string];

    // Append all the parent elements
    unsigned int stateIndex;
    for (stateIndex = 0; stateIndex < _stateCount; stateIndex++)
        [path appendFormat:@"/%@", [_state[stateIndex].element name]];

    // Also, append the current child.  Note that it might not be an element!
    id currentChild = [self currentChild];
    if (currentChild) {
        if ([currentChild isKindOfClass:[OFXMLElement class]])
            [path appendFormat:@"/%@", [currentChild name]];
        else if ([currentChild isKindOfClass:[OFXMLString class]])
            [path appendFormat:@"/[STRING:%@]", [currentChild unquotedString]];
        else if ([currentChild isKindOfClass:[NSString class]])
            [path appendFormat:@"/[STRING:%@]", currentChild];
        else {
            OBASSERT(NO); // shouldn't get here, but at least append something
            [path appendFormat:@"/[UNKNOWN:%@]", currentChild];
        }
    } else {
        // Not sure what the best way do show is that we have an element open but no child selected underneath it.
        [path appendString:@"/"];
    }
    
    return path;
}

- (id)nextChild;
/*.doc. Returns the next unprocessed child of the -currentElement.  The first time this is called after -openElement, it will return the first element of the -currentElement and successive calls will return the remaining children in order.  If there are no more remaining children, this will begin returning nil and will continue to do so until -closeElement is called, at which point it will resume enumating from the next sibling of the -currentElement. */
{
    return [self _nextChild:NO];
}

- (id)peekNextChild;
{
    return [self _nextChild:YES];
}

- (void)openElement;
/*.doc. Suspends enumeration of the current parent element and instead starts enumerating the children of the -currentChild.  An exception will be raised if the -currentChild is not valid for this operation (it is nil or not an OFXMLElement). */
{
    OBINVARIANT([self _checkInvariants]);

    id currentChild = [self currentChild];
    if (!currentChild)
        [NSException raise:NSInternalInconsistencyException format:@"Attempted to call -openElement while -currentChild was nil."];
    if (![currentChild isKindOfClass:[OFXMLElement class]])
        [NSException raise:NSInternalInconsistencyException format:@"Attempted to call -openElement while -currentChild was not an OFXMLElement (currentChild = %@).", currentChild];

    _stateCount++;
    if (_stateCount > _stateSize) {
        _stateSize = 2 * _stateCount;
        _state = NSReallocateCollectable(_state, sizeof(*_state) * _stateSize, NSScannedOption);
    }

    _OFXMLCursorStateInit(&_state[_stateCount - 1], currentChild);

    OBINVARIANT([self _checkInvariants]);
}

- (void)closeElement;
/*.doc. Terminates enumeration of the current level and resumes enumeration of the next highest level.  Note that it is perfectly legal to call -openElement immediately again after this.  This will simply enumerate over the children of the element again. */
{
    OBINVARIANT([self _checkInvariants]);

    if (_stateCount == 1)
        // Since you don't call -openElement to get to the root element, you shouldn't close it either
        [NSException raise:NSInternalInconsistencyException format:@"Attempted to call -closeElement on the root element"];

    _stateCount--;
#ifdef DEBUG
    // Do our best to provoke an error if this gets referenced
    memset(&_state[_stateCount], 0xaa, sizeof(*_state));
#endif

    OBINVARIANT([self _checkInvariants]);
}

//
// Convenience methods that forward to -currentElement
//
- (NSString *)name;
{
    return [[self currentElement] name];
}

- (NSArray *)children;
{
    return [[self currentElement] children];
}

- (NSString *)attributeNamed:(NSString *)attributeName;
{
    return [[self currentElement] attributeNamed:attributeName];
}

- (BOOL)openNextChildElementNamed:(NSString *)childElementName;
{
    OBINVARIANT([self _checkInvariants]);

    struct _OFXMLCursorState *state = &_state[_stateCount-1];
    NSUInteger startingChildIndex = state->childIndex;

    id child;
    while ((child = [self nextChild])) {
        if (![child isKindOfClass:[OFXMLElement class]])
            continue;
        if ([[child name] isEqualToString:childElementName]) {
            [self openElement];
            return YES;
        }
    }

    // Didn't find a child; don't skip all the children that were previously unexplored.  For example, if our DTD says we can have "<a/><b/>" and <a> is optional, don't skip <b> if <a> is missing.
    state->childIndex = startingChildIndex;
    
    OBINVARIANT([self _checkInvariants]);
    return NO;
}

//
// Debugging
//
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict;

    dict = [super debugDictionary];
    [dict setObject:[self currentPath] forKey:@"currentPath"];
    return dict;
}

@end

@implementation OFXMLCursor (Private)

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{
    // There should always be a stack and it should be relatively well formed
    OBINVARIANT(_state != NULL);
    if (!_state)
        return YES;
    
    OBINVARIANT(_stateCount >= 1);
    OBINVARIANT(_stateSize >= _stateCount);

    // Should always have a document
    OBINVARIANT(_document);

    // The starting element should always be in the stack.
    OBINVARIANT(_state[0].element == _startingElement);

    // Check the cached values at each level
    unsigned int stateIndex;
    for (stateIndex = 0; stateIndex < _stateCount; stateIndex++) {
        const struct _OFXMLCursorState *state = &_state[stateIndex];

        // Check cached values
        OBINVARIANT(state->children   == [state->element children]);
        OBINVARIANT(state->childCount == [[state->element children] count]);

        // Make sure the current child index is valid (==childCount is valid since that is when we have finished all the children)
        OBINVARIANT(state->childIndex == InvalidChildIndex || state->childIndex <= state->childCount);

        // Make sure that each level of the stack points to the next
        if (stateIndex != 0) {
            const struct _OFXMLCursorState *prevState = &_state[stateIndex - 1];
            OBINVARIANT([prevState->children objectAtIndex:prevState->childIndex] == state->element);
        }
    }

    return YES;
}
#endif

- (id)_nextChild:(BOOL)peek;
{
    OBINVARIANT([self _checkInvariants]);

    struct _OFXMLCursorState *state = &_state[_stateCount-1];

    id child = nil;

    NSUInteger nextChildIndex = state->childIndex;
    if (state->childIndex == InvalidChildIndex && state->childCount > 0) {
        nextChildIndex = 0;
        child = [state->children objectAtIndex:nextChildIndex];
    } else if (state->childIndex < state->childCount) {
        // Skip to the next child, but the previously returned child might have been the last one, so check again.
        nextChildIndex++;
        if (nextChildIndex < state->childCount)
            child = [state->children objectAtIndex:nextChildIndex];
    }

    if (!peek)
        state->childIndex = nextChildIndex;

    OBINVARIANT([self _checkInvariants]);

    // This means that if peek is YES, then we should gotten a different child than the current child, except in the special case where we have no children.
#ifdef OMNI_ASSERTIONS_ON
    if (peek) {
        OBASSERT(!child || (child != [self currentChild]));
    } else {
        OBASSERT((!child && child == [self currentChild]) || (child && child == [self currentChild]));
    }
#endif
    return child;
}

@end

NSString * const OFXMLLoadError = @"OFXMLLoadError";

void OFXMLRejectElement(OFXMLCursor *cursor)
{
    NSString *format = NSLocalizedStringFromTableInBundle(@"Element '%@' not allowed at path: %@", @"OmniFoundation", OMNI_BUNDLE, "exception reason");
    [NSException raise:OFXMLLoadError format:format, [cursor name], [cursor currentPath]];
}
