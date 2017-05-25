// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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
    
    _titleTabBar = [[OUITabBar alloc] initWithFrame:CGRectMake(0,0,[OUIInspector defaultInspectorContentWidth],30)];
    _titleTabBar.tabTitles = [_segments valueForKey:@"title"];
    // titles have to be set before images, because reasons.
    for (OUIInspectorSegment *segment in _segments) {
        if (segment.image) {
            _titleTabBar.showsTabImage = YES;
            _titleTabBar.showsTabTitle = NO;
            [_titleTabBar setImage:segment.image forTabWithTitle:segment.title];
        }
    }
    [_titleTabBar addTarget:self action:@selector(_changeSegment:) forControlEvents:UIControlEventValueChanged];
    _titleTabBar.appearanceDelegate = self;
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
    [self.viewIfLoaded setNeedsLayout];
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
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0,0, [OUIInspector defaultInspectorContentWidth], 50.0)];
    container.autoresizesSubviews = YES;
    container.backgroundColor = [OUIInspector backgroundColor];
    
    CGRect newFrame = CGRectInset(_titleTabBar.frame, 0.0, -VERTICAL_SPACING_AROUND_TABS);
    newFrame.origin.y = 0.0;
    newFrame.size.width = [OUIInspector defaultInspectorContentWidth];
    
    OUIInspectorBackgroundView *tabBackground = [[OUIInspectorBackgroundView alloc] initWithFrame:newFrame];
    tabBackground.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:tabBackground];
    
    _titleTabBar.frame = CGRectInset(tabBackground.bounds, 0.0, VERTICAL_SPACING_AROUND_TABS);
    _titleTabBar.translatesAutoresizingMaskIntoConstraints = NO;
    [tabBackground addSubview:_titleTabBar];

    self.view = container;

    // Set up space for the OUIStackedSlicesInspectorPane
    newFrame.origin.y = CGRectGetMaxY(newFrame);
    newFrame.size.height = CGRectGetMaxY(container.bounds) - newFrame.origin.y;
    _contentView.frame = newFrame;
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_contentView];
    
    [NSLayoutConstraint activateConstraints:
     @[
       // put the tab bar in its place
       [tabBackground.heightAnchor constraintEqualToConstant:30.0],
       [tabBackground.widthAnchor constraintEqualToAnchor:container.widthAnchor],
       [_titleTabBar.heightAnchor constraintEqualToConstant:30.0],
       [_titleTabBar.widthAnchor constraintEqualToAnchor:container.widthAnchor],
       [_titleTabBar.centerYAnchor constraintEqualToAnchor: tabBackground.centerYAnchor],
       // topLayoutGuide gets updated when we get (or lose?) a nav bar.
       [tabBackground.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor],
       // constrain the inspector slices to be as big as possible, but below the tabs.
       [_contentView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:_titleTabBar.frame.size.height],
       [_contentView.widthAnchor constraintEqualToAnchor:container.widthAnchor],
       [_contentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
       [_contentView.leftAnchor constraintEqualToAnchor:container.leftAnchor],
       [_contentView.rightAnchor constraintEqualToAnchor:container.rightAnchor],
       ]];
}

#pragma mark - OUITabBarAppearanceDelegate

- (UIColor *)selectedTabTintColor;
{
    return [UIColor blackColor];
}


#pragma mark - Private

- (void)_changeSegment:(id)sender;
{
    OBPRECONDITION(_titleTabBar);
    [self setSelectedSegment:[_segments objectAtIndex:[_titleTabBar selectedTabIndex]]];
}

@end
