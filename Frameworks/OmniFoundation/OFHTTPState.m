// Copyright 2012-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHTTPState.h>

#import <OmniFoundation/OFHTTPStateMachine.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

OFHTTPState *OFHTTPStatePause = nil;

@implementation OFHTTPState

@synthesize name;
@synthesize httpMethod, relativePath, setupRequest;
@synthesize success, redirect, failure, transitions;

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFHTTPStatePause = [[OFHTTPState alloc] initWithName:@"<paused>"];
}

- initWithName:(NSString *)aName;
{
    if (!(self = [super init]))
        return nil;
    
    name = [aName copy];
    
    return self;
}

- (void)dealloc;
{
    [self invalidate];
    
    [name release];
    [httpMethod release];
    [relativePath release];
    [super dealloc];
}

- (void)onStatus:(NSInteger)code transition:(OFHTTPStateTransitionBlock)transition;
{
    if (!transitions)
        transitions = [[NSMutableDictionary alloc] init];
    transition = [transition copy];
    [transitions setObject:transition forKey:[NSNumber numberWithInteger:code]];
    [transition release];
}

- (void)invalidate;
{
    self.setupRequest = nil;
    self.success = nil;
    self.failure = nil;
    self.redirect = nil;
    [transitions release];
    transitions = nil;
    
}

@end
