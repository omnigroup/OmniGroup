// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMultiSegmentStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorBackgroundView.h>
#import <OmniUI/OUITabBar.h>

RCS_ID("$Id$");

@implementation OUIInspectorSegment
@end

@implementation OUIMultiSegmentStackedSlicesInspectorPane
{
    UIView *_contentView;
}

#define SEGMENTED_CONTROL_HORIZONTAL_SPACING 9.0

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    _segments = [self makeAvailableSegments];
    
    _titleTabBar = [[OUITabBar alloc] initWithFrame:CGRectMake(0,0,OUIInspectorContentWidth,30)];
    _titleTabBar.tabTitles = [_segments valueForKey:@"title"];
    [_titleTabBar addTarget:self action:@selector(_changeSegment:) forControlEvents:UIControlEventValueChanged];
    
    // Do this once in case we are told to inspect objects before our view is supposedly loaded.
    _titleTabBar.selectedTabIndex = 0;
    [self _changeSegment:nil];
    
    return self;
}

- (void)setSelectedSegment:(OUIInspectorSegment *)segment;
{
    if (segment == _selectedSegment)
        return;
    
    _selectedSegment = segment;
    
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_selectedSegment.title style:UIBarButtonItemStylePlain target:nil action:NULL];
    
    [self.titleTabBar setSelectedTabIndex:[_segments indexOfObject:segment]];
    self.availableSlices = segment.slices;
    [self setToolbarItems:_toolbarItemsForSegment(_selectedSegment) animated:NO];
}

- (NSArray *)makeAvailableSegments; // For subclasses
{
    return [NSArray array];
}

#pragma mark -
#pragma mark UIViewController subclass

static NSArray *_toolbarItemsForSegment(OUIInspectorSegment *segment)
{
    NSArray *toolbarItems = [[[segment slices] objectAtIndex:0] toolbarItems];
    
    if ([toolbarItems count] == 0)
        // We don't need the bottom toolbar, but toggling between having a toolbar and not is buggy, seemingly in UIPopoverController. For one thing, it animates even if we pass around animate:NO. Turning that off via OUIWithoutAnimating(^{...}), the SHADOW behind the popover still animates. Also, the content size of the popover is what the contained view controller gets to set, so we would need to report a greater size for non-toolbar controllers, or we'd need OUIInspector to adjust height when it toggled the toolbar on/off.
        toolbarItems = [NSArray arrayWithObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL]];
    
    return toolbarItems;
}

- (NSArray *)toolbarItems;
{
    return _toolbarItemsForSegment(_selectedSegment);
}

/*
- (UIView *)navigationBarAccessoryView;
{
    return _titleTabBar;
}
*/
- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.titleTabBar.selectedTabIndex = 0;
    [self _changeSegment:nil];
}

- (UIView *)contentView;
{
    return _contentView;
}

#define VERTICAL_SPACING_AROUND_TABS 0.0

- (void)loadView;
{
    // Embed the tab bar and superclass scrolling view inside a container
    [super loadView];
    _contentView = self.view;
    
    UIScrollView *container = [[UIScrollView alloc] initWithFrame:CGRectMake(0,0, OUIInspectorContentWidth, 50.0)];
    container.autoresizesSubviews = YES;
    container.scrollEnabled = NO;
    container.backgroundColor = [OUIInspector backgroundColor];
    
    CGRect newFrame = CGRectInset(_titleTabBar.frame, 0.0, -VERTICAL_SPACING_AROUND_TABS);
    newFrame.origin.y = 0.0;
    newFrame.size.width = OUIInspectorContentWidth;
    
    OUIInspectorBackgroundView *tabBackground = [[OUIInspectorBackgroundView alloc] initWithFrame:newFrame];
    tabBackground.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleWidth;
    [container addSubview:tabBackground];
    
    _titleTabBar.frame = CGRectInset(tabBackground.bounds, 0.0, VERTICAL_SPACING_AROUND_TABS);
    _titleTabBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [tabBackground addSubview:_titleTabBar];
    
    newFrame.origin.y = CGRectGetMaxY(newFrame);
    newFrame.size.height = CGRectGetMaxY(container.bounds) - newFrame.origin.y;
    _contentView.frame = newFrame;
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    [container addSubview:_contentView];
    
    self.view = container;
}


#pragma mark - Private

- (void)_changeSegment:(id)sender;
{
    OBPRECONDITION(_titleTabBar);
    [self setSelectedSegment:[_segments objectAtIndex:[_titleTabBar selectedTabIndex]]];
}

@end
