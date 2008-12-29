// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOPerf/ODOPerf.h 104583 2008-09-06 21:23:18Z kc $

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
