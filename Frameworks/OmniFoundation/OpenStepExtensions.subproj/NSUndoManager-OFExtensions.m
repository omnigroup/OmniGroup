// Copyright 2001-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUndoManager-OFExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniBase/OmniBase.h>     // for 'shortDescription'

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>  // This seems to be the most parsimonious way to include CGBase.h for the CGFloat typedef
#else
#import <CoreGraphics/CGGeometry.h>
#endif

RCS_ID("$Id$");

static unsigned int OFUndoManagerLoggingOptions = OFUndoManagerNoLogging;
static CFMutableSetRef OFUndoManagerStates = NULL;
static Ivar targetIvar;

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

static id (*logging_original_prepareWithInvocationTarget)(id self, SEL _cmd, id target) = NULL;
static void (*logging_original_removeAllActions)(id self, SEL _cmd) = NULL;
static void (*logging_original_removeAllActionsWithTarget)(id self, SEL _cmd, id target) = NULL;
static void (*logging_original_registerUndoWithTargetSelectorObject)(id self, SEL _cmd, id target, SEL sel, id obj) = NULL;
static void (*logging_original_undo)(id self, SEL _cmd) = NULL;
static void (*logging_original_redo)(id self, SEL _cmd) = NULL;
static void (*logging_original_beginUndoGrouping)(id self, SEL _cmd) = NULL;
static void (*logging_original_endUndoGrouping)(id self, SEL _cmd) = NULL;
static void (*logging_original_disableUndoRegistration)(id self, SEL _cmd) = NULL;
static void (*logging_original_enableUndoRegistration)(id self, SEL _cmd) = NULL;
static void (*logging_original_dealloc)(id self, SEL _cmd) = NULL;

@interface NSUndoManager (OFUndoLogging)
- (void)logging_replacement_removeAllActions;
- (void)logging_replacement_removeAllActions;
- (void)logging_replacement_removeAllActionsWithTarget:(id)target;
- (void)logging_replacement_registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)anObject;
- (id)logging_replacement_prepareWithInvocationTarget:(id)target;
- (void)logging_replacement_undo;
- (void)logging_replacement_redo;
- (void)logging_replacement_beginUndoGrouping;
- (void)logging_replacement_endUndoGrouping;
- (void)logging_replacement_disableUndoRegistration;
- (void)logging_replacement_enableUndoRegistration;
- (void)logging_replacement_dealloc;
@end

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
            
            targetIvar = class_getInstanceVariable(self, "_target");
            OBASSERT(targetIvar);
            
#define REPL(old, name) old = (typeof(old))OBReplaceMethodImplementationWithSelector(self, @selector(name), @selector(logging_replacement_ ## name))
            
            REPL(logging_original_prepareWithInvocationTarget, prepareWithInvocationTarget:);
            REPL(logging_original_removeAllActions, removeAllActions);
            REPL(logging_original_removeAllActionsWithTarget, removeAllActionsWithTarget:);
            REPL(logging_original_registerUndoWithTargetSelectorObject, registerUndoWithTarget:selector:object:);
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
        if (indent) {
            
            unsigned int i;
            for (i = 0; i < state->indentLevel; i++)
                [state->buffer addObject:@"  "];
        }
        [state->buffer addObject:string];
    }
    
    [string release];
    [pool drain];
    
    return state;
}

void _OFUndoManagerPushCallSite(NSUndoManager *undoManager, id self, SEL _cmd)
{
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [undoManager isUndoRegistrationEnabled]) {
        OFUndoManagerLoggingState *state = _log(undoManager, YES, @"%@ %s {\n", [self shortDescription], _cmd);
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
        _log(self, NO, @"%p REMOVE ACTIONS target=%@\n", self, [target shortDescription]);
    }
    logging_original_removeAllActionsWithTarget(self, _cmd, target);
}

- (void)logging_replacement_registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)anObject;
{
    // Do this before logging so that the 'BEGIN' log happens first (probably in auto-group creation mode)
    logging_original_registerUndoWithTargetSelectorObject(self, _cmd, target, selector, anObject);

    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [self isUndoRegistrationEnabled]) {
        _log(self, YES, @">> target=%@ selector=%s object=%@\n", [target shortDescription], selector, anObject);
    }
}

// No NSMapTable on the iPhone as of yet.
static CFMutableDictionaryRef ProxyForwardInvocationClassToOriginalImp = nil;

static void logging_replacement_proxyFowardInvocation(id proxy, SEL _cmd, NSInvocation *anInvocation)
{
    // We depend on the proxy being an NSUndoManager proxy, which is a private class with a '_manager' ivar.
    NSUndoManager *self = nil;
    object_getInstanceVariable(proxy, "_manager", (void **)&self); // might fail

    // The target of the invocation is the proxy.  NSUndoManager stores the target for the undo an an ivar and doesn't set it on the NSInvocation, when we invoke the original.
    id target = self ? [object_getIvar(self, targetIvar) retain] : nil;

    // Do this before logging so that the 'BEGIN' log happens first (probably in auto-group creation mode)
    IMP original = (IMP)CFDictionaryGetValue(ProxyForwardInvocationClassToOriginalImp, object_getClass(proxy));
    original(proxy, _cmd, anInvocation);

    // bail if we failed to lookup the undo manager.
    if (!self) {
        [target release];
        return;
    }
    
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging) && [self isUndoRegistrationEnabled]) {
        _log(self, YES, @">> %@ %s ", [target shortDescription], [anInvocation selector]);
        
        NSMethodSignature *signature = [anInvocation methodSignature];
        NSUInteger argIndex, argCount;
        
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
            } else if (strcmp(type, @encode(CGPoint)) == 0) {
                CGPoint pt;
                [anInvocation getArgument:&pt atIndex:argIndex];
                _log(self, NO, @"<Point %g,%g>", pt.x, pt.y);
            } else if (strcmp(type, @encode(CGRect)) == 0) {
                CGRect rect;
                [anInvocation getArgument:&rect atIndex:argIndex];
                _log(self, NO, @"<Rect %gx%g at %g,%g>", rect.size.width, rect.size.height, rect.origin.x, rect.origin.y);
            } else if (strcmp(type, @encode(CGSize)) == 0) {
                CGSize size;
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

// In 10.6, NSUndoManager finally started returning a proxy object so that you could log undos for NSObject methods like -retain.  We need a proxy-proxy!  Proxy.  Now the word sounds funny.
- (id)logging_replacement_prepareWithInvocationTarget:(id)target;
{
    // Get the real undo manager's proxy
    id proxy = logging_original_prepareWithInvocationTarget(self, _cmd, target);
    if (!proxy) {
        OBASSERT(![self isUndoRegistrationEnabled]);
        return nil;
    }
    
    OBASSERT([self isUndoRegistrationEnabled]);
    
    // See if we've already overridden -forwardInvocation: on this class.
    Class proxyClass = object_getClass(proxy);
    IMP proxyImp = class_getMethodImplementation(proxyClass, @selector(forwardInvocation:));
    if (proxyImp != (IMP)logging_replacement_proxyFowardInvocation) {
        // Haven't swizzled this class yet.  Do so now and store it in our table.
        OBASSERT([NSThread isMainThread]); // Not worrying too much about undo managers in background threads at the moment.
        
        if (!ProxyForwardInvocationClassToOriginalImp)
            ProxyForwardInvocationClassToOriginalImp = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);
        
        // Do a replace, which returns the old IMP (in multi-threading we'll want to re-check the IMP returned).
        Method proxyMethod = class_getInstanceMethod(proxyClass, @selector(forwardInvocation:));
        proxyImp = class_replaceMethod(proxyClass, @selector(forwardInvocation:), (IMP)logging_replacement_proxyFowardInvocation, method_getTypeEncoding(proxyMethod));
        if (proxyImp != (IMP)logging_replacement_proxyFowardInvocation)
            CFDictionarySetValue(ProxyForwardInvocationClassToOriginalImp, proxyClass, proxyImp);
    }
    
    return proxy;
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
        OFUndoManagerLoggingState *state = _log(self, YES, @"BEGIN GROUPING(%p) {\n", self);
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
        _log(self, YES, @"} (%p)END GROUPING\n", self);
    }
}

- (void)logging_replacement_disableUndoRegistration;
{
    logging_original_disableUndoRegistration(self, _cmd);
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
        state->indentLevel++;
        _log(self, YES, @"BEGIN DISABLE UNDO REGISTRATION(%p) {\n", self);
    }
}

- (void)logging_replacement_enableUndoRegistration;
{
    logging_original_enableUndoRegistration(self, _cmd);
    if ((OFUndoManagerLoggingOptions != OFUndoManagerNoLogging)) {
        OFUndoManagerLoggingState *state = _OFUndoManagerLoggingStateGet(self);
        _log(self, YES, @"} (%p)END DISABLE UNDO REGISTRATION{\n", self);
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
