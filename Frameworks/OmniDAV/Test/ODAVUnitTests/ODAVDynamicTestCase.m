// Copyright 2008-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ODAVConcreteTestCase.h"

#import <OmniDAV/ODAVConformanceTest.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <objc/runtime.h>

// This runs the tests that are included in the framework for pre-flighting servers to make sure they do WebDAV according to the spec (at least to the level we need).
@interface ODAVDynamicTestCase : ODAVConcreteTestCase
@property(nonatomic,readonly) ODAVConformanceTest *conformanceTest;
@end

@implementation ODAVDynamicTestCase

static void _addTestMethods(Class cls)
{
    // Add instance methods to ourself for any -testFoo: methods on ODAVConformanceTest. We use this approach so that OCUnit logs reasonable names for the tests (though Xcode sadly doesn't let us turn on/off individual tests).
    
    Method testMethodSentinel = class_getInstanceMethod(cls, @selector(_testMethodSentinel));
    const char *testEncoding = method_getTypeEncoding(testMethodSentinel);
    
    [ODAVConformanceTest eachTest:^(SEL methodSelector, ODAVConformanceTestImp methodImp, ODAVConformanceTestProgress progress){
        IMP imp = imp_implementationWithBlock(^(ODAVDynamicTestCase *self){
            __autoreleasing NSError *error;
            if (!methodImp(self.conformanceTest, methodSelector, &error)) {
                XCTFail(@"Test returned error: %@", [error toPropertyList]);
            }
        });
        
        NSString *testMethodName = [NSStringFromSelector(methodSelector) stringByRemovingSuffix:@":"];
        SEL testMethodSelector = NSSelectorFromString(testMethodName);
        
        if (!class_addMethod(cls, testMethodSelector, imp, testEncoding))
            NSLog(@"*** Failed to add method for %@ ***", testMethodName);
    }];
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    // Function just renames self->cls so that argument to imp_implementationWithBlock can take 'self' w/o a shadow warning.
    _addTestMethods(self);
}

+ (XCTestSuite *)defaultTestSuite;
{
    return [super defaultTestSuite];
}

- (void)setUp;
{
    [super setUp];
    
    _conformanceTest = [[ODAVConformanceTest alloc] initWithConnection:self.connection baseURL:self.remoteBaseURL];
}

- (void)tearDown;
{
    _conformanceTest = nil;
    [super tearDown];
}

- (void)_testMethodSentinel;
{
    XCTFail(@"shouldn't be called");
}
- (BOOL)_testWithErrorTypeEncodingSentinel:(NSError **)outError;
{
    return YES;
}

@end
