// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFPreference.h>

#import <OmniDataObjects/ODOFetchExtremum.h>

@class NSPredicate, NSURL, NSError, NSString, NSArray;
@class ODOModel, ODOEntity, ODOAttribute, ODOObjectID, ODOSQLConnection;

NS_ASSUME_NONNULL_BEGIN

/// A marker URL indicating that an ODODatabase is using an in-memory SQLite store rather than creating a file on disk. A URL constructed from this value is legal to pass to -connectToURL:error:, and may be returned from -connectedURL.
extern NSString * const ODODatabaseInMemoryFileURLString;

extern NSInteger ODOSQLDebugLogLevel;

/// ODODatabase represents a single underlying SQLite database which contains a schema corresponding to a particular ODOModel. Most callers should not access an ODODatabase directly; instead, use API on ODOEditingContext and individual ODOObject subclasses to manipulate a persistent data store. However, ODODatabase instances can occasionally offer query capabilities not readily handled by the rest of OmniDataObjects; see the `-fetchCommitted…` methods for examples.
@interface ODODatabase : OFObject

- (instancetype)initWithModel:(ODOModel *)model;

@property (nullable, readonly) ODOSQLConnection *connection;
@property (nullable, readonly) NSURL *connectedURL; // convenience for connection.URL
@property (nonatomic, readonly) ODOModel *model;

- (BOOL)connectToURL:(NSURL *)fileURL readonly:(BOOL)isReadonly error:(NSError **)outError;
- (BOOL)connectToURL:(NSURL *)fileURL error:(NSError **)outError;
- (BOOL)disconnect:(NSError **)outError;

@property(nonatomic, readonly, getter=isFreshlyCreated) BOOL freshlyCreated;

- (void)didSave;

// Values can be any plist type.  Setting a NSNull or nil will cause the metadata value to be removed.  Metadata changes are saved with the next normal save.
- (nullable id)metadataForKey:(NSString *)key;
- (void)setMetadata:(nullable id)value forKey:(NSString *)key;

- (BOOL)writePendingMetadataChanges:(NSError **)outError; // Typically this happens at save time, but we may need to force a write (for example, when closing a store before deleting the cache file)
- (BOOL)deleteCommittedMetadataForKey:(NSString *)key error:(NSError **)outError;

@property(nullable, readonly) NSDictionary *committedMetadata;

/// Query the receiver for the number of rows that have been saved in the table corresponding to the given `entity` and matching the given `predicate`. This offers a convenient shortcut for determining the total number of instances of a particular ODOObject subclass without having to fetch them all (even as faults). This method only counts rows and evaluates the predicate against data that has been committed to the underlying SQLite database; any changes made in memory that have not been saved will not affect the row count.
- (BOOL)fetchCommittedRowCount:(uint64_t *)outRowCount fromEntity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

/// Query the receiver for the sum of the values in the table column corresponding to the given `entity` and `attribute` and matching the given `predicate`. The attribute must have an integer type. This offers a convenient shortcut for summing some property — stored or derived — on all instances of a particular ODOObject subclass without having to fetch them all. This method only sums values and evaluates the predicate against data that has been committed to the underlying SQLite database; any changes made in memory that have not been saved will not affect the sum.
- (BOOL)fetchCommitedInt64Sum:(int64_t *)outSum fromAttribute:(ODOAttribute *)attribute entity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

/// Query the receiver for values for the given `attributes` that have been stored in the table corresponding to the given `entity` and matching the given `predicate`. This offers a convenient shortcut for querying large amounts of data, or only particular attributes, on all instances of a particular ODOObject subclass without having to fully fetch them all. This method only returns values that have been committed to the underlying SQLite database; any changes made in memory that have not been saved will not be reflected in the returned array.
- (nullable NSArray<NSArray<id> *> *)fetchCommittedAttributes:(NSArray<ODOAttribute *> *)attributes fromEntity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

/// Query the receiver for values for the given `attributes` for the row having the minimum or maximum value for another specified `attribute` in the table corresponding to the given `entity` and matching the given `predicate`. This offers a convenient shortcut for determining which instance among many of a particular ODOObject subclass holds the lowest or highest value for a specific property without requiring the caller to fully fetch them all. This method only sorts on and returns values that have been committed to the underlying SQLite database; any changes made in memory that have not been saved will not be reflected in the returned array.
///
/// Regardless of the `predicate` passed, this method adds an "implicit nonnull" predicate for the specified extremum attribute; it will not match rows that have no value for that attribute. In the event that no row matches the given `predicate`, or no row holds a nonnull value for the specified extremum `attribute`, this method will return a nonnull NSArray filled with NSNull instances, one per requested attribute from `attributes`. (This differs from this method returning a nil array, which only occurs in the event of an error.)
- (nullable NSArray<id> *)fetchCommittedAttributes:(NSArray<ODOAttribute *> *)attributes fromEntity:(ODOEntity *)entity havingExtremum:(ODOFetchExtremum)extremum forAttribute:(ODOAttribute *)attribute matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

// Dangerous API
- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;

@end

extern NSNotificationName const ODODatabaseConnectedURLChangedNotification;

NS_ASSUME_NONNULL_END
