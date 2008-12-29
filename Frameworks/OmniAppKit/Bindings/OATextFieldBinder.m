// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATextFieldBinder.h"

#import <OmniBase/OmniBase.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$");

@implementation OATextFieldBinder

- (void)observeIfNeeded;
{
    BOOL shouldBeObserving;
    
    if (!boundField || [boundField isHidden] || !subject || !keyPath)
        shouldBeObserving = NO;
    else {
        shouldBeObserving = YES;
    }
    
    
    if (observing && !shouldBeObserving) {
        [subject removeObserver:self forKeyPath:keyPath];
        observing = NO;
    } else if (!observing && shouldBeObserving) {
        [subject addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:NULL];
        observing = YES;
    }
}

- (void)setBoundField:(NSTextField *)f
{
    if (boundField == f)
        return;
    
    if (boundField) {
        [boundField setTarget:nil];
        [boundField release];
    }
    boundField = [f retain];
    
    [boundField setTarget:self];
    [boundField setAction:@selector(uiChangedValue:)];
    [self observeIfNeeded];
}

- (void)uiChangedValue:sender
{
    //NSLog(@"%@ changedValue begin", OBShortObjectDescription(self));
    settingValue = YES;
    [subject setValue:[sender objectValue] forKeyPath:keyPath];
    settingValue = NO;
    //NSLog(@"%@ changedValue end", OBShortObjectDescription(self));
}

- (void)setSubject:(NSObject *)s;
{
    if (subject == s)
        return;
    
    if (subject) {
        if (observing) {
            [subject removeObserver:self forKeyPath:keyPath];
            observing = NO;
        }
        [subject release];
        subject = nil;
    }
    
    subject = [s retain];
    [self observeIfNeeded];
}

- (void)setKeyPath:(NSString *)observingKeyPath
{
    if (keyPath == observingKeyPath)
        return;
    
    if (keyPath) {
        if (observing) {
            [subject removeObserver:self forKeyPath:keyPath];
            observing = NO;
        }
        [keyPath release];
        keyPath = nil;
    }
    
    if (observingKeyPath) {
        keyPath = [observingKeyPath copy];
        [self observeIfNeeded];
    }
}

- (void)observeValueForKeyPath:(NSString *)observedKeyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    //NSLog(@"%@ observingValue begin %@", OBShortObjectDescription(self), [change description]);
    if (object == subject && [observedKeyPath isEqualToString:keyPath]) {
        if (settingValue && [boundField currentEditor]) {
            // do nothing.
        } else {
            [boundField setObjectValue:[change objectForKey:NSKeyValueChangeNewKey]];
        }
    } else {
        OBASSERT_NOT_REACHED("Unexpected KVO message received");
    }
    //NSLog(@"%@ observingValue end", OBShortObjectDescription(self));
}


@end

