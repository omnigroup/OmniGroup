// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEditableLabeledTableViewCell.h>

#import <OmniUI/OUIEditableLabeledValueCell.h>

RCS_ID("$Id$")

@implementation OUIEditableLabeledTableViewCell
{
    OUIEditableLabeledValueCell *_editableValueCell;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier;
{
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]))
        return nil;
    
    _editableValueCell = [[OUIEditableLabeledValueCell alloc] initWithFrame:self.contentView.bounds];
    _editableValueCell.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self.contentView addSubview:_editableValueCell];
    
    return self;
}

- (void)dealloc;
{
    _editableValueCell.delegate = nil; // Callers like OUIServerAccountSetupViewController will make themselves the delegate
    [_editableValueCell release];
    
    [super dealloc];
}

- (OUIEditableLabeledValueCell *)editableValueCell;
{
    OBPRECONDITION(_editableValueCell);
    return _editableValueCell;
}

@end
