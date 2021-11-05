// Copyright 2006-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASteppableTextField.h>

#import <OmniAppKit/OAUtilities.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSApplication.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@interface OASteppableTextField (/*Private*/)
- (BOOL)_stepWithFormatterSelector:(SEL)formatterSelector;
@end

@implementation OASteppableTextField

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
{
    if (![self isEditable]) {
        return NO;
    }
    SEL formatterSelector;
    
    if (commandSelector == @selector(moveUp:)) {
        formatterSelector = @selector(stepUpValue:);
    } else if (commandSelector == @selector(moveUpAndModifySelection:)) {
        formatterSelector = @selector(largeStepUpValue:);
    } else if (commandSelector == @selector(moveDown:)) {
        formatterSelector = @selector(stepDownValue:);
    } else if (commandSelector == @selector(moveDownAndModifySelection:)) {
        formatterSelector = @selector(largeStepDownValue:);
    } else
        return NO;

    return [self _stepWithFormatterSelector:formatterSelector];
}

- (void)stepperAction:(id)sender;
{    
    SEL formatterSelector;
    double value = [sender doubleValue];
    if (value > stepperTracking)
	formatterSelector = @selector(stepUpValue:);
    else 
	formatterSelector = @selector(stepDownValue:);
    
    stepperTracking = value;
    [self _stepWithFormatterSelector:formatterSelector];
}

- (BOOL)validateSteppedObjectValue:(id)objectValue;
{
    return YES;
}

#pragma mark -
#pragma mark Private

- (BOOL)_stepWithFormatterSelector:(SEL)formatterSelector;
{
    NSFormatter *formatter = [self formatter];
    if (![formatter respondsToSelector:formatterSelector])
        return NO;
    
    id objectValue = [formatter performSelector:formatterSelector withObject:[self objectValue]];
    if (![self validateSteppedObjectValue:objectValue])
        return NO;
    
    [self setObjectValue:objectValue];
    [[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:self];
    
    OAPushValueThroughBinding(self, objectValue, NSValueBinding);
    
    return YES;
}

@end

@implementation NSNumberFormatter (OASteppableTextFieldFormatter)

- (id)stepUpValue:(id)anObjectValue;
{
    return [anObjectValue decimalNumberByAdding:[NSDecimalNumber one]];
}

- (id)largeStepUpValue:(id)anObjectValue;
{
    return [anObjectValue decimalNumberByAdding:[NSDecimalNumber decimalNumberWithMantissa:10 exponent:0 isNegative:NO]];
}

- (id)stepDownValue:(id)anObjectValue;
{
    return [anObjectValue decimalNumberBySubtracting:[NSDecimalNumber one]];
}

- (id)largeStepDownValue:(id)anObjectValue;
{
    return [anObjectValue decimalNumberBySubtracting:[NSDecimalNumber decimalNumberWithMantissa:10 exponent:0 isNegative:NO]];
}

@end
