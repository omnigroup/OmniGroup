// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDocumentTitle.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWURL.h>
#import <OWF/OWContentType.h>

RCS_ID("$Id$")

@implementation OWDocumentTitle

static NSLock *cacheLock;
static NSMutableDictionary *guessedTitles, *realTitles;
static NSNotificationCenter *notificationCenter;

+ (void)_flushCache:(NSNotification *)notification;
{
    [cacheLock lock];
    [guessedTitles removeAllObjects];
    [realTitles removeAllObjects];
    [cacheLock unlock];
}

+ (void)initialize;
{
    OBINITIALIZE;

    cacheLock = [[NSLock alloc] init];
    guessedTitles = [[NSMutableDictionary alloc] init];
    realTitles = [[NSMutableDictionary alloc] init];
    notificationCenter = [[NSNotificationCenter alloc] init];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_flushCache:) name:OWContentCacheFlushNotification object:nil];
}


+ (NSString *)titleForAddress:(OWAddress *)address;
{
    NSString *cacheKey = [address cacheKey];
    [cacheLock lock];
    NSString *title = [guessedTitles objectForKey:cacheKey];
    [cacheLock unlock];
    return title;
}

+ (void)cacheRealTitle:(NSString *)aTitle forAddress:(OWAddress *)anAddress;
{
    if (anAddress == nil)
	return;

    NSString *cacheKey = [anAddress cacheKey];
    NSString *cacheValue = [aTitle copy];
    [cacheLock lock];
    if (![NSString isEmptyString:aTitle]) {
        [realTitles setObject:cacheValue forKey:cacheKey];
        [guessedTitles setObject:cacheValue forKey:cacheKey];
    } else {
        [realTitles removeObjectForKey:cacheKey];
    }
    [cacheLock unlock];

    // Give the UI a chance to respond
    [self postNotificationForAddress:anAddress];
}

+ (void)cacheGuessTitle:(NSString *)aTitle forAddress:(OWAddress *)anAddress;
{
    if (anAddress == nil || aTitle == nil || [aTitle isEqualToString:@""])
	return;
    
    NSString *cacheKey = [anAddress cacheKey];
    NSString *cacheValue = [aTitle copy];
    [cacheLock lock];
    if ([realTitles objectForKey:cacheKey] == nil)
        [guessedTitles setObject:cacheValue forKey:cacheKey];
    [cacheLock unlock];
}

+ (void)invalidateGuessTitleForAddress:(OWAddress *)anAddress;
{
    if (anAddress == nil)
        return;

    NSString *cacheKey = [anAddress cacheKey];
    [cacheLock lock];
    NSString *title = [realTitles objectForKey:cacheKey];
    if (title != nil)
        [guessedTitles setObject:title forKey:cacheKey];
    else if ([guessedTitles objectForKey:cacheKey] != nil)
        [guessedTitles removeObjectForKey:cacheKey];
    [cacheLock unlock];
}

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector address:(OWAddress *)anAddress;
{
    [notificationCenter addObserver:anObserver selector:aSelector name:[anAddress cacheKey] object:nil];
    
    if ([[[anAddress url] path] length]) {
        NSString *baseKey = [[anAddress addressWithPath:@""] cacheKey];
        [notificationCenter addObserver:anObserver selector:aSelector name:baseKey object:nil];
    }
}

+ (void)removeObserver:(id)anObserver address:(OWAddress *)anAddress;
{
    [notificationCenter removeObserver:anObserver name:[anAddress cacheKey] object:nil];
    
    if ([[[anAddress url] path] length]) {
        NSString *baseKey = [[anAddress addressWithPath:@""] cacheKey];
        [notificationCenter removeObserver:anObserver name:baseKey object:nil];
    }
}

+ (void)removeObserver:(id)anObserver;
{
    [notificationCenter removeObserver:anObserver];
}

+ (void)postNotificationForAddress:(OWAddress *)anAddress;
{
    [notificationCenter mainThreadPostNotificationName:[anAddress cacheKey] object:anAddress];
}

@end
