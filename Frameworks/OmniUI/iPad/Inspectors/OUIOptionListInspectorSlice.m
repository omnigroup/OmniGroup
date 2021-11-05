// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIOptionListInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIThemedTableViewCell.h>
#import <OmniUI/UITableView-OUIExtensions.h>

RCS_ID("$Id$");

@interface OUIOptionListInspectorSlice () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation OUIOptionListInspectorSlice
{
    Class _objectClass;
    NSString *_keyPath;
    NSArray *_titlesSubtitlesAndObjectValues;
}

+ (instancetype)optionListSliceWithObjectClass:(Class)objectClass
                                       keyPath:(NSString *)keyPath
                titlesSubtitlesAndObjectValues:(NSString *)title, ...;
{
    OBPRECONDITION(objectClass);
    
    NSMutableArray *titlesSubtitlesAndObjectValues = [[NSMutableArray alloc] initWithObjects:title, nil];
    if (title) {
        id nextObject;
        
        va_list argList;
        va_start(argList, title);
        while ((nextObject = va_arg(argList, id)) != nil) {
            [titlesSubtitlesAndObjectValues addObject:nextObject];
        }
        va_end(argList);
    }
    
    OBASSERT([titlesSubtitlesAndObjectValues count] > 0);
    OBASSERT(([titlesSubtitlesAndObjectValues count] % 3) == 0);
    
    OUIOptionListInspectorSlice *result = [[self alloc] init];
    result->_objectClass = objectClass;
    result->_keyPath = [keyPath copy];
    result->_titlesSubtitlesAndObjectValues = [titlesSubtitlesAndObjectValues copy];
    
    
    return result;
}

- (instancetype)init
{
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    
    _dismissesSelf = YES;

    return self;
}

@synthesize optionChangedBlock = _optionChangedBlock;

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:_objectClass];
}

#pragma mark - UITableViewDataSource protocol

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    if (section == 0)
        return [_titlesSubtitlesAndObjectValues count] / 3;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)aTableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    UITableViewCell *cell = [aTableView dequeueReusableCellWithIdentifier:@"option"];
    if (!cell)
        cell = [[OUIThemedTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"option"];
    
    NSUInteger row = indexPath.row;
    
    cell.textLabel.text = [_titlesSubtitlesAndObjectValues objectAtIndex:3*row + 0];
    cell.detailTextLabel.text = [_titlesSubtitlesAndObjectValues objectAtIndex:3*row + 1];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];

    cell.backgroundColor = [self sliceBackgroundColor];
    
    id valueForRow = [_titlesSubtitlesAndObjectValues objectAtIndex:3*row + 2];
    id valueForObject = [[self.appropriateObjectsForInspection lastObject] valueForKeyPath:_keyPath];
    
    BOOL selected = OFISEQUAL(valueForRow, valueForObject);
    OUITableViewCellShowSelection(cell, OUITableViewCellImageSelectionType, selected);
    
    return cell;
}

#pragma mark - UITableViewDelegate protocol

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    [self _changeValue:indexPath.row];
    [aTableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    return [self groupTitle];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
{
    return self.topPadding;
}
    
#pragma mark - Private

- (void)_changeValue:(NSUInteger)row;
{
    id value = [_titlesSubtitlesAndObjectValues objectAtIndex:3*row + 2];
    OUIInspector *inspector = self.inspector;
    
    [inspector willBeginChangingInspectedObjects];
    {
        for (id object in self.appropriateObjectsForInspection) {
            [object setValue:value forKeyPath:_keyPath];
            if (_optionChangedBlock != NULL)
                _optionChangedBlock(_keyPath, value);
        }
    }
    [inspector didEndChangingInspectedObjects];
    
    if (self.dismissesSelf)
        [self.navigationController popViewControllerAnimated:YES];
}

@end
