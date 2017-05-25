// Copyright 2002-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSScriptObjectSpecifiers.h>

#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSScriptClassDescription.h>

RCS_ID("$Id$");

/* Private methods used when converting an NSObjectSpecifier to an NSAppleEventDecriptor (10.2.+ only) */
@interface NSScriptObjectSpecifier (NSPrivateAPI)
- (NSAppleEventDescriptor *)_asDescriptor;
- (BOOL)_putKeyFormAndDataInRecord:(NSAppleEventDescriptor *)aedesc;
@end

@interface NSSpecifierTest (OFFixes)
- (NSAppleEventDescriptor *)fixed_asDescriptor;
@end

@implementation NSWhoseSpecifier (OFFixes)

static id (*originalObjectsByEvaluatingWithContainers)(id self, SEL cmd, id containers) = NULL;
static BOOL (*originalPutKeyFormAndDataInRecord)(id self, SEL _cmd, NSAppleEventDescriptor *aedesc) = NULL;

// Apple's code incorrectly returns nil instead of an empty array if there are no matches.
// This is Apple bug #3935660, BugSnacker bug #19944 and #19364.
- (id)replacement_objectsByEvaluatingWithContainers:(id)containers;
{
    id result = originalObjectsByEvaluatingWithContainers(self, _cmd, containers);
    
    if (result == nil) {
	// <bug://bugs/25410> Don't return empty arrays for whose specifiers that should return a single item
	// Some 'whose' specifiers should return arrays and some shouldn't.  Don't return an array if we are trying to get a single item.
	NSWhoseSubelementIdentifier startSubelement = [self startSubelementIdentifier];
	NSWhoseSubelementIdentifier endSubelement = [self endSubelementIdentifier];
	
	// Requested a single item (start==index and end==index would probably be interpreted as a length 1 array)
	if ((startSubelement == NSIndexSubelement || startSubelement == NSMiddleSubelement || startSubelement == NSRandomSubelement) &&
	    endSubelement == NSNoSubelement)
	    return nil;
		
        //NSLog(@"[#19944] fixup for %@", [self description]);
        result = [NSArray array];
    }
    
    return result;
}


- (BOOL)replacement_putKeyFormAndDataInRecord:(NSAppleEventDescriptor *)aedesc
{
    BOOL ok;
    NSAppleEventDescriptor *testClause, *ordinalAny;
    const FourCharCode ordinalAnyContents = kAEAny;
    
    ok = originalPutKeyFormAndDataInRecord(self, _cmd, aedesc);
    
    /* The buggy code does not set anything for the seld keyword. If there is data for that keyword, assume we're running with a non-broken version of Foundation. */
    /* Note: Testing shows that this bug is still here as of NSFoundationVersion 500.56, OS version 10.3.7 (7S215)   [wiml 25 January 2005] */
    if (!ok || [aedesc descriptorForKeyword:keyAEKeyData] != nil)
        return ok;
    
    /* Fix for Apple bug #3137439: NSWhoseDescriptor does not correctly handle the creation of an AEDesc. We create and return a correct descriptor (actually, a nested index/test descriptor). */
    
    /* Since this code is only here as a workaround until Apple fixes their bug, I'm not implementing the full set of possibilities here, only the cases I expect to encounter. */
    if (![[self test] isKindOfClass:[NSSpecifierTest class]])
        return NO;
    
    /* Although there is a descriptor form of formWhose, it apparently does not work to return one of these directly in an apple event; we must only return the equivalent nested formIndex and formTest. */
    testClause = [[NSAppleEventDescriptor alloc] initRecordDescriptor];
    
    [testClause setDescriptor:[aedesc descriptorForKeyword:keyAEDesiredClass] forKeyword:keyAEDesiredClass];
    [testClause setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:formTest] forKeyword:keyAEKeyForm];
    [testClause setDescriptor:[(NSSpecifierTest *)[self test] fixed_asDescriptor] forKeyword:keyAEKeyData];
    [testClause setDescriptor:[aedesc descriptorForKeyword:keyAEContainer] forKeyword:keyAEContainer];
    
    /* This isn't at all correct for the general case; it just handles the one case I'm interested in. */
    [aedesc setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:formAbsolutePosition] forKeyword:keyAEKeyForm];
    ordinalAny = [NSAppleEventDescriptor descriptorWithDescriptorType:typeAbsoluteOrdinal bytes:&ordinalAnyContents length:4];
    [aedesc setDescriptor:ordinalAny forKeyword:keyAEKeyData];
    [aedesc setDescriptor:[testClause coerceToDescriptorType:typeObjectSpecifier] forKeyword:keyAEContainer];
    
    [testClause release];
    
    return ok;
}

OBPerformPosing(^{
    Class self = objc_getClass("NSWhoseSpecifier");

    originalObjectsByEvaluatingWithContainers = (void *)OBReplaceMethodImplementationWithSelector(self,  @selector(objectsByEvaluatingWithContainers:), @selector(replacement_objectsByEvaluatingWithContainers:));
    originalPutKeyFormAndDataInRecord = (typeof(originalPutKeyFormAndDataInRecord))OBReplaceMethodImplementationWithSelector(self,  @selector(_putKeyFormAndDataInRecord:), @selector(replacement_putKeyFormAndDataInRecord:));
});

@end


/* This allows us to convert an NSSpecifierTest to its corresponding typeCompDescriptor. */
@implementation NSSpecifierTest (OFFixes)

- (NSAppleEventDescriptor *)fixed_asDescriptor
{
    // Radar 6964125: NSSpecifierTest needs accessors
    NSScriptObjectSpecifier *objectSpecifier = [self valueForKey:@"object1"];
    id testObject = [self valueForKey:@"object2"];
    NSTestComparisonOperation comparisonOperator = [[self valueForKey:@"comparisonOperator"] intValue];
    
    OSType comparisonOp;
    switch (comparisonOperator) {
        case NSEqualToComparison: comparisonOp = kAEEquals; break;
        case NSLessThanOrEqualToComparison: comparisonOp = kAELessThanEquals; break;
        case NSLessThanComparison: comparisonOp = kAELessThan; break;
        case NSGreaterThanOrEqualToComparison: comparisonOp = kAEGreaterThanEquals; break;
        case NSGreaterThanComparison: comparisonOp = kAEGreaterThan; break;
        case NSBeginsWithComparison: comparisonOp = kAEBeginsWith; break;
        case NSEndsWithComparison: comparisonOp = kAEEndsWith; break;
        case NSContainsComparison: comparisonOp = kAEContains; break;
        default:
            return nil;
    }

    /* Half-assed conversion of testObject into an AEDesc */
    NSAppleEventDescriptor *obj2;
    if ([testObject respondsToSelector:@selector(_asDescriptor)])
        obj2 = [testObject _asDescriptor];
    else if ([testObject isKindOfClass:[NSNumber class]])
        obj2 = [NSAppleEventDescriptor descriptorWithInt32:[testObject intValue]];
    else if ([testObject isKindOfClass:[NSString class]])
        obj2 = [NSAppleEventDescriptor descriptorWithString:testObject];
    else
        return nil;
    
    NSAppleEventDescriptor *testd = [[[NSAppleEventDescriptor alloc] initRecordDescriptor] autorelease];
    [testd setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:comparisonOp] forKeyword:keyAECompOperator];
    [testd setDescriptor:[objectSpecifier _asDescriptor] forKeyword:keyAEObject1];
    [testd setDescriptor:obj2 forKeyword:keyAEObject2];

    return [testd coerceToDescriptorType:typeCompDescriptor];
}

@end


#if 1 && defined(DEBUG)

// This produces a false positive in at least some cases. In OmniFocus, for example, "tell MyDocument / duplicate every inbox task whose name is "a" to end of inbox tasks / end". We get called with a nil container and the 'inbox task' class description. Presumably they call back later and set the container. If we want to bring this back, we'd maybe want to override the evaluation methods instead...
#if 0
// Add assertions on initializer arguments for the object specifier classes. In at least one, case 10.9 didn't catch a bad argument and silently produced corrupt object specifier AppleEvents. 15181769: NSUniqueIDSpecifier should warn on bad input instead of producing garbage output

static id (*original_NSScriptObjectSpecifier_initWithContainerClassDescription_containerSpecifier_property)(NSScriptObjectSpecifier *self, SEL _cmd, NSScriptClassDescription *classDesc, NSScriptObjectSpecifier *container, NSString *key) = NULL;
static id replacement_NSScriptObjectSpecifier_initWithContainerClassDescription_containerSpecifier_property(NSScriptObjectSpecifier *self, SEL _cmd, NSScriptClassDescription *classDesc, NSScriptObjectSpecifier *container, NSString *key)
{
    OBPRECONDITION(container || classDesc.appleEventCode == 'capp');
    OBPRECONDITION(key);
    OBPRECONDITION([classDesc classDescriptionForKey:key]/*element*/ || [classDesc typeForKey:key]/*property*/, "No class description or type registered for the key \"%@\" of class description \"%@\"", key, classDesc);
    
    return original_NSScriptObjectSpecifier_initWithContainerClassDescription_containerSpecifier_property(self, _cmd, classDesc, container, key);
}
#endif

static id (*original_NSUniqueIDSpecifier_initWithContainerClassDescription_containerSpecifier_key_uniqueID)(NSUniqueIDSpecifier *self, SEL _cmd, NSScriptClassDescription *classDesc, NSScriptObjectSpecifier *container, NSString *key, id uniqueID) = NULL;
static id replacement_NSUniqueIDSpecifier_initWithContainerClassDescription_containerSpecifier_key_uniqueID(NSUniqueIDSpecifier *self, SEL _cmd, NSScriptClassDescription *classDesc, NSScriptObjectSpecifier *container, NSString *key, id uniqueID)
{
    OBPRECONDITION(classDesc);
    OBPRECONDITION(container || classDesc.appleEventCode == 'capp');
    OBPRECONDITION(key);
    OBPRECONDITION([classDesc classDescriptionForKey:key]);
    OBPRECONDITION(uniqueID);
    
    return original_NSUniqueIDSpecifier_initWithContainerClassDescription_containerSpecifier_key_uniqueID(self, _cmd, classDesc, container, key, uniqueID);
}

#define REPLACE(f, cls, sel) original_ ## cls ## _ ## f = (typeof(original_ ## cls ## _ ## f))OBReplaceMethodImplementation([cls class], @selector(sel), (IMP)replacement_ ## cls ## _ ## f)

static void initSpecifierAssertions(void) __attribute__((constructor));
static void initSpecifierAssertions(void)
{
//    REPLACE(initWithContainerClassDescription_containerSpecifier_property, NSScriptObjectSpecifier, initWithContainerClassDescription:containerSpecifier:key:);
    REPLACE(initWithContainerClassDescription_containerSpecifier_key_uniqueID, NSUniqueIDSpecifier, initWithContainerClassDescription:containerSpecifier:key:uniqueID:);
}


#endif
