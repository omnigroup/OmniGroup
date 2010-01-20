// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@interface ODOPerf : NSObject
{
@private
    NSString *_name;
    CFAbsoluteTime _start, _stop;
}

+ (NSUInteger)stepCount;

+ (void)gatherTestNames:(NSMutableSet *)testNames;
+ (void)run;

- initWithName:(NSString *)name;
@property(readonly) NSString *name;
@property(readonly) NSString *storePath;

- (BOOL)runTestNamed:(NSString *)name;
- (void)setupCompleted;
- (CFTimeInterval)elapsedTime;

+ (NSString *)resourceDirectory;

@end
