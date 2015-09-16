// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMenuOption.h>

RCS_ID("$Id$");

@implementation OUIMenuOption

+ (instancetype)optionWithFirstResponderSelector:(SEL)selector title:(NSString *)title image:(UIImage *)image NS_EXTENSION_UNAVAILABLE_IOS("");
{
    void (^action)(void) = ^{
        // Try the first responder and then the app delegate.
        UIApplication *app = [UIApplication sharedApplication];
        if ([app sendAction:selector to:nil from:self forEvent:nil])
            return;
        if ([app sendAction:selector to:app.delegate from:self forEvent:nil])
            return;
        
        NSLog(@"No target found for menu action %@", NSStringFromSelector(selector));
    };
    
    return [[self alloc] initWithTitle:title image:image action:action];
}

+ (instancetype)optionWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;
{
    return [[self alloc] initWithTitle:title image:image action:action];
}

+ (instancetype)optionWithTitle:(NSString *)title action:(OUIMenuOptionAction)action;
{
    return [[self alloc] initWithTitle:title image:nil action:action];
}

+ (instancetype)optionWithTitle:(NSString *)title action:(OUIMenuOptionAction)action validator:(OUIMenuOptionValidatorAction)validator;
{
    return [[self alloc] initWithTitle:title image:nil options:nil destructive:NO action:action validator:validator];
}

- initWithTitle:(NSString *)title image:(UIImage *)image options:(NSArray *)options destructive:(BOOL)destructive action:(OUIMenuOptionAction)action validator:(OUIMenuOptionValidatorAction)validator;
{
    OBPRECONDITION(title);
    //OBPRECONDITION(action || [options count] > 0); We allow placeholder disabled actions
    
    if (!(self = [super init]))
        return nil;
    
    _action = [action copy];
    _validator = [validator copy];
    _title = [title copy];
    _image = image;
    _destructive = destructive;
    _options = [options count] > 0 ? [options copy] : nil;
    
    return self;
}
- initWithTitle:(NSString *)title image:(UIImage *)image options:(NSArray *)options destructive:(BOOL)destructive action:(OUIMenuOptionAction)action;
{
    return [self initWithTitle:title image:image options:options destructive:destructive action:action validator:NULL];
}

- initWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;
{
    return [self initWithTitle:title image:image options:nil destructive:NO action:action];
}

- (BOOL)isEnabled;
{
    if (self.validator) {
        return self.validator();
    }
    else {
        return YES;
    }
}

@end
