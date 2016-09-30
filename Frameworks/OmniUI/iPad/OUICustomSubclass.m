// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUICustomSubclass.h>

RCS_ID("$Id$");

static NSDictionary *OriginalClassNameToSubclassName = nil;
static NSDictionary *CustomSubclassNameToClassName = nil;

static void _OUILoadCustomClassMapping(void)
{
    if (OriginalClassNameToSubclassName)
        return;
    
    OriginalClassNameToSubclassName = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUICustomClass"] copy];
    if (!OriginalClassNameToSubclassName)
        OriginalClassNameToSubclassName = [[NSDictionary alloc] init]; // For early out later
    
    NSMutableDictionary *inverseDictionary = [NSMutableDictionary dictionary];
    for (NSString *sourceClassName in OriginalClassNameToSubclassName) {
        NSString *destinationClassName = [OriginalClassNameToSubclassName objectForKey:sourceClassName];
        
        // Some sanity checks. Must map to subclasses. Must be one-to-one with no cycles.
        // Also note that we don't handle things like A : B : C with a map of A->C. If B is allocated you'll just get a B.
#ifdef OMNI_ASSERTIONS_ON
        Class sourceClass = NSClassFromString(sourceClassName);
        OBASSERT(sourceClass);
        
        Class destinationClass = NSClassFromString(destinationClassName);
        OBASSERT(destinationClass);
        OBASSERT(OFNOTEQUAL(sourceClassName, destinationClassName));
        OBASSERT(OBClassIsSubclassOfClass(destinationClass, sourceClass));
        OBASSERT([OriginalClassNameToSubclassName objectForKey:destinationClassName] == nil);
        OBASSERT([inverseDictionary objectForKey:destinationClassName] == nil);
#endif
        [inverseDictionary setObject:sourceClassName forKey:destinationClassName];
    }
    
    CustomSubclassNameToClassName = [inverseDictionary copy];
}

id _OUIAllocateCustomClass(Class self, NSZone *zone)
{
    // Allow Info.plist based class substitution for inspector slices since applications may want to customize slices
    _OUILoadCustomClassMapping();
    NSString *sourceClassName = NSStringFromClass(self);
    NSString *destinationClassName = [OriginalClassNameToSubclassName objectForKey:sourceClassName];
    
    if (destinationClassName) {
        // we're depending on the sanity checks done above...
        return [NSClassFromString(destinationClassName) allocWithZone:zone];
    }
    
    return nil;
}

// Useful for the default +nibName on UIViewControllers
NSString *OUICustomClassOriginalClassName(Class cls)
{
    OBPRECONDITION(cls);
    
    NSString *className = NSStringFromClass(cls);
    NSString *originalClassName = [CustomSubclassNameToClassName objectForKey:className];
    if (originalClassName)
        return originalClassName;
    return className;
}
