// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OASteppableTextField.h>

@interface OADatePickerTextField : OASteppableTextField

@property (nonatomic, strong, readonly) NSDate *defaultDate;

@property (nonatomic, strong) NSTextField *defaultTextField;
@property (nonatomic, strong) NSDate *minDate;
@property (nonatomic, strong) NSDate *maxDate;
@property (nonatomic, assign) BOOL isDatePickerHidden;
@property (nonatomic, strong) NSCalendar *calendar;

@end

