// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileState.h"

#import <OmniFoundation/OFEnumNameTable.h>

RCS_ID("$Id$")

// Most of our states are exclusive. 'moved' can be combined with Normal and Edited, but nothing else.
typedef NS_ENUM(NSUInteger, OFXPrimaryFileState) {
    OFXPrimaryFileStateNormal,
    OFXPrimaryFileStateMissing,
    OFXPrimaryFileStateEdited,
    OFXPrimaryFileStateDeleted,
};
#define OFXPrimaryFileStateMask (0xff)

#define OFXMoveStateMask (0xff00)
#define OFXMoveStateShift (8)

#define OFXFileStateUserMoved (1 << OFXMoveStateShift)
#define OFXFileStateAutoMoved (2 << OFXMoveStateShift)

@interface OFXFileState ()
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
@end

@implementation OFXFileState
{
    NSUInteger _state;
}

static OFXFileState *_stateWith(NSUInteger state)
{
    OFXFileState *instance = [OFXFileState new];
    instance->_state = state;
    OBPOSTCONDITION([instance _checkInvariants]);
    return instance;
}

+ (instancetype)missing;
{
    return _stateWith(OFXPrimaryFileStateMissing);
}

+ (instancetype)normal;
{
    return _stateWith(OFXPrimaryFileStateNormal);
}

+ (instancetype)edited;
{
    return _stateWith(OFXPrimaryFileStateEdited);
}

+ (instancetype)deleted;
{
    return _stateWith(OFXPrimaryFileStateDeleted);
}

// We allow non-content edits to have just the moved flag set. But these aren't "normal" from the perspective of "nothing to do to upload this"
- (BOOL)normal;
{
    OBINVARIANT([self _checkInvariants]);
    return _state == OFXPrimaryFileStateNormal; // Not masking in this case
}

#define GETTER(p, e) - (BOOL)p; { \
    OBINVARIANT([self _checkInvariants]); \
    return (_state & OFXPrimaryFileStateMask) == e; \
}

GETTER(missing, OFXPrimaryFileStateMissing);
GETTER(edited, OFXPrimaryFileStateEdited);
GETTER(deleted, OFXPrimaryFileStateDeleted);

- (BOOL)userMoved;
{
    OBINVARIANT([self _checkInvariants]);
    return (_state & OFXMoveStateMask) == OFXFileStateUserMoved;
}

- (BOOL)autoMoved;
{
    OBINVARIANT([self _checkInvariants]);
    return (_state & OFXMoveStateMask) == OFXFileStateAutoMoved;
}

- (BOOL)onlyAutoMoved;
{
    OBINVARIANT([self _checkInvariants]);
    return _state == (OFXPrimaryFileStateNormal|OFXFileStateAutoMoved);
}

- (instancetype)withEdited;
{
    if (_state == OFXPrimaryFileStateNormal)
        return [[self class] edited];
    if (_state == OFXFileStateUserMoved || _state == OFXFileStateAutoMoved)
        return _stateWith(_state|OFXPrimaryFileStateEdited);
    
    OBASSERT_NOT_REACHED("Called -withEdited on something that isn't moved or normal");
    return self;
}

- (instancetype)withUserMoved;
{
    // Allow for repeated moves (and promote automatic moves to user intended moves)
    NSUInteger moved = (_state & OFXMoveStateMask);
    if (moved) {
        OFXPrimaryFileState primaryState = _state & OFXPrimaryFileStateMask;
        return _stateWith(OFXFileStateUserMoved|primaryState);
    }
    
    if (_state == OFXPrimaryFileStateNormal)
        return _stateWith(OFXFileStateUserMoved|OFXPrimaryFileStateNormal);
    if (_state == OFXPrimaryFileStateEdited)
        return _stateWith(OFXFileStateUserMoved|OFXPrimaryFileStateEdited);
    if (_state == OFXPrimaryFileStateMissing)
        return _stateWith(OFXFileStateUserMoved|OFXPrimaryFileStateMissing);
    
    OBASSERT_NOT_REACHED("Called -withUserMoved on something that isn't edited or normal");
    return self;
}

- (instancetype)withAutoMoved;
{
    NSUInteger moved = (_state & OFXMoveStateMask);
    if (moved) {
        OBASSERT(moved == OFXFileStateAutoMoved, "Repeated automove is OK, but if the file was in the user-moved state, the caller needs to fix that");
        OFXPrimaryFileState primaryState = _state & OFXPrimaryFileStateMask;
        return _stateWith(OFXFileStateAutoMoved|primaryState);
    }
    
    if (_state == OFXPrimaryFileStateNormal)
        return _stateWith(OFXFileStateAutoMoved|OFXPrimaryFileStateNormal);
    if (_state == OFXPrimaryFileStateEdited)
        return _stateWith(OFXFileStateAutoMoved|OFXPrimaryFileStateEdited);
    if (_state == OFXPrimaryFileStateMissing)
        return _stateWith(OFXFileStateAutoMoved|OFXPrimaryFileStateMissing);
    
    OBASSERT_NOT_REACHED("Called -withAutoMoved on something that isn't edited or normal");
    return self;
}

- (instancetype)withAutoMovedCleared;
{
    OBPRECONDITION((_state & OFXMoveStateMask) == OFXFileStateAutoMoved, "Caller should check that the state included auto-move already");
    
    OFXPrimaryFileState primaryState = _state & OFXPrimaryFileStateMask;
    return _stateWith(primaryState);
}

static OFEnumNameTable *StateNameTable(void)
{
    static OFEnumNameTable *nameTable;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        nameTable = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OFXPrimaryFileStateNormal];
        [nameTable setName:@"normal" forEnumValue:OFXPrimaryFileStateNormal];
        [nameTable setName:@"missing" forEnumValue:OFXPrimaryFileStateMissing];
        [nameTable setName:@"edit" forEnumValue:OFXPrimaryFileStateEdited];
        [nameTable setName:@"delete" forEnumValue:OFXPrimaryFileStateDeleted];
        [nameTable setName:@"move" forEnumValue:OFXFileStateUserMoved];
        [nameTable setName:@"automove" forEnumValue:OFXFileStateAutoMoved];
        [nameTable setName:@"edit+move" forEnumValue:OFXPrimaryFileStateEdited|OFXFileStateUserMoved];
        [nameTable setName:@"edit+automove" forEnumValue:OFXPrimaryFileStateEdited|OFXFileStateAutoMoved];
        [nameTable setName:@"missing+move" forEnumValue:OFXPrimaryFileStateMissing|OFXFileStateUserMoved];
        [nameTable setName:@"missing+automove" forEnumValue:OFXPrimaryFileStateMissing|OFXFileStateAutoMoved];
    });
    
    return nameTable;
}

+ (instancetype)stateFromArchiveString:(NSString *)string;
{
    OBPRECONDITION([StateNameTable() isEnumName:string]);
    return _stateWith([StateNameTable() enumForName:string]);
}

- (NSString *)archiveString;
{
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION([StateNameTable() isEnumValue:_state]);
    return [StateNameTable() nameForEnum:_state];
}

#pragma mark - Comparison

- (BOOL)isEqual:(id)object;
{
    if (![object isKindOfClass:[OFXFileState class]])
        return NO;
    OFXFileState *otherState = object;
    return _state == otherState->_state;
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return self.archiveString;
}

- (NSString *)description;
{
    return self.archiveString;
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{
    NSUInteger primaryState = _state & OFXPrimaryFileStateMask;
    OBINVARIANT(primaryState <= OFXPrimaryFileStateDeleted, "Range of primary state enum");

    NSUInteger moved = (_state & ~OFXPrimaryFileStateMask);
    OBINVARIANT(moved == 0 || moved == OFXFileStateUserMoved || moved == OFXFileStateAutoMoved);
    
    OBINVARIANT(!moved || primaryState == OFXPrimaryFileStateNormal || primaryState == OFXPrimaryFileStateEdited || primaryState == OFXPrimaryFileStateMissing, "Moved can only be combined with normal/edited/missing");
    
    return YES;
}
#endif

@end
