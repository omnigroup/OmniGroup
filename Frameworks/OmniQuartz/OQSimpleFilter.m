// Copyright 2005-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQSimpleFilter.h>

RCS_ID("$Id$");

static NSMutableDictionary *classToKernel = nil;

@implementation OQSimpleFilter

+ (void)initialize
{
    if (self == [OQSimpleFilter class]) {
	classToKernel = [[NSMutableDictionary alloc] init];
	return;
    }
    OBASSERT(classToKernel); // superclasses should be initialized first
    
    // Subclasses might not be linked against a debug copy of this framework (3rd parties).  So, check at runtime.
    NSString *className = NSStringFromClass(self);
    if (![self conformsToProtocol:@protocol(OQConcreteSimpleFilter)]) {
	// Don't log here (we'll log down in +fitlerWithName: if they try to ask for something that didn't get registered)
	// This allows us to have abstract subclasses of OQSimpleFilter
	//NSLog(@"The subclass '%@' OQSimpleFilter does not conform to the 'OQConcreteSimpleFilter' protocol!", className);
	return;
    }
    
    NSBundle *bundle = [NSBundle bundleForClass:self];
    NSString *kernelSourceFileName = [self filterSourceFileName];
    NSString *kernelSourcePath = [bundle pathForResource:kernelSourceFileName ofType:@"cikernel"];
    if (!kernelSourcePath) {
	NSLog(@"Unable to locate '%@.cikernel' for filter class '%@' in bundle '%@'", kernelSourceFileName, className, bundle);
	return;
    }
    
    NSError *error = nil;
    NSString *kernelSource = [[NSString alloc] initWithContentsOfFile:kernelSourcePath encoding:NSUTF8StringEncoding error:&error];
    if (!kernelSource) {
	NSLog(@"Unable to load source for kernel for \"%@\" from \"%@\": %@", className, kernelSource, [error toPropertyList]);
	return;
    }
    
    NSArray *kernels = [CIKernel kernelsWithString:kernelSource]; 
    OBASSERT([kernels count] == 1);
    
    CIKernel *kernel = [kernels objectAtIndex:0];
    [kernelSource release];
    if (!kernel) {
	NSLog(@"Unable to create kernel from source at '%@'", kernelSourcePath);
	return;
    }
    [classToKernel setObject:kernel forKey:(id)self];
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
	className, kCIAttributeFilterDisplayName,
	[NSArray arrayWithObject:@"OmniMagicWand Internal"], kCIAttributeFilterCategories, nil];
    
    id constructor = (id <CIFilterConstructor>)self; // OBFinishPorting: <bug:///147891> (iOS-OmniOutliner Engineering: +[OQSimpleFilter initialize] - Can't declare that the class implements CIFilterConstructor (just +filterWithName:))
    
    [CIFilter registerFilterName:className  
		     constructor:constructor
		 classAttributes:attributes];
}

+ (CIFilter *)filterWithName:(NSString *)name
{
    Class cls = NSClassFromString(name);
    if (!cls) {
	NSLog(@"%s: Unable to find class '%@'", __PRETTY_FUNCTION__, name);
	return nil;
    }
    
    if (![cls kernel]) {
	NSLog(@"%s: No kernel registered for class '%@' (perhaps it didn't conform to OQConcreteSimpleFilter)", __PRETTY_FUNCTION__, name);
	return nil;
    }
    
    return [[[cls alloc] init] autorelease];
}

+ (CIKernel *)kernel;
{
    CIKernel *kernel = [classToKernel objectForKey:self];
    OBASSERT(kernel);
    return kernel;
}

+ (NSString *)filterSourceFileName;
{
    return NSStringFromClass(self);
}

@end
