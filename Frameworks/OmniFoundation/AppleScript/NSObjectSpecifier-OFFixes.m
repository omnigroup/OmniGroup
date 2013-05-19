// Copyright 2002-2005, 2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if 0 // Disabled -- uses undocumented APIs
#import <Foundation/NSScriptObjectSpecifiers.h>

#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSAppleEventDescriptor.h>

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

+ (void)performPosing
{
    originalObjectsByEvaluatingWithContainers = (void *)OBReplaceMethodImplementationWithSelector(self,  @selector(objectsByEvaluatingWithContainers:), @selector(replacement_objectsByEvaluatingWithContainers:));
    originalPutKeyFormAndDataInRecord = (typeof(originalPutKeyFormAndDataInRecord))OBReplaceMethodImplementationWithSelector(self,  @selector(_putKeyFormAndDataInRecord:), @selector(replacement_putKeyFormAndDataInRecord:));
}

@end

@interface NSAppleEventDescriptor (JaguarAPI)
+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)signedInt;
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)string;
+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)enumerator;
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)descriptorType bytes:(const void *)bytes length:(unsigned int)byteCount;
@end


/* This allows us to convert an NSSpecifierTest to its corresponding typeCompDescriptor. */
@implementation NSSpecifierTest (OFFixes)

- (NSAppleEventDescriptor *)fixed_asDescriptor
{
    NSAppleEventDescriptor *seld, *testd, *obj2;
    OSType comparisonOp;

    // Radar 6964125: NSSpecifierTest needs accessors
    NSScriptObjectSpecifier *objectSpecifier = [self valueForKey:@"object1"];
    id testObject = [self valueForKey:@"object2"];
    NSTestComparisonOperation comparisonOperator = [[self valueForKey:@"comparisonOperator"] intValue];
    
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
    if ([testObject respondsToSelector:@selector(_asDescriptor)])
        obj2 = [testObject _asDescriptor];
    else if ([testObject isKindOfClass:[NSNumber class]])
        obj2 = [NSAppleEventDescriptor descriptorWithInt32:[testObject intValue]];
    else if ([testObject isKindOfClass:[NSString class]])
        obj2 = [NSAppleEventDescriptor descriptorWithString:testObject];
    else
        return nil;
    
    testd = [[NSAppleEventDescriptor alloc] initRecordDescriptor];
    [testd setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:comparisonOp] forKeyword:keyAECompOperator];
    [testd setDescriptor:[objectSpecifier _asDescriptor] forKeyword:keyAEObject1];
    [testd setDescriptor:obj2 forKeyword:keyAEObject2];

    seld = [testd coerceToDescriptorType:typeCompDescriptor];
    [testd autorelease];
    return seld;
}

@end
#endif
