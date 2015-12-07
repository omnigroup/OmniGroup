// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
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

RCS_ID("$Id$")

@implementation NSPopUpButton (OAExtensions)

- (void)selectItemWithRepresentedObject:(id)object;
{
    NSInteger elementIndex = [self indexOfItemWithRepresentedObject:object];
    if (elementIndex != -1)
        [self selectItemAtIndex:elementIndex];
}

- (NSMenuItem *)itemWithTag:(NSInteger)tag
{
    return [[self menu] itemWithTag:tag];
}

- (void)addRepresentedObjects:(NSArray *)objects titleSelector:(SEL)titleSelector;
{
    NSMenu *menu = [self menu];

    for (id object in objects) {
        NSString *title = OBSendObjectReturnMessage(object, titleSelector);

        NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
        [newItem setRepresentedObject:object];
        [menu addItem:newItem];
     }
}

- (void)addRepresentedObjects:(NSArray *)objects titleKeyPath:(NSString *)keyPath;
{
    NSMenu *menu = [self menu];

    for (id object in objects) {
        NSString *title = [object valueForKeyPath:keyPath];
        
        NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
        [newItem setRepresentedObject:object];
        [menu addItem:newItem];
    }
}

@end
