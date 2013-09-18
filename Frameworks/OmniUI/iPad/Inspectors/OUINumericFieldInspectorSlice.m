// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINumericFieldInspectorSlice.h>
#import <OmniUI/OUINumericFieldTableCell.h>

RCS_ID("$Id$");


@implementation OUINumericFieldInspectorSlice

static void *OUINumericFieldInspectorSliceObservationContext; // The value is unimportant - we just use the address of this to get a unique context

+ (UIEdgeInsets)sliceAlignmentInsets;
{
    return (UIEdgeInsets) { .left = 0.0f, .right = 0.0f, .top = 0.0f, .bottom = 0.0f };
}

- (void)dealloc;
{
    if ([self isViewLoaded])
        [self.view removeObserver:self forKeyPath:OUINumericFieldTableCellValueKey context:&OUINumericFieldInspectorSliceObservationContext];
}

#pragma mark - Properties and API

- (NSInteger)integerValueInModel;
{
    OBRequestConcreteImplementation(self, _cmd);
    return 0;
}

- (void)setIntegerValueInModel:(NSInteger)newValue;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)_updateViewFromModel;
{
    ((OUINumericFieldTableCell *)self.view).value = self.integerValueInModel;
}

- (void)_updateModelFromView;
{
    NSInteger viewValue = ((OUINumericFieldTableCell *)self.view).value;
    NSInteger modelValue = self.integerValueInModel;
    if (viewValue != modelValue) {
        self.integerValueInModel = viewValue;
    }
}

#pragma mark - OUIInspectorSlice subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [self _updateViewFromModel];
}

#pragma mark - UIViewController

- (void)loadView;
{
    OUINumericFieldTableCell *cell = [OUINumericFieldTableCell numericFieldTableCell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger integerValue = self.integerValueInModel;
    cell.value = integerValue;
    self.view = cell;
    [cell sizeToFit];
    [cell addObserver:self forKeyPath:OUINumericFieldTableCellValueKey options:0 context:&OUINumericFieldInspectorSliceObservationContext];
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &OUINumericFieldInspectorSliceObservationContext) {
        OUINumericFieldTableCell *cell = (OUINumericFieldTableCell *)self.view;
        if (object == cell) {
            OBASSERT([keyPath isEqualToString:OUINumericFieldTableCellValueKey]);
            [self _updateModelFromView];
        } else {
            OBASSERT_NOT_REACHED(@"unexpected object for observation: %@", object);
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
