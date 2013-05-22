// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMultiSegmentStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>

RCS_ID("$Id$");

@implementation OUIInspectorSegment
@synthesize title, slices;

- (void)dealloc;
{
    [title release];
    [slices release];
    [super dealloc];
}
@end

@implementation OUIMultiSegmentStackedSlicesInspectorPane

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    _segments = [[self makeAvailableSegments] retain];
    
    _titleSegmentedControl = [[UISegmentedControl alloc] initWithItems:[_segments valueForKey:@"title"]];
    _titleSegmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
    
    [_titleSegmentedControl addTarget:self action:@selector(_changeSegment:) forControlEvents:UIControlEventValueChanged];
        
    // Layout in the full width, divvying up fractional pixels.
    NSUInteger segmentCount = [_segments count];
    CGFloat totalWidth = OUIInspectorContentWidth - (segmentCount - 1); // remove space taken by the 1px separators between each segment
    for (NSUInteger segmentIndex = 0; segmentIndex < segmentCount; segmentIndex++) {
        CGFloat left = ceil(segmentIndex * totalWidth / segmentCount);
        CGFloat right = ceil((segmentIndex + 1) * totalWidth / segmentCount);
        [_titleSegmentedControl setWidth:right - left forSegmentAtIndex:segmentIndex];
    }
    
    self.navigationItem.titleView = _titleSegmentedControl;
    
    // Do this once in case we are told to inspect objects before our view is supposedly loaded.
    _titleSegmentedControl.selectedSegmentIndex = 0;
    [self _changeSegment:nil];
    
    return self;
}

- (void)dealloc;
{
    [_selectedSegment release];
    [_segments release];
    
    [_titleSegmentedControl removeFromSuperview];
    [_titleSegmentedControl removeAllSegments];
    [_titleSegmentedControl release];
    
    [super dealloc];
}

- (void)setSelectedSegment:(OUIInspectorSegment *)segment;
{
    if (segment == _selectedSegment)
        return;
    
    [_selectedSegment release];
    _selectedSegment = [segment retain];
    
    self.navigationItem.backBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:_selectedSegment.title style:UIBarButtonItemStyleBordered target:nil action:NULL] autorelease];
    
    [self.titleSegmentedControl setSelectedSegmentIndex:[_segments indexOfObject:segment]];
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
        toolbarItems = [NSArray arrayWithObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
    
    return toolbarItems;
}

- (NSArray *)toolbarItems;
{
    return _toolbarItemsForSegment(_selectedSegment);
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.titleSegmentedControl.selectedSegmentIndex = 0;
    [self _changeSegment:nil];
}

#pragma mark - Private

- (void)_changeSegment:(id)sender;
{
    OBPRECONDITION(_titleSegmentedControl);
    
    NSInteger segmentIndex = [_titleSegmentedControl selectedSegmentIndex];
    [self setSelectedSegment:[_segments objectAtIndex:segmentIndex]];
}

@end
