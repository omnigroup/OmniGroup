// Copyright 2000-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$");

#import <OmniBase/OBLoadAction.h>

/*
 Various hacks into the Cocoa scripting support to make debugging easier.
 */

#if 1 && defined(DEBUG)

#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSScriptCommandDescription.h>
#import <Foundation/NSScriptObjectSpecifiers.h>

@interface NSClassDescription (OFDebugging)
@end
@implementation NSClassDescription (OFDebugging)

static NSClassDescription * (*original_NSClassDescription_classDescriptionForClass)(Class self, SEL _cmd, Class aClass);
static void (*original_NSClassDescription_registerClassDescriptionForClass)(Class self, SEL _cmd, NSClassDescription *description, Class aClass);

OBPerformPosing(^{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;
    
    Class self = objc_getClass("NSClassDescription");

    original_NSClassDescription_classDescriptionForClass = (typeof(original_NSClassDescription_classDescriptionForClass))OBReplaceMethodImplementationWithSelector(object_getClass(self), @selector(classDescriptionForClass:), @selector(replacement_classDescriptionForClass:));
    original_NSClassDescription_registerClassDescriptionForClass = (typeof(original_NSClassDescription_registerClassDescriptionForClass))OBReplaceMethodImplementationWithSelector(object_getClass(self), @selector(registerClassDescription:forClass:), @selector(replacement_registerClassDescription:forClass:));
});

+ (void)replacement_registerClassDescription:(NSClassDescription *)description forClass:(Class)aClass;
{
    NSLog(@"CLASS DESCRIPTION REGISTER %@ -> %p", aClass, description);
    original_NSClassDescription_registerClassDescriptionForClass(self, _cmd, description, aClass);
}

+ (NSClassDescription *)replacement_classDescriptionForClass:(Class)aClass;
{
    /*
     This can be caused by the fact that -[NSObject classDescription] calls +[NSClassDescription classDescriptionForClass:] and does *not* look up the superclass chain.
     The confusing part is that +[NSScriptClassDescription classDescriptionForClass:] *does* look up the superclass chain. So, you'd be tempted to call that, but calling the instance method is still better since it lets you support polymorphic instances.
     Often, this can be fixed by changing your sdef to register the exact implementation class for your document class (you can't override it in a class-extension element).
     */
    NSClassDescription *description = original_NSClassDescription_classDescriptionForClass(self, _cmd, aClass);
    if (!description)
        NSLog(@"CLASS DESCRIPTION LOOKUP %@ -> %p", aClass, description);
    return description;
}

@end

@interface NSPositionalSpecifier (OFDebugging)
@end
@implementation NSPositionalSpecifier (OFDebugging)

static BOOL (*original_NSPositionalSpecifier_describedClass_isSubclassOfClass)(Class self, SEL _cmd, id cls, Class superclass) = NULL;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
OBPerformPosing(^{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;
    
    Class self = objc_getClass("NSPositionalSpecifier");

    original_NSPositionalSpecifier_describedClass_isSubclassOfClass = (typeof(original_NSPositionalSpecifier_describedClass_isSubclassOfClass))OBReplaceClassMethodImplementationWithSelector(self, @selector(_describedClass:isSubclassOfClass:), @selector(_replacement_describedClass:isSubclassOfClass:));
});
#pragma clang diagnostic pop

+ (BOOL)_replacement_describedClass:(id)cls isSubclassOfClass:(Class)otherClass;
{
    BOOL result = original_NSPositionalSpecifier_describedClass_isSubclassOfClass(self, _cmd, cls, otherClass);
    NSLog(@"IS SUBCLASS %@ of %@ -> %d", cls, otherClass, result);
    return result;
}

@end

@interface NSScriptObjectSpecifier (OFDebugging)
@end
@implementation NSScriptObjectSpecifier (OFDebugging)

static id (*original_NSScriptObjectSpecifier_objectsByEvaluatingSpecifier)(NSScriptObjectSpecifier *self, SEL _cmd);

OBPerformPosing(^{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;

    Class self = objc_getClass("NSScriptObjectSpecifier");

    original_NSScriptObjectSpecifier_objectsByEvaluatingSpecifier = (typeof(original_NSScriptObjectSpecifier_objectsByEvaluatingSpecifier))OBReplaceMethodImplementationWithSelector(self, @selector(objectsByEvaluatingSpecifier), @selector(replacement_objectsByEvaluatingSpecifier));
});

- (id)replacement_objectsByEvaluatingSpecifier;
{
    id objects = original_NSScriptObjectSpecifier_objectsByEvaluatingSpecifier(self, _cmd);
    NSLog(@"EVAL %@ -> %@", self, objects);
    return objects;
}

@end

@interface NSIndexSpecifier (OFDebugging)
@end
@implementation NSIndexSpecifier (OFDebugging)

static id (*original_NSIndexSpecifier_objectsByEvaluatingSpecifier)(NSIndexSpecifier *self, SEL _cmd);
static id (*original_objectsByEvaluatingWithContainers)(NSIndexSpecifier *self, SEL _cmd, id containers);

OBPerformPosing(^{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;

    Class self = objc_getClass("NSIndexSpecifier");

    original_NSIndexSpecifier_objectsByEvaluatingSpecifier = (typeof(original_NSIndexSpecifier_objectsByEvaluatingSpecifier))OBReplaceMethodImplementationWithSelector(self, @selector(objectsByEvaluatingSpecifier), @selector(replacement_objectsByEvaluatingSpecifier));
    original_objectsByEvaluatingWithContainers = (typeof(original_objectsByEvaluatingWithContainers))OBReplaceMethodImplementationWithSelector(self, @selector(objectsByEvaluatingWithContainers:), @selector(replacement_objectsByEvaluatingWithContainers:));
});

- (id)replacement_objectsByEvaluatingSpecifier;
{
    id objects = original_NSIndexSpecifier_objectsByEvaluatingSpecifier(self, _cmd);
    NSLog(@"EVAL %@ -> %@", self, objects);
    return objects;
}

- (id)replacement_objectsByEvaluatingWithContainers:(id)containers;
{
    id objects = original_objectsByEvaluatingWithContainers(self, _cmd, containers);
    NSLog(@"EVAL %@ with containers %@ -> %@", self, containers, objects);
    return objects;
}

@end



@interface NSScriptClassDescription (OFDebugging)
@end
@implementation NSScriptClassDescription (OFDebugging)

static NSScriptClassDescription *(*original_NSScriptClassDescription_classDescriptionForClass)(Class self, SEL _cmd, Class aClass);
static NSScriptClassDescription *(*original_NSScriptClassDescription_classDescriptionForKey)(NSScriptClassDescription *self, SEL _cmd, NSString *key);
static NSString *(*original_NSScriptClassDescription_keyWithAppleEventCode)(NSScriptClassDescription *self, SEL _cmd, FourCharCode appleEventCode);
static BOOL (*original_NSScriptClassDescription_supportsCommand)(id self, SEL _cmd, NSScriptCommandDescription *commandDef);
static SEL (*original_NSScriptClassDescription_selectorForCommand)(id self, SEL _cmd, NSScriptCommandDescription *commandDef);

OBPerformPosing(^{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;

    Class self = objc_getClass("NSScriptClassDescription");

    original_NSScriptClassDescription_classDescriptionForClass = (typeof(original_NSScriptClassDescription_classDescriptionForClass))OBReplaceMethodImplementationWithSelector(object_getClass(self), @selector(classDescriptionForClass:), @selector(replacement_classDescriptionForClass:));
    original_NSScriptClassDescription_classDescriptionForKey = (typeof(original_NSScriptClassDescription_classDescriptionForKey))OBReplaceMethodImplementationWithSelector(self, @selector(classDescriptionForKey:), @selector(replacement_classDescriptionForKey:));
    original_NSScriptClassDescription_keyWithAppleEventCode = (typeof(original_NSScriptClassDescription_keyWithAppleEventCode))OBReplaceMethodImplementationWithSelector(self, @selector(keyWithAppleEventCode:), @selector(replacement_keyWithAppleEventCode:));
    original_NSScriptClassDescription_supportsCommand = (typeof(original_NSScriptClassDescription_supportsCommand))OBReplaceMethodImplementationWithSelector(self, @selector(supportsCommand:), @selector(replacement_supportsCommand:));
    original_NSScriptClassDescription_selectorForCommand = (typeof(original_NSScriptClassDescription_selectorForCommand))OBReplaceMethodImplementationWithSelector(self, @selector(selectorForCommand:), @selector(replacement_selectorForCommand:));
});

+ (NSScriptClassDescription *)replacement_classDescriptionForClass:(Class)aClass;
{
    NSScriptClassDescription *description = original_NSScriptClassDescription_classDescriptionForClass(self, _cmd, aClass);
    NSLog(@"GET CLASS DESC %@ -> %p", aClass, description);
    
    // We expect nothing to have a plain 'item' type. If we *do* need this later, we can make this check more specific, but a common error is that *no* class description gets registered and we get this useless fallback.
    OBASSERT_IF(description.appleEventCode != 'cobj', [description.className isEqualToString:@"item"] == NO);
    
    return description;
}

- (NSScriptClassDescription *)replacement_classDescriptionForKey:(NSString *)key;
{
    NSScriptClassDescription *result = original_NSScriptClassDescription_classDescriptionForKey(self, _cmd, key);
    NSLog(@"[%@:%@] classDescriptionForKey:%@ -> %@", [self suiteName], [self className], key, [result shortDescription]);
    return result;
}

- (NSString *)replacement_keyWithAppleEventCode:(FourCharCode)code;
{
    NSString *result = original_NSScriptClassDescription_keyWithAppleEventCode(self, _cmd, code);
    NSLog(@"[%@:%@] keyWithAppleEventCode:%@ -> %@", [self suiteName], [self className], [NSString stringWithFourCharCode:code], result);
    return result;
}

- (BOOL)replacement_supportsCommand:(NSScriptCommandDescription *)commandDef;
{
    BOOL yn = original_NSScriptClassDescription_supportsCommand(self, _cmd, commandDef);
    NSLog(@"[%@:%@] supportsCommand:%@ -> %d", [self suiteName], [self className], [commandDef shortDescription], yn);
    return yn;
}

- (SEL)replacement_selectorForCommand:(NSScriptCommandDescription *)commandDef;
{
    SEL sel = (SEL)original_NSScriptClassDescription_selectorForCommand(self, _cmd, commandDef);
    NSLog(@"[%@:%@] selectorForCommand:%@ -> %@", [self suiteName], [self className], [commandDef shortDescription], NSStringFromSelector(sel));
    return sel;
}

@end

#import <Foundation/NSScriptCoercionHandler.h>

@interface NSScriptCoercionHandler (OFDebugging)
@end
@implementation NSScriptCoercionHandler (OFDebugging)

static id (*original_coerceValue_toClass)(id self, SEL _cmd, id value, Class cls) = NULL;

OBPerformPosing(^{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;
    
    Class self = objc_getClass("NSScriptCoercionHandler");

    original_coerceValue_toClass = (typeof(original_coerceValue_toClass))OBReplaceMethodImplementationWithSelector(self, @selector(coerceValue:toClass:), @selector(replacement_coerceValue:toClass:));
});

- (id)replacement_coerceValue:(id)value toClass:(Class)toClass;
{
    id result = original_coerceValue_toClass(self, _cmd, value, toClass);
    NSLog(@"Coerce <%@:%p> %@ to class %@ -> %@ %@", NSStringFromClass([value class]), value, value, NSStringFromClass(toClass), NSStringFromClass([result class]), result);
    return result;
}

@end

#endif

