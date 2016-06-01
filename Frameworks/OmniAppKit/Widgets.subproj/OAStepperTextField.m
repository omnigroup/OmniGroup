// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAStepperTextField.h>

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>

#import <OmniAppKit/NSTextField-OAExtensions.h>


RCS_ID("$Id$");

@interface OAStepperTextField (Private)
- (void)_synchronizeFormatterAndStepper;
@end


@implementation OAStepperTextField
    
- (void)awakeFromNib;
{
    [labelControl setEnabled:[self isEnabled]];
    [stepper setEnabled:[self isEnabled]];
}

// API

- (void)takeDoubleValueFrom:(id)sender;
{
    [super takeDoubleValueFrom:sender];
    [[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:self];

    // Make bindings notice the change
    OAPushValueThroughBinding(self, [self objectValue], NSValueBinding);
}

- (void)setHidden:(BOOL)flag;
{
    [labelControl setHidden:flag];
    [stepper setHidden:flag];
    [super setHidden:flag];
}

- (NSString *)label;
{
    if ([labelControl respondsToSelector:@selector(title)])
        return [(id)labelControl title];
    else
        return [labelControl stringValue];
}

- (void)setLabel:(NSString *)newValue;
{
    if (labelControl == nil) {
        NSLog(@"%@ %@ - ignoring attempt to set a label because we don't have a label field.", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    }

    if ([labelControl respondsToSelector:@selector(setTitle:)])
        [(id)labelControl setTitle:newValue];
    else
        [labelControl setStringValue:newValue];
}

- (id)labelControl;
{
    return labelControl;
}

- (void)setLabelControl:(id)newValue;
{
    if (labelControl != newValue) {
        labelControl = newValue;
        [labelControl setEnabled:[self isEnabled]];
    }
}

- (id)stepper;
{
    return stepper;
}

- (void)setStepper:(id)newValue;
{
    [stepper setTarget:nil];
    [stepper setAction:NULL];
    
     stepper = newValue;

    [stepper setDoubleValue:[self doubleValue]];
    [stepper setEnabled:[self isEnabled]];
    [stepper setTarget:self];
    [stepper setAction:@selector(takeDoubleValueFrom:)];
}


// NSControl subclass

- (void)setEnabled:(BOOL)flag;
{
    [super setEnabled:flag];
    [stepper setEnabled:flag];
    if ([labelControl isKindOfClass:[NSTextField class]])
        [(NSTextField *)labelControl changeColorAsIfEnabledStateWas:flag];
    else
        [labelControl setEnabled:flag];
}

- (void)setDoubleValue:(double)newValue;
{
    [super setDoubleValue:newValue];
    [stepper setDoubleValue:[self doubleValue]];
}

- (void)setFloatValue:(float)newValue;
{
    [super setFloatValue:newValue];
    [stepper setDoubleValue:[self doubleValue]];
}

- (void)setFormatter:(NSFormatter *)newValue;
{
    [super setFormatter:newValue];
    [self _synchronizeFormatterAndStepper];
}

- (void)setIntValue:(int)newValue;
{
    [super setIntValue:newValue];
    [stepper setDoubleValue:[self doubleValue]];
}

- (void)setObjectValue:(id <NSCopying>)newValue;
{
    [super setObjectValue:newValue];
    [stepper setDoubleValue:[self doubleValue]];
}

- (void)setStringValue:(NSString *)newValue;
{
    [super setStringValue:newValue];
    [stepper setDoubleValue:[self doubleValue]];
}


// NSTextField subclass

- (void)textDidEndEditing:(NSNotification *)notification;
{
    [super textDidEndEditing:notification];
    [stepper setDoubleValue:[self doubleValue]];
}

- (void)_synchronizeFormatterAndStepper;
{
    id formatter = [self formatter];
    
    if ([formatter respondsToSelector:@selector(minValue)]) {
        [stepper setMinValue:[formatter minValue]];
    }
    
    if ([formatter respondsToSelector:@selector(maxValue)]) {
        [stepper setMaxValue:[formatter maxValue]];
    }
}

@end

