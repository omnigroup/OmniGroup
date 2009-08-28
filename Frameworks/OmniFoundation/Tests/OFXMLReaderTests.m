// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFXMLReader.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniBase/NSError-OBExtensions.h>

@interface OFXMLReaderTests : OFTestCase
@end

@implementation OFXMLReaderTests

- (void)testSkippingEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><empty1/><empty2/></root>";
    
    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    shouldBeEqual([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"empty1");
    
    OBShouldNotError([reader skipCurrentElement:&error]);
    shouldBeEqual([reader elementQName].name, @"empty2");
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"empty2");
}

- (void)testCloseElementSkippingEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><interior><empty1/><empty2/></interior><follow/></root>";
    
    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    shouldBeEqual([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"interior");
    
    OBShouldNotError([reader openElement:&error]);

    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"empty1");
    
    OBShouldNotError([reader closeElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"follow");
}

- (void)testCloseElementSkippingMultipleEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><interior><empty1/><empty2/></interior><follow/></root>";
    
    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    shouldBeEqual([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"interior");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader closeElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"follow");
}

- (void)testOpenEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><empty1/><empty2/></root>";
    
    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    shouldBeEqual([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"empty1");
    
    OBShouldNotError([reader openElement:&error]);
    OBShouldNotError([reader closeElement:&error]);

    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"empty2");
}

- (void)testCopyStringWithEmbeddedElements;
{
    NSError *error = nil;
    NSString *xml = @"<root>a<empty1/>b<foo>c</foo></root>";

    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    NSString *str = nil;
    OBShouldNotError([reader copyStringContentsToEndOfElement:&str error:&error]);
    
    shouldBeEqual(str, @"abc");

    [str release];
}

static void _testReadBoolContents(OFXMLReaderTests *self, SEL _cmd, NSString *inner, BOOL defaultValue, BOOL expectedValue)
{
    NSError *error = nil;
    NSString *xml = [NSString stringWithFormat:@"<root>%@<foo/></root>", inner];
    
    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]);
    
    BOOL value = ~expectedValue; // make sure it gets written to.
    
    OBShouldNotError([reader readBoolContentsOfElement:&value defaultValue:defaultValue error:&error]);
    
    STAssertEquals(value, expectedValue, nil);
    
    // Should have skipped the bool element.
    OFXMLQName *name = nil;
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"foo");
}

- (void)testReadBoolContents;
{
    // empty nodes should yield default values
    _testReadBoolContents(self, _cmd, @"<bool/>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool/>", YES, YES);
    
    // start/end nodes should be the same as empty
    _testReadBoolContents(self, _cmd, @"<bool></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool></bool>", YES, YES);

    // nodes with only whitespace should be the same as empty
    _testReadBoolContents(self, _cmd, @"<bool> </bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool> </bool>", YES, YES);
    
    // explicit true/false strings should give their values.
    _testReadBoolContents(self, _cmd, @"<bool>true</bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool>true</bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool>false</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool>false</bool>", YES, NO);
    
    // 1/0 are supposed to work too.
    _testReadBoolContents(self, _cmd, @"<bool>1</bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool>1</bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool>0</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool>0</bool>", YES, NO);
    
    // The leading space makes this not exactly match "true" or "1"
    _testReadBoolContents(self, _cmd, @"<bool> true</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool> true</bool>", YES, NO);
    _testReadBoolContents(self, _cmd, @"<bool> 1</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool> 1</bool>", YES, NO);
    
    // Empty CDATA should be the same as empty
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[]]></bool>", YES, YES);

    // CDATA with space in it isn't considered whitespace and is directly compared to "true" and "1".  Don't do that, silly person.
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[ ]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[ ]]></bool>", YES, NO);
    
    // More CDATA versions of stuff above
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[true]]></bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[true]]></bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[false]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[false]]></bool>", YES, NO);
    
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[1]]></bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[1]]></bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[0]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[0]]></bool>", YES, NO);
}

static void _testReadLongContents(OFXMLReaderTests *self, SEL _cmd, NSString *inner, long defaultValue, long expectedValue)
{
    NSError *error = nil;
    NSString *xml = [NSString stringWithFormat:@"<root>%@<foo/></root>", inner];
    
    OFXMLReader *reader = [[[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error] autorelease];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]);
    
    long value = ~expectedValue; // make sure it gets written to.
    
    OBShouldNotError([reader readLongContentsOfElement:&value defaultValue:defaultValue error:&error]);
    
    STAssertEquals(value, expectedValue, nil);
    
    // Should have skipped the long element.
    OFXMLQName *name = nil;
    OBShouldNotError([reader findNextElement:&name error:&error]);
    shouldBeEqual(name.name, @"foo");
}

- (void)testReadLongContents;
{
    // empty nodes should yield default values
    _testReadLongContents(self, _cmd, @"<long/>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long/>", 13, 13);
    
    // start/end nodes should be the same as empty
    _testReadLongContents(self, _cmd, @"<long></long>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long></long>", 13, 13);
    
    // nodes with only whitespace should be the same as empty
    _testReadLongContents(self, _cmd, @"<long> </long>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long> </long>", 13, 13);
    
    // explicit longs should give their values.
    _testReadLongContents(self, _cmd, @"<long>123</long>", 13, 123);
    _testReadLongContents(self, _cmd, @"<long>0</long>", 13, 0);
    _testReadLongContents(self, _cmd, @"<long>-1</long>", 13, -1);
    
    // leading/trailing whitespace is allowed
    _testReadLongContents(self, _cmd, @"<long> 567</long>", 13, 567);
    _testReadLongContents(self, _cmd, @"<long>678 </long>", 13, 678);

    // Empty CDATA should be the same as empty
    _testReadLongContents(self, _cmd, @"<long><![CDATA[]]></long>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[]]></long>", 13, 13);
    
    // CDATA with space in it isn't considered whitespace and is directly passed to strtol. Don't do that, silly person.
    _testReadLongContents(self, _cmd, @"<long><![CDATA[ ]]></long>", 13, 0);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[ ]]></long>", 13, 0);
    
    // More CDATA versions of stuff above
    _testReadLongContents(self, _cmd, @"<long><![CDATA[123]]></long>", 13, 123);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[0]]></long>", 13, 0);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[-1]]></long>", 13, -1);
}

@end
