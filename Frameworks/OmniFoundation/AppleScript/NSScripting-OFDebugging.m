// Copyright 2000-2013 Omni Development, Inc. All rights reserved.

RCS_ID("$Id$");

/*
 Various hacks into the Cocoa scripting support to make debugging easier.
 */

#if 1 && defined(DEBUG)

#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSScriptObjectSpecifiers.h>

@interface NSClassDescription (OFDebugging)
@end
@implementation NSClassDescription (OFDebugging)

static void (*original_NSClassDescription_registerClassDescriptionForClass)(Class self, SEL _cmd, NSClassDescription *description, Class aClass);

+ (void)performPosing;
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;
    
    original_NSClassDescription_registerClassDescriptionForClass = (typeof(original_NSClassDescription_registerClassDescriptionForClass))OBReplaceMethodImplementationWithSelector(object_getClass(self), @selector(registerClassDescription:forClass:), @selector(replacement_registerClassDescription:forClass:));
}

+ (void)replacement_registerClassDescription:(NSClassDescription *)description forClass:(Class)aClass;
{
    NSLog(@"REGISTER %@ -> %p", aClass, description);
    original_NSClassDescription_registerClassDescriptionForClass(self, _cmd, description, aClass);
}

@end

@interface NSPositionalSpecifier (OFDebugging)
@end
@implementation NSPositionalSpecifier (OFDebugging)

static BOOL (*original_NSPositionalSpecifier_describedClass_isSubclassOfClass)(Class self, SEL _cmd, id cls, Class superclass) = NULL;

+ (void)performPosing;
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;
    
    original_NSPositionalSpecifier_describedClass_isSubclassOfClass = (typeof(original_NSPositionalSpecifier_describedClass_isSubclassOfClass))OBReplaceClassMethodImplementationWithSelector(self, @selector(_describedClass:isSubclassOfClass:), @selector(_replacement_describedClass:isSubclassOfClass:));
}

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

+ (void)performPosing;
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;

    original_NSScriptObjectSpecifier_objectsByEvaluatingSpecifier = (typeof(original_NSScriptObjectSpecifier_objectsByEvaluatingSpecifier))OBReplaceMethodImplementationWithSelector(self, @selector(objectsByEvaluatingSpecifier), @selector(replacement_objectsByEvaluatingSpecifier));
}

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

+ (void)performPosing;
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;

    original_NSIndexSpecifier_objectsByEvaluatingSpecifier = (typeof(original_NSIndexSpecifier_objectsByEvaluatingSpecifier))OBReplaceMethodImplementationWithSelector(self, @selector(objectsByEvaluatingSpecifier), @selector(replacement_objectsByEvaluatingSpecifier));
    original_objectsByEvaluatingWithContainers = (typeof(original_objectsByEvaluatingWithContainers))OBReplaceMethodImplementationWithSelector(self, @selector(objectsByEvaluatingWithContainers:), @selector(replacement_objectsByEvaluatingWithContainers:));
}

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

+ (void)performPosing;
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;

    original_NSScriptClassDescription_classDescriptionForClass = (typeof(original_NSScriptClassDescription_classDescriptionForClass))OBReplaceMethodImplementationWithSelector(object_getClass(self), @selector(classDescriptionForClass:), @selector(replacement_classDescriptionForClass:));
    original_NSScriptClassDescription_classDescriptionForKey = (typeof(original_NSScriptClassDescription_classDescriptionForKey))OBReplaceMethodImplementationWithSelector(self, @selector(classDescriptionForKey:), @selector(replacement_classDescriptionForKey:));
    original_NSScriptClassDescription_keyWithAppleEventCode = (typeof(original_NSScriptClassDescription_keyWithAppleEventCode))OBReplaceMethodImplementationWithSelector(self, @selector(keyWithAppleEventCode:), @selector(replacement_keyWithAppleEventCode:));
    original_NSScriptClassDescription_supportsCommand = (typeof(original_NSScriptClassDescription_supportsCommand))OBReplaceMethodImplementationWithSelector(self, @selector(supportsCommand:), @selector(replacement_supportsCommand:));
    original_NSScriptClassDescription_selectorForCommand = (typeof(original_NSScriptClassDescription_selectorForCommand))OBReplaceMethodImplementationWithSelector(self, @selector(selectorForCommand:), @selector(replacement_selectorForCommand:));
}

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

+ (void)performPosing;
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"NSScriptingDebugLogLevel"] == 0)
        return;
    
    original_coerceValue_toClass = (typeof(original_coerceValue_toClass))OBReplaceMethodImplementationWithSelector(self, @selector(coerceValue:toClass:), @selector(replacement_coerceValue:toClass:));
}

- (id)replacement_coerceValue:(id)value toClass:(Class)toClass;
{
    id result = original_coerceValue_toClass(self, _cmd, value, toClass);
    NSLog(@"Coerce <%@:%p> %@ to class %@ -> %@ %@", NSStringFromClass([value class]), value, value, NSStringFromClass(toClass), NSStringFromClass([result class]), result);
    return result;
}

@end

#endif

