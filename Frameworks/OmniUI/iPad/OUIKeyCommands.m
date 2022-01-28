// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIKeyCommands.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSIndexSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>

#import <Foundation/Foundation.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OUIKeyCommands

static NSMutableDictionary *CategoriesToKeyCommands = nil;
static NSMutableDictionary *CategoriesToSelectorNames = nil;
static NSCache *KeyCommandsToSelectorNames = nil;

static void _parseKeyCommands(NSArray *commands, NSBundle *bundle, NSString *tableName, NSArray **outKeyCommands, NSSet **outSelectorNames)
{
    /*
     We use a similar syntax as /System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict on the Mac
     
     FLAGS:
     
         ^ = control
         $ = shift
         @ = command
         ~ = alternate
     
         TODO: Add UIKeyModifierAlphaShift and UIKeyModifierNumericPad mappings
     
     SINGLE KEY COMMANDS:
     
         After the flag specification there is a single character for the creation of a single key command.
     
     DYNAMIC KEY COMMANDS:
     
         However, you can use the character * as a prefix to symbolize a dynamically created group of key commands.
         
         For example, you can request an "index set" of logically grouped key commands by using the range string syntax supported by NSIndexSet-OFFoundation embedded in parenthesis.
         
         To create key commands @1, @2, @3, you can collapse this into `@*(1-3)`
     
         This can be helpful for navigating tab-style interfaces where each key command corresponds to an available tab in the interface.

     The value of each command array is the shortcut and a selector for an action (the Mac allows a list of shortcuts per action, but UIKeyCommand does not).
     
     */
    
    tableName = [NSString stringWithFormat:@"%@Keycommands", tableName];
    
    NSCharacterSet *nonModifierCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"^$@~"] invertedSet];

    NSMutableArray *keyCommands = [NSMutableArray array];
    NSMutableSet *selectorNames = [NSMutableSet set];

    for (NSArray *commandComponents in commands) {
        NSUInteger componentCount = [commandComponents count];
        OBASSERT(componentCount >= 3 && componentCount <= 4);
        if (componentCount < 3 || componentCount > 4) {
#ifdef DEBUG
            NSLog(@"Skipping command %@ due to incorrect formatting in keycommands document.", commandComponents);
#endif
            continue;
        }
        
        BOOL hasDiscoverabilityTitleIdentifier = componentCount == 4;
        NSString *shortcut = [commandComponents firstObject];

        BOOL wantsPriorityOverSystemBehavior = [[commandComponents objectAtIndex:1] boolValue];

        NSString *selectorName = nil;
        NSString *discoverabilityTitle = nil;
        if (hasDiscoverabilityTitleIdentifier) {
            selectorName = [commandComponents objectAtIndex:2];
            NSString *discoverabilityTitleIdentifier = [commandComponents lastObject];
            OBASSERT(![NSString isEmptyString:discoverabilityTitleIdentifier]);
            discoverabilityTitle = [bundle localizedStringForKey:discoverabilityTitleIdentifier value:@"" table:tableName];
        } else {
            selectorName = [commandComponents lastObject];
        }

        OBASSERT([selectorName rangeOfString:@":"].location == [selectorName length] - 1, "Selector \"%@\" should have one \":\" at the end.", selectorName);
        
        __block UIKeyModifierFlags flags = 0;
        
        // Have to leave at least one character (so ^@ would be valid -- at least on a keyboard where '@' is not shifted).
        NSUInteger inputStart;
        {
            NSRange allowedModifierRange = NSMakeRange(0, [shortcut length] - 1);
            
            NSRange nonModifierRange = [shortcut rangeOfCharacterFromSet:nonModifierCharacterSet options:0 range:allowedModifierRange];
            if (nonModifierRange.location == NSNotFound) {
                inputStart = NSMaxRange(allowedModifierRange); // All the characters up front are modifiers
            } else {
                inputStart = nonModifierRange.location;
            }
        }
        
        [[shortcut substringToIndex:inputStart] enumerateSubstringsInRange:NSMakeRange(0, inputStart) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            if ([substring isEqualToString:@"$"]) {
                flags |= UIKeyModifierShift;
            } else if ([substring isEqualToString:@"^"]) {
                flags |= UIKeyModifierControl;
            } else if ([substring isEqualToString:@"~"]) {
                flags |= UIKeyModifierAlternate;
            } else if ([substring isEqualToString:@"@"]) {
                flags |= UIKeyModifierCommand;
            } else {
                NSLog(@"Unknown key command modifier flag \"%@\".", substring);
            }
        }];
        
        NSString *inputString = [shortcut substringFromIndex:inputStart];
        
        if ([inputString hasPrefix:@"*"]) {
            NSString *variableInput = [inputString substringFromIndex:1];
            if ([variableInput hasPrefix:@"("] && [variableInput hasSuffix:@")"]) {
                NSIndexSet *dynamicInputIndexSet = [NSIndexSet indexSetWithRangeString:[variableInput substringWithRange:NSMakeRange(1, [variableInput length] - 1)]];
                
                [dynamicInputIndexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                    NSString *input = [[NSNumber numberWithUnsignedInteger:idx] stringValue];
                    UIKeyCommand *command = [UIKeyCommand keyCommandWithInput:input modifierFlags:flags action:NSSelectorFromString(selectorName)];
                    if (@available(iOS 15.0, *)) {
                        command.wantsPriorityOverSystemBehavior = wantsPriorityOverSystemBehavior;
                    }
                    command.discoverabilityTitle = discoverabilityTitle;
                    
                    OBASSERT(command != nil);
                    if (command != nil) {
                        [keyCommands addObject:command];
                        [selectorNames addObject:selectorName];
                    }
                }];
            } else {
                OBASSERT_NOT_REACHED("What kind of dynamic key command is this? Unrecognized syntax.");
            }
        } else {
            if ([inputString isEqualToString:@"up"]) {
                inputString = UIKeyInputUpArrow;
            } else if ([inputString isEqualToString:@"down"]) {
                inputString = UIKeyInputDownArrow;
            } else if ([inputString isEqualToString:@"left"]) {
                inputString = UIKeyInputLeftArrow;
            } else if ([inputString isEqualToString:@"right"]) {
                inputString = UIKeyInputRightArrow;
            } else if ([inputString isEqualToString:@"escape"]) {
                inputString = UIKeyInputEscape;
            } else {
                OBASSERT([inputString length] == 1, "Input portion of key command string \"%@\" should be a single character", shortcut);
            }
            UIKeyCommand *command = [UIKeyCommand keyCommandWithInput:inputString modifierFlags:flags action:NSSelectorFromString(selectorName)];
            if (@available(iOS 15.0, *)) {
                command.wantsPriorityOverSystemBehavior = wantsPriorityOverSystemBehavior;
            }

            if (discoverabilityTitle != nil && discoverabilityTitle.length > 0) {
                command.discoverabilityTitle = discoverabilityTitle;
            }
            
            OBASSERT(command != nil);
            if (command != nil) {
                [keyCommands addObject:command];
                [selectorNames addObject:selectorName];
            }
        }
    }

    *outKeyCommands = [keyCommands copy];
    *outSelectorNames = [selectorNames copy];
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    CategoriesToKeyCommands = [[NSMutableDictionary alloc] init];
    CategoriesToSelectorNames = [[NSMutableDictionary alloc] init];
    KeyCommandsToSelectorNames = [[NSCache alloc] init];
    
    // Each file should have the structure { category = ( list of commands ); }
    NSMutableArray *bundles = [[NSBundle allFrameworks] mutableCopy]; // On iOS 8 and iOS 9, +allFrameworks includes +mainBundle.
    if ([bundles containsObject:[NSBundle mainBundle]] == NO)
        [bundles addObject:[NSBundle mainBundle]]; // but let's be safe in case they fix the bug.
    
    for (NSBundle *bundle in bundles) {
        NSArray *keyCommandsFileURLs = [bundle URLsForResourcesWithExtension:@"keycommands" subdirectory:nil];
        for (NSURL *keyCommandFileURL in keyCommandsFileURLs) {
            __autoreleasing NSError *error = nil;
            
            NSData *keyCommandData = [[NSData alloc] initWithContentsOfURL:keyCommandFileURL options:NSDataReadingMappedIfSafe error:&error];
            if (keyCommandData == nil) {
                [error log:@"Error reading data from %@", keyCommandFileURL];
                continue;
            }
            
            error = nil;
            NSDictionary *keyCommandsPlist = [NSPropertyListSerialization propertyListWithData:keyCommandData options:0 format:NULL error:&error];
            if (keyCommandsPlist == nil) {
                [error log:@"Error deserializing data from %@", keyCommandFileURL];
                continue;
            }
            
            [keyCommandsPlist enumerateKeysAndObjectsUsingBlock:^(NSString *categoryName, NSArray *keyCommandDescriptions, BOOL *stop) {
                NSString *tableName = [[keyCommandFileURL lastPathComponent] stringByDeletingPathExtension];
                __autoreleasing NSArray *keyCommands = nil;
                __autoreleasing NSSet *selectorNames = nil;

                _parseKeyCommands(keyCommandDescriptions, bundle, tableName, &keyCommands, &selectorNames);
                
                // TODO: At this point we could eliminate duplicates within a given category, but not cross-category de-duping.
                NSArray *previousCommands = CategoriesToKeyCommands[categoryName];
                if (previousCommands != nil) {
                    keyCommands = [previousCommands arrayByAddingObjectsFromArray:keyCommands];
                }
                
                NSSet *previousSelectorNames = CategoriesToSelectorNames[categoryName];
                if (previousSelectorNames != nil) {
                    selectorNames = [previousSelectorNames setByAddingObjectsFromSet:previousSelectorNames];
                }
                
                CategoriesToKeyCommands[categoryName] = keyCommands;
                CategoriesToSelectorNames[categoryName] = selectorNames;
            }];
        }
    }
}

+ (nullable NSArray<UIKeyCommand *> *)keyCommandsForCategories:(nullable NSOrderedSet<NSString *> *)categoriesSet;
{
    if (categoriesSet == nil) {
        return nil;
    }
    
    NSArray<NSString *> *names = [categoriesSet array];
    NSString *categories = [names componentsJoinedByString:@","];
    
    // TODO: At this point it would be okay to do cross-category de-duping based on the ordered, comma-separated categories string. When done here, if category foo and bar share keycommand, sending "foo", "bar", "foo,bar", "bar,foo" should always result in one version of keycommand.
    NSArray *commands = CategoriesToKeyCommands[categories];
    if (commands != nil) {
        return commands;
    }
    
    NSMutableArray *mergedCommands = [NSMutableArray array];
    NSArray *categoryNames = [categories componentsSeparatedByString:@","];
    for (NSString *categoryName in categoryNames) {
        commands = CategoriesToKeyCommands[categoryName];
        if (commands == nil) {
            NSLog(@"No key command category named \"%@\".", categoryName);
            continue;
        }
        
        [mergedCommands addObjectsFromArray:commands];
    }
    
    commands = [mergedCommands copy];
    CategoriesToKeyCommands[categories] = commands;

    return commands;
}

+ (nullable NSSet<NSString *> *)keyCommandSelectorNamesForCategories:(nullable NSOrderedSet<NSString *> *)categoriesSet;
{
    if (categoriesSet == nil) {
        return nil;
    }
    
    NSArray<NSString *> *names = [categoriesSet array];
    NSString *categories = [names componentsJoinedByString:@","];
    
    NSSet *selectorNames = CategoriesToSelectorNames[categories];
    if (selectorNames != nil) {
        return selectorNames;
    }
    
    NSMutableSet *mergedSelectorNames = [NSMutableSet set];
    NSArray *categoryNames = [categories componentsSeparatedByString:@","];
    for (NSString *categoryName in categoryNames) {
        selectorNames = CategoriesToSelectorNames[categoryName];
        if (selectorNames == nil) {
            NSLog(@"No key command category named \"%@\".", categoryName);
            continue;
        }
        
        [mergedSelectorNames unionSet:selectorNames];
    }
    
    selectorNames = [mergedSelectorNames copy];
    CategoriesToSelectorNames[categories] = selectorNames;
    
    return selectorNames;
}

+ (nullable NSSet<NSString *> *)keyCommandSelectorNamesForKeyCommands:(nullable NSArray<UIKeyCommand *> *)keyCommands;
{
    if (keyCommands == nil) {
        return nil;
    }
    
    NSSet *selectorNames = [KeyCommandsToSelectorNames objectForKey:keyCommands];
    if (selectorNames != nil) {
        return selectorNames;
    }
    
    NSMutableSet *mergedSelectorNames = [NSMutableSet set];
    for (UIKeyCommand *keyCommand in keyCommands) {
        SEL selector = keyCommand.action;
        if (selector != NULL) {
            NSString *selectorName = NSStringFromSelector(selector);
            [mergedSelectorNames addObject:selectorName];
        }
    }
    
    [KeyCommandsToSelectorNames setObject:mergedSelectorNames forKey:keyCommands];
    
    return selectorNames;
}

// Awful approximation for a string that's too long and will break multi-column layout. Useful for discoverability titles that display user configured strings.
// TODO: Consider adding support for string measuring.
static NSUInteger DesiredDiscoverabilityTitleLength = 25;

+ (NSString *)truncatedDiscoverabilityTitle:(NSString *)title;
{
    return [title stringByTruncatingToMaximumLength:DesiredDiscoverabilityTitleLength atSpaceAfterMinimumLength:0];
}

@end

#pragma mark -

@implementation UIResponder (OUIKeyCommandProvider)

- (BOOL)hasKeyCommandWithAction:(SEL)action;
{
    if ([self conformsToProtocol:@protocol(OUIKeyCommandProvider)] || [self respondsToSelector:@selector(keyCommandCategories)]) {
        id responder = self;
        NSOrderedSet<NSString *> *categories = [responder keyCommandCategories];
        if (categories != nil) {
            NSSet *selectorNames = [OUIKeyCommands keyCommandSelectorNamesForCategories:categories];
            if ([selectorNames containsObject:NSStringFromSelector(action)]) {
                return YES;
            }
        }
    }
    
    if ([self conformsToProtocol:@protocol(OUIKeyCommandProvider)] || [self respondsToSelector:@selector(keyCommands)]) {
        // It might be nice, and more efficient, to cache the computed selects for key commands by responder, but we cannot rely on the set of key commands being static over time.
        // One example of this may be an app which vends different key commands for standard and pro editions. (It would be preferable to vend all the commands and disable the pro set, but we cannot rely on that.)
        NSArray<UIKeyCommand *> *keyCommands = self.keyCommands;
        if (keyCommands != nil) {
            NSSet *selectorNames = [OUIKeyCommands keyCommandSelectorNamesForKeyCommands:keyCommands];
            if ([selectorNames containsObject:NSStringFromSelector(action)]) {
                return YES;
            }
        }
    }

    return NO;
}

@end


NS_ASSUME_NONNULL_END
