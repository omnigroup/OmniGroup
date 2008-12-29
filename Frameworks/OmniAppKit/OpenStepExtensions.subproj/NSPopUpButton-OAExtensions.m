// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSPopUpButton-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSPopUpButton-OAExtensions.m 104581 2008-09-06 21:18:23Z kc $")

@implementation NSPopUpButton (OAExtensions)

- (void)selectItemWithRepresentedObject:(id)object;
{
    NSArray *array = [self itemArray];
    unsigned int elementIndex = [array count];
    while (elementIndex--) {
        if (OFISEQUAL([[array objectAtIndex:elementIndex] representedObject], object)) {
            [self selectItemAtIndex:elementIndex];
            return;
        }
    }
}

- (NSMenuItem *)itemWithTag:(int)tag
{
    return [[self menu] itemWithTag:tag];
}

- (void)addRepresentedObjects:(NSArray *)objects titleSelector:(SEL)titleSelector;
{
    // Don't bother doing anything on nil or empty arrays
    if ([objects count] == 0)
        return;
        
    NSMenu *menu = [self menu];

    unsigned int objectIndex, objectCount;
    for (objectIndex = 0, objectCount = [objects count]; objectIndex < objectCount; objectIndex++) {
        id object = [objects objectAtIndex:objectIndex];
        NSString *title = [object performSelector:titleSelector];
        
        NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
        [newItem setRepresentedObject:object];
        [menu addItem:newItem];
        [newItem release];
    }
}

- (void)addRepresentedObjects:(NSArray *)objects titleKeyPath:(NSString *)keyPath;
{
    // Don't bother doing anything on nil or empty arrays
    if ([objects count] == 0)
        return;
        
    NSMenu *menu = [self menu];

    unsigned int objectIndex, objectCount;
    for (objectIndex = 0, objectCount = [objects count]; objectIndex < objectCount; objectIndex++) {
        id object = [objects objectAtIndex:objectIndex];
        NSString *title = [object valueForKeyPath:keyPath];
        
        NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
        [newItem setRepresentedObject:object];
        [menu addItem:newItem];
        [newItem release];
    }
}

@end
