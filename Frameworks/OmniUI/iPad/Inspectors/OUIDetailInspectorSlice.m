// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDetailInspectorSlice.h>

#import <OmniUI/OUIInspectorTextWell.h>

RCS_ID("$Id$");

@implementation OUIDetailInspectorSlice

+ (id)detailLabelWithTitle:(NSString *)title paneMaker:(OUIDetailInspectorSlicePaneMaker)paneMaker;
{
    return [[(OUIDetailInspectorSlice *)[self alloc] initWithTitle:title paneMaker:paneMaker] autorelease];
}

- initWithTitle:(NSString *)title paneMaker:(OUIDetailInspectorSlicePaneMaker)paneMaker;
{
    OBPRECONDITION(paneMaker);

    if (!(self = [super initWithTitle:title action:@selector(showDetails:)]))
        return nil;
    
    self.paneMaker = paneMaker;
    
    return self;
}

@synthesize paneMaker = _paneMaker;

- (void)dealloc;
{
    [_paneMaker release];
    [super dealloc];
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (void)showDetails:(id)sender;
{
    if (!self.detailPane && _paneMaker)
        self.detailPane = _paneMaker(self);
    [super showDetails:sender];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    self.textWell.showNavigationArrow = YES;
}

@end
