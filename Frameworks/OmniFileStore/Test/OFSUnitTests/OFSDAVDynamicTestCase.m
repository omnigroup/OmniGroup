// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFSDAVTestCase.h"

#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSDAVConformanceTest.h>
#import <objc/runtime.h>

// This runs the tests that are included in the framework for pre-flighting servers to make sure they do WebDAV according to the spec (at least to the level we need).
@interface OFSDAVDynamicTestCase : OFSDAVTestCase <OFSFileManagerDelegate>
@property(nonatomic,readonly) OFSDAVConformanceTest *conformanceTest;
@end

@implementation OFSDAVDynamicTestCase

static void _addTestMethods(Class cls)
{
    // Add instance methods to ourself for any -testFoo: methods on OFSDAVConformanceTest. We use this approach so that OCUnit logs reasonable names for the tests (though Xcode sadly doesn't let us turn on/off individual tests).
    
    Method testMethodSentinel = class_getInstanceMethod(cls, @selector(_testMethodSentinel));
    const char *testEncoding = method_getTypeEncoding(testMethodSentinel);
    
    [OFSDAVConformanceTest eachTest:^(SEL methodSelector, OFSDAVConformanceTestImp methodImp){
        IMP imp = imp_implementationWithBlock(^(OFSDAVDynamicTestCase *self){
            __autoreleasing NSError *error;
            if (!methodImp(self.conformanceTest, methodSelector, &error)) {
                STFail(@"Test returned error: %@", [error toPropertyList]);
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

+ (id)defaultTestSuite;
{
    return [super defaultTestSuite];
}

- (void)setUp;
{
    [super setUp];
    
    _conformanceTest = [[OFSDAVConformanceTest alloc] initWithFileManager:self.fileManager];
}

- (void)tearDown;
{
    _conformanceTest = nil;
    [super tearDown];
}

- (void)_testMethodSentinel;
{
    STFail(@"shouldn't be called");
}
- (BOOL)_testWithErrorTypeEncodingSentinel:(NSError **)outError;
{
    return YES;
}

@end
