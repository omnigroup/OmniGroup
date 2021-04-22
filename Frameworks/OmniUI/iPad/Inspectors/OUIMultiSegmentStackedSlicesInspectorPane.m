// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMultiSegmentStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorBackgroundView.h>
#import <OmniUI/OUITabBar.h>

@interface OUIMultiSegmentStackedSlicesInspectorPane (/*Private*/)
@property (nonatomic, strong) UINavigationItem *segmentsNavigationItem;
@property (nonatomic, copy) UIColor *selectedTabTintColor;
@property (nonatomic, copy) UIColor *horizontalTabBottomStrokeColor;
@property (nonatomic, copy) UIColor *horizontalTabSeparatorTopColor;

@end

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
    
    _titleTabBar = [[OUITabBar alloc] initWithFrame:CGRectMake(0,0,[OUIInspector defaultInspectorContentWidth],30)];
    [_titleTabBar addTarget:self action:@selector(_changeSegment:) forControlEvents:UIControlEventValueChanged];
    _titleTabBar.appearanceDelegate = self;

    [self reloadAvailableSegments];

    self.selectedTabTintColor = [UIColor labelColor];

    return self;
}

- (void)reloadAvailableSegments; // this will end up calling makeAvailableSegments
{
    _segments = [self makeAvailableSegments];

    _titleTabBar.tabTitles = [_segments valueForKey:@"title"];
    // titles have to be set before images, because reasons.
    for (OUIInspectorSegment *segment in _segments) {
        if (segment.image) {
            _titleTabBar.showsTabImage = YES;
            _titleTabBar.showsTabTitle = NO;
            [_titleTabBar setImage:segment.image forTabWithTitle:segment.title];
        }
    }
    // Do this once in case we are told to inspect objects before our view is supposedly loaded.
    _titleTabBar.selectedTabIndex = 0;
    [self _changeSegment:nil];
}

- (UINavigationItem *)segmentsNavigationItem;
{
    if (!_segmentsNavigationItem) {
        _segmentsNavigationItem = [[UINavigationItem alloc] init];
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:[_segments valueForKey:@"title"]];

        [control addTarget:self action:@selector(_changeNavigationSegment:) forControlEvents:UIControlEventValueChanged];
        _segmentsNavigationItem.titleView = control;
    }

    return _segmentsNavigationItem;
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

    if (!self.wantsEmbeddedTitleTabBar) {
        UISegmentedControl *control = (UISegmentedControl *)self.navigationItem.titleView;

        if ([control isKindOfClass:UISegmentedControl.class]) {
            NSInteger currentIndex = control.selectedSegmentIndex;
            NSInteger index = [self _segmentIndexFromSegmentTitle:segment.title];
            if (currentIndex != index) {
                control.selectedSegmentIndex = index;
            }
        }
    }
}

- (BOOL)wantsEmbeddedTitleTabBar; // return NO if you want a segmented control in the navigation items instead of tabs in the content.
{
    return YES;
}

- (NSArray *)makeAvailableSegments; // For subclasses
{
    OBRequestConcreteImplementation(self, _cmd);
    return @[]; 
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

- (UINavigationItem *)navigationItem;
{
    if (self.wantsEmbeddedTitleTabBar) {
        return [super navigationItem];
    } else {
        return self.segmentsNavigationItem;
    }
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
#define VERTICAL_SPACING_FOR_NON_TABS (0.0)

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

    if (!self.wantsEmbeddedTitleTabBar) {
        newFrame.size.height = VERTICAL_SPACING_FOR_NON_TABS;
    }

    NSMutableArray *constraints = [NSMutableArray array];

    OUIInspectorBackgroundView *tabBackground = [[OUIInspectorBackgroundView alloc] initWithFrame:newFrame];
    tabBackground.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:tabBackground];
    if (self.wantsEmbeddedTitleTabBar) {
        _titleTabBar.frame = CGRectInset(tabBackground.bounds, 0.0, VERTICAL_SPACING_AROUND_TABS);
        _titleTabBar.translatesAutoresizingMaskIntoConstraints = NO;
        [tabBackground addSubview:_titleTabBar];
    }

    self.view = container;

    if (self.wantsEmbeddedTitleTabBar) {
        // Set up space for the OUIStackedSlicesInspectorPane
        newFrame.origin.y = CGRectGetMaxY(newFrame);
        newFrame.size.height = CGRectGetMaxY(container.bounds) - newFrame.origin.y;
    } else {
        newFrame.size.height = 0;
    }

    _contentView.frame = newFrame;
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_contentView];

    if (self.wantsEmbeddedTitleTabBar) {
        [constraints addObjectsFromArray:@[
            // put the tab bar in its place
            [tabBackground.heightAnchor constraintEqualToConstant:30.0],
            [tabBackground.widthAnchor constraintEqualToAnchor:container.widthAnchor],
            [tabBackground.leadingAnchor constraintEqualToAnchor: container.leadingAnchor],
            [tabBackground.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor],
            [tabBackground.bottomAnchor constraintEqualToAnchor:_contentView.topAnchor],

            [_titleTabBar.heightAnchor constraintEqualToConstant:30.0],
            [_titleTabBar.widthAnchor constraintEqualToAnchor:container.widthAnchor],
            [_titleTabBar.leadingAnchor constraintEqualToAnchor: tabBackground.leadingAnchor],
            [_titleTabBar.topAnchor constraintEqualToAnchor:tabBackground.topAnchor],

            ]];
    } else {
        [constraints addObject:[_contentView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:VERTICAL_SPACING_FOR_NON_TABS]];
    }

    [constraints addObjectsFromArray:@[
        [_contentView.widthAnchor constraintEqualToAnchor:container.widthAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_contentView.leftAnchor constraintEqualToAnchor:container.leftAnchor],
        [_contentView.rightAnchor constraintEqualToAnchor:container.rightAnchor],
        ]];


    [NSLayoutConstraint activateConstraints:constraints];
}


#pragma mark - PrivateOP

- (void)_changeSegment:(id)sender;
{
    OBPRECONDITION(_titleTabBar);
    if (_segments.count == 0) {
        return;
    }
    [self setSelectedSegment:[_segments objectAtIndex:[_titleTabBar selectedTabIndex]]];
}

- (void)_changeNavigationSegment:(id)sender;
{
    OBASSERT(self.wantsEmbeddedTitleTabBar == NO, @"_changeNavigationSegment should only be called when not using tabs.");
    UISegmentedControl *control = (UISegmentedControl *)self.navigationItem.titleView;

    if ([control isKindOfClass:UISegmentedControl.class]) {
        NSInteger index = control.selectedSegmentIndex;
        self.titleTabBar.selectedTabIndex = index;
        [self setSelectedSegment:[self.segments objectAtIndex:index]];
    }
}

- (NSInteger)_segmentIndexFromSegmentTitle:(NSString *)title;
{
    for (NSUInteger index = 0; index < self.segments.count; index++) {
        OUIInspectorSegment *segment = [self.segments objectAtIndex:index];
        if ([title isEqualToString:segment.title]) {
            return index;
        }
    }

    return NSNotFound;
}

@end
