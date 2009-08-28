// Copyright 2001-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUndoManager-OFExtensions.h>

#import <Foundation/NSGeometry.h>

RCS_ID("$Id$");

static unsigned int OFUndoManagerLoggingOptions = OFUndoManagerNoLogging;
static CFMutableSetRef OFUndoManagerStates = NULL;

#ifdef __OBJC2__
#if __OBJC2__
static Ivar targetIvar;
#define USE_IVAR_INDIRECTION
#endif
#endif

typedef struct {
    NSUndoManager *undoManager; // non-retained
    unsigned int indentLevel;
    NSMutableArray *buffer;
} OFUndoManagerLoggingState;


static void _OFUndoManagerLoggingStateDestroy(CFAllocatorRef allocator, const void *value)
{
    OFUndoManagerLoggingState *state = (OFUndoManagerLoggingState *)value;
    [state->buffer release];
    free(state);
}

static Boolean _OFUndoManagerLoggingStateEqual(const void *value1, const void *value2)
{
    const OFUndoManagerLoggingState *state1 = value1;
    const OFUndoManagerLoggingState *state2 = value2;
    
    return state1->undoManager == state2->undoManager;
}

static CFHashCode _OFUndoManagerLoggingStateHash(const void *value)
{
    const OFUndoManagerLoggingState *state = value;
    return (CFHashCode)state->undoManager;
}

static OFUndoManagerLoggingState *_OFUndoManagerLoggingStateGet(NSUndoManager *undoManager)
{
    OFUndoManagerLoggingState proto = (OFUndoManagerLoggingState){.undoManager = undoManager};
    OFUndoManagerLoggingState *state = (OFUndoManagerLoggingState *)CFSetGetValue(OFUndoManagerStates, &proto);
    
    if (!state) {
        NSLog(@"Creating undo logging state for %@", undoManager);
        state = calloc(1, sizeof(*state));
        state->undoManager = undoManager;
        
        CFSetAddValue(OFUndoManagerStates, state);
    }
    return state;
}

static void (*logging_original_removeAllActions)(id self, SEL _cmd) = NULL;
static void (*logging_original_removeAllActionsWithTarget)(id self, SEL _cmd, id target) = NULL;
static void (*logging_original_registerUndoWithTargetSelectorObject)(id self, SEL _cmd, id target, SEL sel, id obj) = NULL;
static void (*logging_original_forwardInvocation)(id self, SEL _cmd, NSInvocation *invocation) = NULL;
static void (*logging_original_undo)(id self, SEL _cmd) = NULL;
static void (*logging_original_redo)(id self, SEL _cmd) = NULL;
static void (*logging_original_beginUndoGrouping)(id self, SEL _cmd) = NULL;
static void (*logging_original_endUndoGrouping)(id self, SEL _cmd) = NULL;
static void (*logging_original_disableUndoRegistration)(id self, SEL _cmd) = NULL;
static void (*logging_original_enableUndoRegistration)(id self, SEL _cmd) = NULL;
static void (*logging_original_dealloc)(id self, SEL _cmd) = NULL;

@implementation NSUndoManager (OFExtensions)

- (BOOL)isUndoingOrRedoing;
{
    return [self isUndoing] || [self isRedoing];
}

// Use this instead of the regular -setActionName:.  This won't create an undo group if there's not one there already.
- (void)setActionNameIfGrouped:(NSString *)newActionName;
{
    if (newActionName != nil && [self groupingLevel] > 0)
        [self setActionName:newActionName];
}

- (void)registerUndoWithValue:(id)oldValue forKey:(NSString *)aKey of:(NSObject *)kvcCompliantTarget;
{
    // We can't use -prepareWithInvocationTarget: in the normal way here because it'll attempt to set a value on the NSUndoManager instead of creating an invocation.
    NSInvocation *resetInvocation = [NSInvocation invocationWithMethodSignature:[kvcCompliantTarget methodSignatureForSelector:@selector(setValue:forKey:)]];
    [resetInvocation setSelector:@selector(setValue:forKey:)];
    [resetInvocation setArgument:&oldValue atIndex:2];
    [resetInvocation setArgument:&aKey atIndex:3];
    [resetInvocation retainArguments];
    [[self prepareWithInvocationTarget:kvcCompliantTarget] forwardInvocation:resetInvocation];
}

+ (unsigned int)loggingOptions;
{
    return OFUndoManagerLoggingOptions;
}

+ (void)setLoggingOptions:(unsigned int)options;
{
    if (OFUndoManagerLoggingOptions == options)
        return;

    // Avoiding deprecated -poseAs: and requiring that users allocate a custom subclass (might not be feasible for undo managers that are allocated in Apple frameworks).
    
    if (OFUndoManagerStates) {
        // reset all the states; assumes we aren't in the middle of undo logging when we change state.
        CFRelease(OFUndoManagerStates);
        OFUndoManagerStates = NULL;
    }

    OFUndoManagerLoggingOptions = options;

    if (OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) {
        if (!OFUndoManagerStates) {
            CFSetCallBacks callbacks;
            memset(&callbacks, 0, sizeof(callbacks));
            
            callbacks.release = _OFUndoManagerLoggingStateDestroy;
            callbacks.equal = _OFUndoManagerLoggingStateEqual;
            callbacks.hash = _OFUndoManagerLoggingStateHash;
            OFUndoManagerStates = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
        }
        
        static BOOL methodsInstalled = NO;
        if (!methodsInstalled) {
            
#ifdef USE_IVAR_INDIRECTION
            targetIvar = class_getInstanceVariable(self, "_target");
#endif
            
#define REPL(old, name) old = (typeof(old))OBReplaceMethodImplementationWithSelector(self, @selector(name), @selector(logging_replacement_ ## name))
            
            REPL(logging_original_removeAllActions, removeAllActions);
            REPL(logging_original_removeAllActionsWithTarget, removeAllActionsWithTarget:);
            REPL(logging_original_registerUndoWithTargetSelectorObject, registerUndoWithTarget:selector:object:);
            REPL(logging_original_forwardInvocation, forwardInvocation:);
            REPL(logging_original_undo, undo);
            REPL(logging_original_redo, redo);
            REPL(logging_original_beginUndoGrouping, beginUndoGrouping);
            REPL(logging_original_endUndoGrouping, endUndoGrouping);
            REPL(logging_original_disableUndoRegistration, disableUndoRegistration);
            REPL(logging_original_enableUndoRegistration, enableUndoRegistration);
            REPL(logging_original_dealloc, dealloc);
            methodsInstalled = YES;
        }
    }
}

- (NSString *)loggingBuffer;
{
    if ((OFUndoManagerLoggingOptions & OFUndoManagerLogToBuffer) == 0)
        return nil;
    
    OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
    return [state->buffer componentsJoinedByString:@""];
}

- (void)clearLoggingBuffer;
{
    if ((OFUndoManagerLoggingOptions & OFUndoManagerLogToBuffer) == 0)
        return;
    
    OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
    [state->buffer removeAllObjects];
}

@end


static OFUndoManagerLoggingState *_log(NSUndoManager *self, BOOL indent, NSString *format, ...)
{
    OBPRECONDITION(OFUndoManagerLoggingOptions != OFUndoManagerNoLogging);
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
    
    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    if (OFUndoManagerLoggingOptions & OFUndoManagerLogToConsole) {
        if (indent) {
            unsigned int i;
            for (i = 0; i < state->indentLevel; i++)
                fputs("  ", stderr);
        }
        fprintf(stderr, "%s", [string UTF8String]);
    }
    
    if (OFUndoManagerLoggingOptions & OFUndoManagerLogToBuffer) {
        if (state->buffer == nil)
            state->buffer = [[NSMutableArray alloc] init];
        if (indent)
            [state->buffer addObject:[NSString spacesOfLength:2*state->indentLevel]];
        [state->buffer addObject:string];
    }
    
    [string release];
    [pool release];
    
    return state;
}

void _OFUndoManagerPushCallSite(NSUndoManager *undoManager, id self, SEL _cmd)
{
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [undoManager isUndoRegistrationEnabled]) {
        Class cls = [self class];
        OFUndoManagerLoggingState *state = _log(undoManager, YES, @"<%s:0x%08x> %s {\n", class_getName(cls), self, _cmd);
        state->indentLevel++;
    }
}

void _OFUndoManagerPopCallSite(NSUndoManager *undoManager)
{
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [undoManager isUndoRegistrationEnabled]) {
        OFUndoManagerLoggingState *state = _log(undoManager, YES, @"}\n");
        state->indentLevel--;
    }
}

@interface NSUndoManager (Private)
- (id)getInvocationTarget;
@end
@implementation NSUndoManager (Private)
#ifdef USE_IVAR_INDIRECTION
- (id)getInvocationTarget;
{
    return object_getIvar(self, targetIvar);
}
#else
- (id)getInvocationTarget;
{
    return _target;
}
#endif
@end

@interface NSUndoManager (OFUndoLogging)
@end

@implementation NSUndoManager (OFUndoLogging)

+ (void)performPosing;
{
    if (getenv("OFUndoManagerLoggingOptions") != NULL)
        [self setLoggingOptions:atoi(getenv("OFUndoManagerLoggingOptions"))]; // TODO: Use an OFEnumNameTable and NSUserDefaults to make this more friendly
}

- (void)logging_replacement_removeAllActions;
{
    OBASSERT([self isUndoRegistrationEnabled]);
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging))
        _log(self, NO, @"REMOVE ALL ACTIONS\n");
    logging_original_removeAllActions(self, _cmd);
}

- (void)logging_replacement_removeAllActionsWithTarget:(id)target;
{
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        Class cls = [target class];
        _log(self, NO, @"%p REMOVE ACTIONS target=<%s:0x%08x>\n", self, class_getName(cls), target);
    }
    logging_original_removeAllActionsWithTarget(self, _cmd, target);
}

- (void)logging_replacement_registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)anObject;
{
    // Do this before logging so that the 'BEGIN' log happens first (probably in auto-group creation mode)
    logging_original_registerUndoWithTargetSelectorObject(self, _cmd, target, selector, anObject);

    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [self isUndoRegistrationEnabled]) {
        Class cls = [target class];
        _log(self, YES, @">> target=<%s:0x%08x> selector=%s object=%@\n", class_getName(cls), target, selector, anObject);
    }
}

- (void)logging_replacement_forwardInvocation:(NSInvocation *)anInvocation;
{
    // Grab this first since super resets _target and doesn't stick it on the NSInvocation (so we have to access _target directly, sadly).
    id target = [[self getInvocationTarget] retain];

    // Do this before logging so that the 'BEGIN' log happens first (probably in auto-group creation mode)
    logging_original_forwardInvocation(self, _cmd, anInvocation);

    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [self isUndoRegistrationEnabled]) {
        Class cls = [target class];
        _log(self, YES, @">> <%s:%p> %s ", class_getName(cls), target, [anInvocation selector]);

        NSMethodSignature *signature = [anInvocation methodSignature];
        unsigned int argIndex, argCount;

        // Arg0 is the receiver, arg1 is the selector.  Skip those here.
        argCount = [signature numberOfArguments];
        for (argIndex = 2; argIndex < argCount; argIndex++) {
            const char *type = [signature getArgumentTypeAtIndex:argIndex];
            _log(self, NO, @" arg%d(%s):", argIndex - 2, type);
            if (strcmp(type, @encode(id)) == 0) {
                id arg = nil;
                [anInvocation getArgument:&arg atIndex:argIndex];
                _log(self, NO, @"%@", arg? [arg shortDescription] : @"nil");
            } else if (strcmp(type, @encode(Class)) == 0) {
                Class arg = Nil;
                [anInvocation getArgument:&arg atIndex:argIndex];
                _log(self, NO, @"<Class:%@>", NSStringFromClass(arg));
            } else if (strcmp(type, @encode(int)) == 0) {
                int arg = -1;
                [anInvocation getArgument:&arg atIndex:argIndex];
                _log(self, NO, @"%d", arg);
            } else if (strcmp(type, @encode(unsigned int)) == 0) {
                unsigned int arg = -1;
                [anInvocation getArgument:&arg atIndex:argIndex];
                _log(self, NO, @"%u", arg);
            } else if (strcmp(type, @encode(float)) == 0) {
                float arg = -1;
                [anInvocation getArgument:&arg atIndex:argIndex];
                _log(self, NO, @"%g", arg);
            } else if (strcmp(type, @encode(SEL)) == 0) {
                SEL sel;
                [anInvocation getArgument:&sel atIndex:argIndex];
                _log(self, NO, @"%s", sel);
            } else if (strcmp(type, @encode(BOOL)) == 0) {
                BOOL arg;
                [anInvocation getArgument:&arg atIndex:argIndex];
                _log(self, NO, @"%u", (unsigned int)arg);
            } else if (strcmp(type, @encode(NSRange)) == 0) {
                NSRange range;
                [anInvocation getArgument:&range atIndex:argIndex];
                _log(self, NO, @"%@", NSStringFromRange(range));
            } else if (strcmp(type, @encode(NSPoint)) == 0) {
                NSPoint pt;
                [anInvocation getArgument:&pt atIndex:argIndex];
                _log(self, NO, @"<Point %g,%g>", pt.x, pt.y);
            } else if (strcmp(type, @encode(NSRect)) == 0) {
                NSRect rect;
                [anInvocation getArgument:&rect atIndex:argIndex];
                _log(self, NO, @"<Rect %gx%g at %g,%g>", rect.size.width, rect.size.height, rect.origin.x, rect.origin.y);
            } else if (strcmp(type, @encode(NSSize)) == 0) {
                NSSize size;
                [anInvocation getArgument:&size atIndex:argIndex];
                _log(self, NO, @"<Size %gx%g>", size.width, size.height);
            } else {
                _log(self, NO, @"UNKNOWN ARG TYPE");
            }
        }
        _log(self, NO, @"\n");
    }

    [target release];
}

- (void)logging_replacement_undo;
{
    OFUndoManagerLoggingState *state = NULL;
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        state = _log(self, YES, @"UNDO {\n");
        state->indentLevel++;
    }
    
    logging_original_undo(self, _cmd);
    
    if (state) {
        state->indentLevel--;
        _log(self, YES, @"} UNDO\n");
    }
}

- (void)logging_replacement_redo;
{
    OFUndoManagerLoggingState *state = NULL;
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        state = _log(self, YES, @"REDO {\n");
        state->indentLevel++;
    }
    
    logging_original_redo(self, _cmd);
    
    if (state) {
        state->indentLevel--;
        _log(self, YES, @"} REDO\n");
    }
}

- (void)logging_replacement_beginUndoGrouping;
{
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        OFUndoManagerLoggingState *state = _log(self, YES, @"BEGIN GROUPING(%08x) {\n", self);
        state->indentLevel++;
    }
    
    logging_original_beginUndoGrouping(self, _cmd);
}

- (void)logging_replacement_endUndoGrouping;
{
    logging_original_endUndoGrouping(self, _cmd);
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
        state->indentLevel--;
        _log(self, YES, @"} (%08x)END GROUPING\n", self);
    }
}

- (void)logging_replacement_disableUndoRegistration;
{
    logging_original_disableUndoRegistration(self, _cmd);
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
        state->indentLevel++;
        _log(self, YES, @"BEGIN DISABLE UNDO REGISTRATION(%08x) {\n", self);
    }
}

- (void)logging_replacement_enableUndoRegistration;
{
    logging_original_enableUndoRegistration(self, _cmd);
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
        _log(self, YES, @"} (%08x)END DISABLE UNDO REGISTRATION{\n", self);
        state->indentLevel--;
    }
}

- (void)logging_replacement_dealloc;
{
    // clear up extra state
    if (OFUndoManagerStates) {
        OFUndoManagerLoggingState proto = (OFUndoManagerLoggingState){.undoManager = self};
        OFUndoManagerLoggingState *state = (OFUndoManagerLoggingState *)CFSetGetValue(OFUndoManagerStates, &proto);
        if (state)
            CFSetRemoveValue(OFUndoManagerStates, state);
    }
    
    logging_original_dealloc(self, _cmd);
}

@end
