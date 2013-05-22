// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileItemTransfers.h"

RCS_ID("$Id$")

@implementation OFXFileItemTransfers
{
    NSMutableSet *_requested;
    NSMutableSet *_running;
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _requested = [NSMutableSet new];
    _running = [NSMutableSet new];
    
    return self;
}

- (void)addRequestedFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION(![self containsFileItem:fileItem]);
    [_requested addObject:fileItem];
}

- (void)removeRequestedFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([_requested member:fileItem] == fileItem);
    [_requested removeObject:fileItem];
}

- (OFXFileItem *)anyRequest;
{
    return [_requested anyObject];
}

- (NSUInteger)numberRequested;
{
    return [_requested count];
}

- (BOOL)isEmpty;
{
    return [_running count] == 0 && [_requested count] == 0;
}

- (void)startedFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([_requested member:fileItem] == fileItem);
    OBPRECONDITION([_running member:fileItem] == nil);
    
    [_running addObject:fileItem];
    [_requested removeObject:fileItem];
}

- (void)finishedFileItem:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([_requested member:fileItem] == nil, "shouldn't be added while still running");
    OBPRECONDITION([_running member:fileItem] == fileItem);
    [_running removeObject:fileItem];
}

- (NSUInteger)numberRunning;
{
    return [_running count];
}

- (BOOL)containsFileItem:(OFXFileItem *)fileItem;
{
    return ([_requested member:fileItem] != nil) || ([_running member:fileItem] != nil);
}

- (void)reset;
{
    [_requested removeAllObjects];
    [_running removeAllObjects];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %ld requested, %ld running>", NSStringFromClass([self class]), self, [_requested count], [_running count]];
}

@end

