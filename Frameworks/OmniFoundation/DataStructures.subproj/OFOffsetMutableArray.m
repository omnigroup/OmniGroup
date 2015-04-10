// Copyright 2012-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFOffsetMutableArray.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$");

@interface OFOffsetMutableArray ()

@property (nonatomic, strong) NSMutableArray *backingArray;

@end

@implementation OFOffsetMutableArray

- (NSMutableArray *)unadjustedArray;
{
    // Deliberately return the backing array itself (not a copy) so that changes to the unadjusted array are reflected in this array as well
    return self.backingArray;
}

#pragma mark - Object lifecycle

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    
    _backingArray = [[NSMutableArray alloc] init];
    _offset = 0;
    
    return self;
}

- (id)initWithArray:(NSArray *)array;
{
    if (!(self = [super init]))
        return nil;
    
    _backingArray = [array mutableCopy];
    _offset = 0;
    
    return self;
}

- (void)dealloc;
{
    [_backingArray release];
    _backingArray = nil;
    
    [super dealloc];
}

#pragma mark - NSArray subclass

- (NSUInteger)count;
{
    if (self.offset > self.backingArray.count)
        return 0;
    
    return self.backingArray.count - self.offset;
}

- (id)objectAtIndex:(NSUInteger)index;
{
    return [self.backingArray objectAtIndex:index + self.offset];
}

#pragma mark - NSMutableArray subclass

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index;
{
    [self.backingArray insertObject:anObject atIndex:index + self.offset];
}

- (void)removeObjectAtIndex:(NSUInteger)index;
{
    [self.backingArray removeObjectAtIndex:index + self.offset];
}

- (void)addObject:(id)anObject;
{
    [self.backingArray addObject:anObject];
}

- (void)removeLastObject;
{
    [self.backingArray removeLastObject];
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject;
{
    [self.backingArray replaceObjectAtIndex:index + self.offset withObject:anObject];
}

@end
