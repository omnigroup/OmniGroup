// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/OmniDataObjects.h>
#import <OmniBase/objc.h>

#import "ODOPerf_CoreData.h"
#import "ODOPerf_ODO.h"

RCS_ID("$Id$")

@implementation ODOPerf

static NSUInteger Tries;
static NSUInteger StepCount;
static BOOL WithODO;
static BOOL WithCD;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithUnsignedInteger:5], @"Tries",
                                [NSNumber numberWithUnsignedInteger:100000], @"StepCount",
                                [NSNumber numberWithBool:YES], @"WithODO",
                                [NSNumber numberWithBool:YES], @"WithCD",
                                nil]];
     
    StepCount = [[defaults objectForKey:@"StepCount"] unsignedIntValue]; // Argh.  NSString doesn't have -unsignedIntegerValue.
    Tries = [[defaults objectForKey:@"Tries"] unsignedIntValue]; // Argh.  NSString doesn't have -unsignedIntegerValue.
    WithODO = [defaults boolForKey:@"WithODO"];
    WithCD = [defaults boolForKey:@"WithCD"];
    
    if (!WithODO && !WithCD) {
        NSLog(@"Need to turn on at least one of WithODO or WithCD");
        exit(1);
    }
}

+ (NSUInteger)stepCount;
{
    return StepCount;
}

static NSString * const PerfPrefix = @"perf_";

+ (void)gatherTestNames:(NSMutableSet *)testNames;
{
    NSString *requestedTestNames = [[NSUserDefaults standardUserDefaults] stringForKey:@"TestNames"];
    if (requestedTestNames) {
        [testNames addObjectsFromArray:[requestedTestNames componentsSeparatedByString:@","]];
        return;
    }
    
    unsigned int methodIndex = 0;
    Method *methods = class_copyMethodList(self, &methodIndex);
    while (methodIndex--) {
        NSString *name = NSStringFromSelector(method_getName(methods[methodIndex]));
        
        if ([name hasPrefix:PerfPrefix]) {
            name = [name substringFromIndex:[PerfPrefix length]];
            [testNames addObject:name];
        }
    }
}

static CFTimeInterval bestTime(BOOL enabled, Class cls, NSString *name)
{
    CFTimeInterval best = -1;
    if (enabled) {
        for (NSUInteger try = 0; try < Tries; try++) {
            CFTimeInterval interval;
            ODOPerf *perf = [[cls alloc] initWithName:name];
            if ([perf runTestNamed:name]) {
                interval = [perf elapsedTime];
                NSLog(@"  try:%d %@:%g", try, NSStringFromClass(cls), interval);
                if (best < 0 || best > interval)
                    best = interval;
            }
            [perf release];
        }
    }
    return best;
}

+ (void)run;
{
    NSMutableSet *allTestNames = [NSMutableSet set];
    [ODOPerf_ODO gatherTestNames:allTestNames];
    [ODOPerf_CoreData gatherTestNames:allTestNames];
    NSArray *testNames = [[allTestNames allObjects] sortedArrayUsingSelector:@selector(compare:)];

    unsigned int testIndex, testCount = [testNames count];
    NSLog(@"running %d tests...", testCount);
    
    for (testIndex = 0; testIndex < testCount; testIndex++) {
        NSString *name = [testNames objectAtIndex:testIndex];
        NSLog(@"Test: %@", name);
        
        CFTimeInterval odoTime = bestTime(WithODO, [ODOPerf_ODO class], name);
        CFTimeInterval cdTime = bestTime(WithCD, [ODOPerf_CoreData class], name);
        
        if (WithODO && WithCD)
            NSLog(@"  ODO:%g CD:%g %%:%g -- %@", odoTime, cdTime, 100.0 * (odoTime / cdTime), name);
        else if (WithODO)
            NSLog(@"  ODO:%g -- %@", odoTime, name);
        else
            NSLog(@"  CD:%g -- %@", cdTime, name);
    }
}

- initWithName:(NSString *)name;
{
    _name = [name copy];
    return self;
}

- (void)dealloc;
{
    [_name release];
    [super dealloc];
}

@synthesize name = _name;

- (NSString *)storePath;
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSStringFromClass([self class]) stringByAppendingFormat:@"-%@", self.name]];
}

- (BOOL)runTestNamed:(NSString *)name;
{
    SEL sel = NSSelectorFromString([PerfPrefix stringByAppendingString:name]);
    if (![self respondsToSelector:sel]) {
        NSLog(@"Missing a version of '%@' -- Method -[%@ %@] not found!", name, NSStringFromClass([self class]), NSStringFromSelector(sel));
        return NO;
    }
    
    _start = CFAbsoluteTimeGetCurrent();
    {
        // Count garbage generated against the time of the test.  Setup garbage should be put in its own pool.
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [self performSelector:sel];
        [pool release];
    }
    _stop = CFAbsoluteTimeGetCurrent();
    return YES;
}

- (void)setupCompleted;
{
    // Restart the start time if the test has startup time.
    _start = CFAbsoluteTimeGetCurrent();
}

- (CFTimeInterval)elapsedTime;
{
    return _stop - _start;
}

+ (NSString *)resourceDirectory;
{
    return [[[[NSProcessInfo processInfo] arguments] objectAtIndex:0] stringByDeletingLastPathComponent];
}

@end

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [ODOPerf run];
    [pool release];
    
    return 0;
}

